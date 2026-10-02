import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/training/execution/templado_screen.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/training/training_models.dart';
import 'package:naguan_app/training/training_services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/forja_headline.dart';
import 'package:naguan_app/theme/one_line_text.dart';

/// La ejecución de una Fragua: paso a paso, con cuenta regresiva en los
/// ejercicios por tiempo y en los descansos.
///
/// La lógica vive en [WorkoutRunner]; esta pantalla lo crea, le da cuerda con
/// un Timer y lo dibuja con un ListenableBuilder.
class ExecutionScreen extends StatefulWidget {
  const ExecutionScreen({
    super.key,
    required this.session,
    required this.catalog,
    required this.training,
    this.restored,
    this.clock,
    this.keepScreenOn = true,
  });

  final Session session;

  /// Para abrir un ejercicio en medio de la Fragua (cómo se hace).
  final CatalogClient catalog;
  final TrainingServices training;

  /// El snapshot de una Fragua interrumpida, para retomarla. Null: una
  /// Fragua nueva.
  final Map<String, dynamic>? restored;

  /// Reloj inyectable para los tests (por defecto, la hora real).
  final DateTime Function()? clock;

  /// Mantener la pantalla encendida mientras se entrena. Los tests lo
  /// apagan: no hay plugin nativo en un widget test.
  final bool keepScreenOn;

  @override
  State<ExecutionScreen> createState() => _ExecutionScreenState();
}

class _ExecutionScreenState extends State<ExecutionScreen> {
  late final WorkoutRunner _runner;
  Timer? _ticker;

  /// Estado del registro al terminar: null mientras se entrena.
  Future<void>? _saving;

  /// Lo último guardado en el teléfono: la revisión del runner y cuándo.
  int _savedRevision = -1;
  DateTime _savedAt = DateTime(0);

  /// Cada cuánto se guarda aunque no haya cambios: así, si la app se
  /// cierra, al retomar se pierden como mucho estos segundos.
  static const _heartbeat = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    final restored = widget.restored;
    _runner = restored != null
        ? WorkoutRunner.restore(widget.session, restored, clock: widget.clock)
        : (WorkoutRunner(widget.session, clock: widget.clock)..start());

    // Pantalla encendida mientras dure la Fragua: sin esto, el teléfono la
    // apaga en un descanso largo (y la cuenta regresiva no se ve).
    if (widget.keepScreenOn) WakelockPlus.enable();

    // El Timer le "da cuerda" al runner 4 veces por segundo: tick()
    // recalcula el tiempo desde la hora real y avanza si hace falta. La
    // precisión no depende del Timer: si se atrasa, el próximo tick corrige.
    _ticker = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _onTick(),
    );
  }

  @override
  void dispose() {
    // Un Timer periódico sigue vivo aunque la pantalla se cierre: hay que
    // cancelarlo, o seguiría llamando a un runner descartado.
    _ticker?.cancel();
    if (widget.keepScreenOn) WakelockPlus.disable();
    _runner.dispose();
    super.dispose();
  }

  void _onTick() {
    if (_runner.tick()) {
      // Terminó un tiempo (ejercicio o descanso): vibración para avisar sin
      // tener que mirar la pantalla.
      HapticFeedback.heavyImpact();
    }
    _persist();
    if (_runner.isFinished && _saving == null) _save();
  }

  /// Guarda el snapshot en el teléfono si cambió algo (otro paso, reps,
  /// pausa) o si pasó el heartbeat. No en cada tick: escribir al disco 4
  /// veces por segundo es gasto inútil.
  void _persist() {
    final now = DateTime.now();
    if (_runner.revision == _savedRevision &&
        now.difference(_savedAt) < _heartbeat) {
      return;
    }
    _savedRevision = _runner.revision;
    _savedAt = now;
    // unawaited: se lanza y no se espera (un tick no tiene que esperar al
    // disco). Si falla, el próximo guardado lo corrige.
    unawaited(
      widget.training.activeWorkout.save(widget.session, _runner.toSnapshot()),
    );
  }

  void _save() {
    _ticker?.cancel();
    setState(() {
      _saving = _record();
    });
  }

  /// Registra la Fragua. Sin señal (o con el servidor caído), la deja en la
  /// cola para registrarla después: lo entrenado no se pierde.
  Future<void> _record() async {
    final workout = _runner.toNewWorkout();
    final training = widget.training;
    WorkoutResult? result;
    try {
      result = await training.client.recordWorkout(workout);
    } on ApiException catch (e) {
      final status = e.statusCode;
      // Un 4xx es un dato inválido: reintentar daría lo mismo, se muestra.
      if (status != null && status < 500) rethrow;
      await training.pending.add(workout);
    }
    // Registrada o encolada: ya no hay una Fragua "en curso" que retomar.
    await training.activeWorkout.clear();
    if (!mounted) return;
    // pushReplacement reemplaza esta pantalla por la de TEMPLADO: "atrás"
    // desde el resumen vuelve a la sesión, no a una ejecución terminada.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TempladoScreen(
          session: widget.session,
          workout: workout,
          result: result,
          exercises: _runner.completedExercises,
        ),
      ),
    );
  }

  /// Abre la pantalla de un ejercicio sin salir de la Fragua: se apila
  /// encima, y "atrás" vuelve acá.
  ///
  /// Antes pausa: mirar el video no tiene que consumir el tiempo del paso.
  /// Al volver queda pausada a propósito (se sigue con ▶ cuando estés en
  /// posición); retomarla sola arrancaría la cuenta antes de acomodarse.
  ///
  /// Esta pantalla sigue montada debajo mientras tanto: el Timer sigue
  /// andando, pero tick() no hace nada con el runner pausado.
  void _openExercise(ExerciseRef exercise) {
    _runner.pause();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ExerciseScreen(catalog: widget.catalog, slug: exercise.slug),
      ),
    );
  }

  /// Descarta una Fragua que la API rechazó (un 4xx).
  Future<void> _discard() async {
    await widget.training.activeWorkout.clear();
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿DEJAR LA FRAGUA?'),
        content: const Text('Lo hecho hasta ahora no se registra.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const OneLineText('SEGUIR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const OneLineText('DEJAR'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // PopScope intercepta el "atrás" (botón o gesto): en vez de salir de
    // golpe a mitad de una Fragua, se pide confirmación.
    return PopScope(
      canPop: _saving != null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          // Abandonada: no queda nada que retomar.
          await widget.training.activeWorkout.clear();
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.session.title.toUpperCase())),
        body: SafeArea(
          child: _saving != null
              ? _SavingView(
                  future: _saving!,
                  onRetry: _save,
                  onDiscard: _discard,
                )
              // ListenableBuilder se reconstruye cada vez que el runner
              // llama a notifyListeners(): solo esta parte del árbol, no la
              // pantalla entera.
              : ListenableBuilder(
                  listenable: _runner,
                  builder: (context, _) => _runner.isFinished
                      ? const Center(child: CircularProgressIndicator())
                      : _StepView(
                          runner: _runner,
                          onOpenExercise: _openExercise,
                        ),
                ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({required this.runner, required this.onOpenExercise});

  final WorkoutRunner runner;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final step = runner.current;

    return Padding(
      padding: const EdgeInsets.all(ForjaSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Barra de progreso de la Fragua entera: el acento marca el avance.
          LinearProgressIndicator(
            value: runner.progress,
            minHeight: ForjaSpace.s2,
            borderRadius: BorderRadius.zero,
          ),
          const SizedBox(height: ForjaSpace.s4),
          Row(
            children: [
              Expanded(
                child: Text(_stepLabel(step), style: textTheme.labelSmall),
              ),
              // Una Fragua retomada arranca pausada: que se note.
              if (runner.isPaused) ...[
                const SizedBox(width: ForjaSpace.s2),
                const ForjaPill('en pausa'),
              ],
            ],
          ),
          // Expanded + Center: el contenido del paso ocupa el centro de la
          // pantalla, y los botones quedan abajo, al alcance del pulgar.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: switch (step.kind) {
                  StepKind.reps => _RepsStep(
                    runner: runner,
                    onOpenExercise: onOpenExercise,
                  ),
                  StepKind.timed => _TimedStep(
                    runner: runner,
                    onOpenExercise: onOpenExercise,
                  ),
                  StepKind.rest => _RestStep(runner: runner),
                  StepKind.amrap => _AmrapStep(
                    runner: runner,
                    onOpenExercise: onOpenExercise,
                  ),
                },
              ),
            ),
          ),
          if (runner.next case final next?) ...[
            _NextStep(step: next, onOpenExercise: onOpenExercise),
            const SizedBox(height: ForjaSpace.s4),
          ],
          _Controls(runner: runner),
        ],
      ),
    );
  }

  String _stepLabel(WorkoutStep step) {
    final block = 'BLOQUE ${step.block.position} · ${step.block.type.label}';
    if (step.kind == StepKind.amrap || step.roundCount <= 1) return block;
    return '$block · VUELTA ${step.round} / ${step.roundCount}';
  }
}

/// Lo que sigue. Si es un ejercicio, se puede tocar para ver cómo se hace:
/// sirve sobre todo en un Enfriá, para prepararse para el próximo.
class _NextStep extends StatelessWidget {
  const _NextStep({required this.step, required this.onOpenExercise});

  final WorkoutStep step;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SIGUE', style: textTheme.labelSmall),
        const SizedBox(height: ForjaSpace.s1),
        Text(_describe(step), style: textTheme.bodyLarge),
      ],
    );

    final exercise = step.item?.exercise;
    if (exercise == null) return content;
    return InkWell(
      onTap: () => onOpenExercise(exercise),
      child: Row(
        children: [
          Expanded(child: content),
          Icon(Icons.chevron_right, color: context.forja.palette.inkMuted),
        ],
      ),
    );
  }
}

/// "Flexión ×10", "Plancha 45 s", "Enfriá 20 s".
String _describe(WorkoutStep step) {
  final item = step.item;
  if (item == null) return 'AMRAP ${formatDuration(step.block.timeCapS!)}';
  if (item.isRest) return 'Enfriá ${formatDuration(item.durationS!)}';
  final metric = item.reps != null
      ? formatReps(item.reps!)
      : formatDuration(item.durationS!);
  final side = item.side != null ? ' (${item.side!.label.toLowerCase()})' : '';
  return '${item.exercise!.name}$side $metric';
}

/// Nombre del ejercicio y su lado: común a los pasos de ejercicio.
class _ExerciseHeader extends StatelessWidget {
  const _ExerciseHeader({required this.item, required this.onOpenExercise});

  final Item item;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        ForjaHeadline(
          item.exercise!.name.toUpperCase(),
          style: textTheme.displayMedium,
          textAlign: TextAlign.center,
        ),
        if (item.side case final side?) ...[
          const SizedBox(height: ForjaSpace.s2),
          ForjaPill(side.label),
        ],
        const SizedBox(height: ForjaSpace.s2),
        TextButton(
          onPressed: () => onOpenExercise(item.exercise!),
          child: const OneLineText('CÓMO SE HACE'),
        ),
      ],
    );
  }
}

/// La cuenta regresiva en grande, en el estilo `stat` (mono tabular: los
/// dígitos no "bailan" al cambiar).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    // Se redondea hacia arriba: con 0,4 s restantes se muestra "1", y el
    // "0" aparece recién cuando el paso termina.
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final text = seconds >= 60
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '$seconds';
    return Text(
      text,
      style: context.forja.stat.copyWith(fontSize: 96, height: 1),
      textAlign: TextAlign.center,
    );
  }
}

class _RepsStep extends StatelessWidget {
  const _RepsStep({required this.runner, required this.onOpenExercise});

  final WorkoutRunner runner;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final stat = context.forja.stat.copyWith(fontSize: 96, height: 1);
    return Column(
      children: [
        _ExerciseHeader(
          item: runner.current.item!,
          onOpenExercise: onOpenExercise,
        ),
        const SizedBox(height: ForjaSpace.s8),
        // Las reps hechas, ajustables: arrancan en las indicadas.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              onPressed: () => runner.adjustReps(-1),
              icon: const Icon(Icons.remove),
              tooltip: 'Una menos',
            ),
            const SizedBox(width: ForjaSpace.s4),
            Text('${runner.repsDraft}', style: stat),
            const SizedBox(width: ForjaSpace.s4),
            IconButton.outlined(
              onPressed: () => runner.adjustReps(1),
              icon: const Icon(Icons.add),
              tooltip: 'Una más',
            ),
          ],
        ),
        const SizedBox(height: ForjaSpace.s2),
        Text('REPS', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _TimedStep extends StatelessWidget {
  const _TimedStep({required this.runner, required this.onOpenExercise});

  final WorkoutRunner runner;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ExerciseHeader(
          item: runner.current.item!,
          onOpenExercise: onOpenExercise,
        ),
        const SizedBox(height: ForjaSpace.s8),
        _Countdown(remaining: runner.remaining!),
      ],
    );
  }
}

class _RestStep extends StatelessWidget {
  const _RestStep({required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ForjaHeadline(
          'ENFRIÁ',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        const SizedBox(height: ForjaSpace.s8),
        _Countdown(remaining: runner.remaining!),
      ],
    );
  }
}

class _AmrapStep extends StatelessWidget {
  const _AmrapStep({required this.runner, required this.onOpenExercise});

  final WorkoutRunner runner;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final block = runner.current.block;
    return Column(
      children: [
        ForjaHeadline('AMRAP', style: textTheme.displayLarge),
        const SizedBox(height: ForjaSpace.s2),
        const Text(
          'Repetí la vuelta hasta que se acabe el tiempo.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ForjaSpace.s6),
        _Countdown(remaining: runner.remaining!),
        const SizedBox(height: ForjaSpace.s6),
        // Cada ejercicio de la vuelta se puede tocar (los descansos no).
        for (final item in block.items)
          InkWell(
            onTap: item.exercise == null
                ? null
                : () => onOpenExercise(item.exercise!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s1),
              child: Text(
                _describe(
                  WorkoutStep(
                    kind: StepKind.reps,
                    block: block,
                    roundCount: 1,
                    item: item,
                  ),
                ),
                style: textTheme.bodyLarge,
              ),
            ),
          ),
        const SizedBox(height: ForjaSpace.s6),
        OutlinedButton(
          onPressed: runner.addAmrapRound,
          child: OneLineText('+1 VUELTA · ${runner.amrapRounds}'),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    final kind = runner.current.kind;
    // El botón de pausa/seguir: en los pasos con tiempo, y en cualquier paso
    // si está pausado (una Fragua retomada arranca así).
    final hasTimer = kind != StepKind.reps || runner.isPaused;

    return Row(
      children: [
        if (hasTimer)
          IconButton.outlined(
            onPressed: runner.isPaused ? runner.resume : runner.pause,
            icon: Icon(runner.isPaused ? Icons.play_arrow : Icons.pause),
            tooltip: runner.isPaused ? 'Seguir' : 'Pausar',
          ),
        if (hasTimer) const SizedBox(width: ForjaSpace.s2),
        TextButton(onPressed: runner.skip, child: const OneLineText('SALTEAR')),
        const SizedBox(width: ForjaSpace.s2),
        // El CTA principal: el único bloque de acento grande de la pantalla.
        Expanded(
          child: FilledButton(
            onPressed: runner.complete,
            child: OneLineText(switch (kind) {
              StepKind.reps => 'LISTO',
              StepKind.timed => 'TERMINÉ',
              StepKind.rest => 'SEGUIR',
              StepKind.amrap => 'TERMINAR',
            }),
          ),
        ),
      ],
    );
  }
}

/// Mientras se registra la Fragua en la API: cargando, o el error con
/// reintento. Sin señal no llega acá (va a la cola): esto es un rechazo de
/// la API, que se puede reintentar o descartar.
class _SavingView extends StatelessWidget {
  const _SavingView({
    required this.future,
    required this.onRetry,
    required this.onDiscard,
  });

  final Future<void> future;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<void>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.error case final error?) {
          final message = error is ApiException
              ? error.message
              : 'No se pudo registrar.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(ForjaSpace.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('NO SE REGISTRÓ', style: textTheme.titleLarge),
                  const SizedBox(height: ForjaSpace.s2),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: ForjaSpace.s6),
                  FilledButton(
                    onPressed: onRetry,
                    child: const OneLineText('REINTENTAR'),
                  ),
                  const SizedBox(height: ForjaSpace.s2),
                  TextButton(
                    onPressed: onDiscard,
                    child: const OneLineText('DESCARTAR'),
                  ),
                ],
              ),
            ),
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: ForjaSpace.s4),
              Text('TEMPLANDO', style: textTheme.labelSmall),
            ],
          ),
        );
      },
    );
  }
}
