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
/// Una Fragua nueva empieza en PRIMER GOLPE (qué se viene, para acomodarse)
/// y arranca con EMPEZAR; una retomada va directo al paso donde quedó.
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
    // Una Fragua nueva no arranca acá: espera al EMPEZAR de PRIMER GOLPE.
    _runner = restored != null
        ? WorkoutRunner.restore(widget.session, restored, clock: widget.clock)
        : WorkoutRunner(widget.session, clock: widget.clock);

    unawaited(_loadLastLoads());

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

  /// Los últimos pesos, para que el runner los proponga: primero los del
  /// teléfono (llegan enseguida, aun sin señal) y después los de la API. Se
  /// cargan mientras el usuario mira PRIMER GOLPE, antes de EMPEZAR, que es
  /// cuando el runner calcula la propuesta del primer paso.
  Future<void> _loadLastLoads() async {
    final loads = widget.training.lastLoads;
    _runner.lastLoads = await loads.cached();
    _runner.lastLoads = await loads.refresh(widget.training.client);
  }

  void _onTick() {
    if (_runner.tick() case final cue?) {
      widget.training.beeper.play(cue);
      // En el 0 (arranca o termina un tiempo), además, vibración: avisa
      // aunque el teléfono esté sin volumen.
      if (cue == Cue.go) HapticFeedback.heavyImpact();
    }
    _persist();
    if (_runner.isFinished && _saving == null) _save();
  }

  /// Guarda el snapshot en el teléfono si cambió algo (otro paso, reps,
  /// pausa) o si pasó el heartbeat. No en cada tick: escribir al disco 4
  /// veces por segundo es gasto inútil.
  void _persist() {
    // Antes de EMPEZAR no hay nada que retomar.
    if (!_runner.isStarted) return;
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

  /// EMPEZAR: arranca la Fragua. Con setState y no solo con el runner: el
  /// PopScope de [build] depende de si empezó (antes, "atrás" sale sin
  /// preguntar), y PopScope está fuera del ListenableBuilder.
  void _start() => setState(_runner.start);

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
    // Los pesos de hoy, para proponerlos la próxima vez aunque esta Fragua
    // haya quedado en la cola.
    await training.lastLoads.remember(_runner.usedLoads);
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
      canPop: _saving != null || !_runner.isStarted,
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
                  builder: (context, _) => switch (_runner) {
                    WorkoutRunner(isStarted: false) => _ReadyView(
                      runner: _runner,
                      onStart: _start,
                      onOpenExercise: _openExercise,
                    ),
                    WorkoutRunner(isFinished: true) => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    _ => _StepView(
                      runner: _runner,
                      onOpenExercise: _openExercise,
                    ),
                  },
                ),
        ),
      ),
    );
  }
}

/// PRIMER GOLPE: lo primero que se hace, antes de arrancar el reloj. Da
/// tiempo de acomodarse (y de ver cómo se hace) sin que corra nada.
class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.runner,
    required this.onStart,
    required this.onOpenExercise,
  });

  final WorkoutRunner runner;
  final VoidCallback onStart;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final first = runner.steps.first;
    final item = first.item;

    return Padding(
      padding: const EdgeInsets.all(ForjaSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('PRIMER GOLPE', style: textTheme.labelSmall),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Un ejercicio muestra su nombre (y CÓMO SE HACE); un
                    // AMRAP o un Enfriá de entrada, su nombre de paso.
                    if (item?.exercise != null)
                      _ExerciseHeader(
                        item: item!,
                        onOpenExercise: onOpenExercise,
                      )
                    else
                      ForjaHeadline(switch (first.kind) {
                        StepKind.amrap => 'AMRAP',
                        StepKind.pyramid => 'PIRÁMIDE',
                        _ => 'ENFRIÁ',
                      }, style: textTheme.displayMedium),
                    const SizedBox(height: ForjaSpace.s6),
                    Text(
                      _metric(first),
                      style: context.forja.stat.copyWith(fontSize: 64),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Subí el volumen: los tiempos arrancan con 3, 2, 1.',
            style: textTheme.bodyMedium?.copyWith(
              color: context.forja.palette.inkMuted,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ForjaSpace.s4),
          FilledButton(onPressed: onStart, child: const OneLineText('EMPEZAR')),
        ],
      ),
    );
  }

  /// "×10", "45″", o el tope de un AMRAP.
  static String _metric(WorkoutStep step) => switch (step) {
    WorkoutStep(item: Item(reps: final reps?)) => formatReps(reps),
    _ => formatDuration(step.duration!.inSeconds),
  };
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
              // Una Fragua retomada arranca pausada: que se note (la oferta
              // de un opcional también pausa, pero ahí se ve sola).
              if (runner.isPaused && !runner.isOfferingOptional) ...[
                const SizedBox(width: ForjaSpace.s2),
                const ForjaPill('en pausa'),
              ],
            ],
          ),
          // La indicación del bloque, para el momento (el ritmo).
          if (step.block.note case final note?) ...[
            const SizedBox(height: ForjaSpace.s2),
            Text(note, style: context.forja.bodyStrong),
          ],
          // Expanded + Center: el contenido del paso ocupa el centro de la
          // pantalla, y los botones quedan abajo, al alcance del pulgar.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: runner.isOfferingOptional
                    ? _OptionalOffer(runner: runner)
                    : switch (step.kind) {
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
                        StepKind.pyramid => _PyramidStep(
                          runner: runner,
                          onOpenExercise: onOpenExercise,
                        ),
                      },
              ),
            ),
          ),
          if (runner.next case final next? when !runner.isOfferingOptional) ...[
            _NextStep(step: next, onOpenExercise: onOpenExercise),
            const SizedBox(height: ForjaSpace.s4),
          ],
          // Mientras se ofrece el opcional, los botones son los de la oferta.
          if (!runner.isOfferingOptional) _Controls(runner: runner),
        ],
      ),
    );
  }

  String _stepLabel(WorkoutStep step) {
    // En el calentamiento y la movilidad, la parte dice más que el número
    // y el tipo del bloque (que son siempre VUELTAS).
    final block = step.block.phase == BlockPhase.main
        ? 'BLOQUE ${step.block.position} · ${step.block.type.label}'
        : step.block.phase.label;
    if (step.kind == StepKind.amrap ||
        step.kind == StepKind.pyramid ||
        step.roundCount <= 1) {
      return block;
    }
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
  if (item == null) {
    final kind = step.kind == StepKind.pyramid ? 'Pirámide' : 'AMRAP';
    return '$kind ${formatDuration(step.block.timeCapS!)}';
  }
  if (item.isRest) return 'Enfriá ${formatDuration(item.durationS!)}';
  final metric = formatTarget(item);
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
  const _Countdown({required this.remaining, this.color});

  final Duration remaining;

  /// Null: el color del texto (ink).
  final Color? color;

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
      style: context.forja.stat.copyWith(fontSize: 96, height: 1, color: color),
      textAlign: TextAlign.center,
    );
  }
}

/// El reloj de un paso con tiempo: durante la preparación, el 3, 2, 1 en
/// acento con PREPARATE; después, lo que le queda al paso.
class _StepClock extends StatelessWidget {
  const _StepClock({required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    final preparation = runner.preparationLeft;
    return Column(
      children: [
        _Countdown(
          // Un ítem del máximo tiempo posible no tiene "lo que queda": en la
          // preparación se muestra la cuenta, después lo transcurrido.
          remaining: preparation ?? runner.remaining ?? runner.elapsedInStep,
          color: preparation != null ? context.forja.palette.accent : null,
        ),
        const SizedBox(height: ForjaSpace.s2),
        // Visibility con maintainSize: oculto, PREPARATE sigue ocupando su
        // lugar. Si desapareciera, todo lo de arriba saltaría al arrancar.
        Visibility(
          visible: preparation != null,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Text(
            'PREPARATE',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
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
        Text(
          _repsLabel(runner.current.item!),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: ForjaSpace.s6),
        _LoadControl(runner: runner),
      ],
    );
  }
}

/// El peso del paso: − y + de a [WorkoutRunner.loadStep], y tocando el
/// número se escribe el exacto (1,25, una kettlebell de 14...). En un
/// ejercicio sin carga, un + LASTRE para sumarle peso (solo en el
/// entrenamiento: en el calentamiento y la movilidad no tiene sentido).
class _LoadControl extends StatelessWidget {
  const _LoadControl({required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    final step = runner.current;
    if (!runner.showsLoad) {
      if (step.block.phase != BlockPhase.main) return const SizedBox.shrink();
      return TextButton(
        onPressed: () => runner.adjustLoad(WorkoutRunner.loadStep),
        child: const OneLineText('+ LASTRE'),
      );
    }
    final load = runner.loadDraft;
    final stat = context.forja.stat.copyWith(fontSize: 48, height: 1);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.outlined(
              // Sin peso no hay qué bajar: el botón queda deshabilitado.
              onPressed: load == null
                  ? null
                  : () => runner.adjustLoad(-WorkoutRunner.loadStep),
              icon: const Icon(Icons.remove),
              tooltip: 'Menos peso',
            ),
            const SizedBox(width: ForjaSpace.s4),
            InkWell(
              onTap: () => _edit(context),
              child: Text(
                load == null ? '—' : formatKgNumber(load),
                style: stat,
              ),
            ),
            const SizedBox(width: ForjaSpace.s4),
            IconButton.outlined(
              onPressed: () => runner.adjustLoad(WorkoutRunner.loadStep),
              icon: const Icon(Icons.add),
              tooltip: 'Más peso',
            ),
          ],
        ),
        const SizedBox(height: ForjaSpace.s2),
        Text(
          step.item!.exercise!.loaded ? 'KG' : 'KG DE LASTRE',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  /// Escribir el peso exacto (ver [_LoadDialog]).
  Future<void> _edit(BuildContext context) async {
    final kg = await showDialog<double>(
      context: context,
      builder: (_) => _LoadDialog(initial: runner.loadDraft),
    );
    if (kg != null) runner.setLoad(kg);
  }
}

/// El diálogo para escribir el peso. Es un StatefulWidget para que el
/// TextEditingController viva lo mismo que el diálogo: se crea en initState
/// y se libera en dispose, que Flutter llama recién cuando el diálogo sale
/// del árbol (después de su animación de cierre).
///
/// Liberarlo apenas vuelve showDialog, como se hacía antes, rompe en debug:
/// el diálogo todavía se está cerrando en pantalla y su TextField sigue
/// usando el controller ("_dependents.isEmpty: is not true").
class _LoadDialog extends StatefulWidget {
  const _LoadDialog({required this.initial});

  final double? initial;

  @override
  State<_LoadDialog> createState() => _LoadDialogState();
}

class _LoadDialogState extends State<_LoadDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _controller = TextEditingController(
      text: initial == null ? '' : formatKgNumber(initial),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Acepta coma o punto decimal; vacío o 0, sin carga.
  void _submit() => Navigator.of(context)
      .pop(double.tryParse(_controller.text.trim().replaceAll(',', '.')) ?? 0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PESO'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        // El teclado numérico con decimales (en Android, con coma o punto
        // según el idioma del teléfono).
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(suffixText: 'kg'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const OneLineText('CANCELAR'),
        ),
        TextButton(onPressed: _submit, child: const OneLineText('LISTO')),
      ],
    );
  }
}

/// Qué se cuenta: «REPS», un rango («REPS · DE 5 A 8») o «TODAS LAS QUE
/// PUEDAS» (el número es una referencia).
String _repsLabel(Item item) => switch (item) {
  Item(open: true) => 'TODAS LAS QUE PUEDAS',
  Item(:final repsMin?, :final reps?) => 'REPS · DE $repsMin A $reps',
  _ => 'REPS',
};

/// Un bloque opcional (el «ejercicio extra»): antes de empezarlo, hacerlo o
/// terminar ahí. La Fragua queda en pausa mientras tanto.
class _OptionalOffer extends StatelessWidget {
  const _OptionalOffer({required this.runner});

  final WorkoutRunner runner;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        ForjaHeadline('EXTRA', style: textTheme.displayLarge),
        const SizedBox(height: ForjaSpace.s2),
        const Text(
          'Hacelo solo si te quedan fuerzas.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: ForjaSpace.s4),
        // Lo que tiene el bloque: así se decide sabiendo qué es.
        for (final step in runner.steps)
          if (identical(step.block, runner.current.block) &&
              step.round == 1 &&
              step.item != null &&
              !step.item!.isRest)
            Text(_describe(step), style: textTheme.bodyLarge),
        const SizedBox(height: ForjaSpace.s6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: runner.acceptOptional,
            child: const OneLineText('HACERLO'),
          ),
        ),
        const SizedBox(height: ForjaSpace.s2),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: runner.skipOptional,
            child: const OneLineText('TERMINAR ACÁ'),
          ),
        ),
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
    final item = runner.current.item!;
    final stat = context.forja.stat.copyWith(fontSize: 96, height: 1);
    return Column(
      children: [
        _ExerciseHeader(item: item, onOpenExercise: onOpenExercise),
        const SizedBox(height: ForjaSpace.s8),
        if (runner.isAskingReps) ...[
          // Terminó el tiempo de un ítem que cuenta las reps: cuántas.
          Text(
            '¿CUÁNTAS HICISTE?',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: ForjaSpace.s2),
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
        ] else if (item.open && !runner.isPreparing) ...[
          // El máximo tiempo posible: el reloj cuenta hacia arriba, y se
          // termina con TERMINÉ.
          _Countdown(remaining: runner.elapsedInStep),
          const SizedBox(height: ForjaSpace.s2),
          Text(
            'TODO EL TIEMPO QUE PUEDAS',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ] else
          _StepClock(runner: runner),
        const SizedBox(height: ForjaSpace.s6),
        _LoadControl(runner: runner),
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
        _StepClock(runner: runner),
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

/// Una pirámide con tope: el peldaño actual (o el descanso entre peldaños),
/// el tiempo que le queda al bloque, BAJAR al llegar al máximo y TERMINAR
/// antes de tiempo. El peldaño se marca con el CTA (HECHO).
class _PyramidStep extends StatelessWidget {
  const _PyramidStep({required this.runner, required this.onOpenExercise});

  final WorkoutRunner runner;
  final ValueChanged<ExerciseRef> onOpenExercise;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.forja.palette;
    final block = runner.current.block;

    // La preparación (3, 2, 1) antes de arrancar: como cualquier paso con
    // tiempo.
    if (runner.isPreparing) {
      return Column(
        children: [
          ForjaHeadline('PIRÁMIDE', style: textTheme.displayLarge),
          const SizedBox(height: ForjaSpace.s6),
          _StepClock(runner: runner),
        ],
      );
    }

    final rest = runner.pyramidRestLeft;
    return Column(
      children: [
        // Lo que le queda al bloque, chico: lo grande es el peldaño.
        Text(
          'QUEDAN ${_clock(runner.remaining!)}',
          style: textTheme.labelSmall,
        ),
        const SizedBox(height: ForjaSpace.s4),
        if (rest != null) ...[
          ForjaHeadline('ENFRIÁ', style: textTheme.displayMedium),
          const SizedBox(height: ForjaSpace.s2),
          _Countdown(remaining: rest, color: palette.accent),
          const SizedBox(height: ForjaSpace.s2),
          Text('SIGUE EL PELDAÑO ${runner.rung}', style: textTheme.labelSmall),
        ] else ...[
          Text('PELDAÑO', style: textTheme.labelSmall),
          Text(
            '${runner.rung}',
            style: context.forja.stat.copyWith(fontSize: 96, height: 1),
          ),
        ],
        const SizedBox(height: ForjaSpace.s4),
        // Cada ejercicio con las reps de este peldaño: el número × su
        // incremento (de a 1 en Desencadenado, de a 2 en Kettlebell).
        for (final item in block.items)
          if (item.exercise case final exercise?)
            InkWell(
              onTap: () => onOpenExercise(exercise),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s1),
                child: Text(
                  '${exercise.name}'
                  '${item.side != null ? ' (${item.side!.label.toLowerCase()})' : ''}'
                  ' ${formatReps(runner.rung * (item.reps ?? 1))}',
                  style: textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        const SizedBox(height: ForjaSpace.s2),
        Text(
          'PICO ${runner.pyramidPeak} · ${runner.rungSum} EN TOTAL',
          style: textTheme.labelSmall,
        ),
        const SizedBox(height: ForjaSpace.s4),
        // Wrap: en un teléfono angosto, los dos botones pueden no entrar en
        // un renglón.
        Wrap(
          alignment: WrapAlignment.center,
          spacing: ForjaSpace.s2,
          runSpacing: ForjaSpace.s2,
          children: [
            // BAJAR: solo subiendo, y con al menos un peldaño hecho.
            if (!runner.isDescending && runner.pyramidPeak > 0)
              OutlinedButton(
                onPressed: runner.pyramidDown,
                child: const OneLineText('BAJAR'),
              ),
            TextButton(
              onPressed: runner.finishPyramid,
              child: const OneLineText('TERMINAR PIRÁMIDE'),
            ),
          ],
        ),
      ],
    );
  }

  /// "5:32" o "45″": lo que le queda al bloque.
  static String _clock(Duration d) {
    final seconds = (d.inMilliseconds / 1000).ceil();
    return seconds >= 60
        ? '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : formatDuration(seconds);
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
        // Volver y saltear, como íconos: con texto (ATRÁS, SALTEAR) no
        // entran junto al CTA en un teléfono de 360 dp.
        IconButton.outlined(
          // null deshabilita el botón: en el primer ejercicio no hay atrás.
          onPressed: runner.canGoBack ? runner.back : null,
          icon: const Icon(Icons.skip_previous),
          tooltip: 'Volver al anterior',
        ),
        const SizedBox(width: ForjaSpace.s2),
        IconButton.outlined(
          onPressed: runner.skip,
          icon: const Icon(Icons.skip_next),
          tooltip: 'Saltear',
        ),
        const SizedBox(width: ForjaSpace.s2),
        // El CTA principal: el único bloque de acento grande de la pantalla.
        Expanded(
          child: FilledButton(
            onPressed: runner.complete,
            child: OneLineText(switch (kind) {
              StepKind.reps => 'LISTO',
              StepKind.timed => runner.isAskingReps ? 'LISTO' : 'TERMINÉ',
              StepKind.rest => 'SEGUIR',
              StepKind.amrap => 'TERMINAR',
              // En la pirámide, el CTA es el peldaño (o cortar el descanso);
              // terminar antes va en el paso.
              StepKind.pyramid => runner.isPyramidResting ? 'SEGUIR' : 'HECHO',
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
