import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/training/training_models.dart';

/// Qué tipo de paso es: cambia cómo se muestra y cómo avanza.
enum StepKind {
  /// Un ejercicio por repeticiones: avanza cuando el usuario marca LISTO.
  reps,

  /// Un ejercicio por tiempo: cuenta regresiva, avanza solo al llegar a 0.
  timed,

  /// Un descanso (Enfriá): cuenta regresiva, avanza solo.
  rest,

  /// Un bloque AMRAP entero: se repite la vuelta hasta que se acaba el tope.
  amrap,
}

/// Un paso de la ejecución. La sesión se "aplana" en una lista de pasos que
/// se recorre en orden.
///
/// Se llama WorkoutStep y no Step porque Material ya tiene un widget Step
/// (el del Stepper): con el mismo nombre habría que desambiguar los imports.
class WorkoutStep {
  const WorkoutStep({
    required this.kind,
    required this.block,
    required this.roundCount,
    this.item,
  });

  final StepKind kind;
  final Block block;

  /// El ítem del paso; null en un AMRAP (que abarca el bloque entero).
  final Item? item;

  /// Cuántas vueltas tiene el bloque (para mostrar "VUELTA 3 / 8").
  final int roundCount;

  int get round => item?.round ?? 1;

  /// La duración del paso, si tiene: el tiempo del ejercicio o del
  /// descanso, o el tope del AMRAP. Null en los pasos por reps.
  Duration? get duration => switch (kind) {
    StepKind.timed || StepKind.rest => Duration(seconds: item!.durationS!),
    StepKind.amrap => Duration(seconds: block.timeCapS!),
    StepKind.reps => null,
  };
}

/// Convierte una sesión en la lista de pasos a recorrer.
List<WorkoutStep> buildSteps(Session session) {
  return [
    for (final block in session.blocks)
      if (block.type == BlockType.amrap)
        WorkoutStep(kind: StepKind.amrap, block: block, roundCount: 1)
      else
        for (final item in block.items)
          WorkoutStep(
            kind: switch (item) {
              Item(isRest: true) => StepKind.rest,
              Item(reps: _?) => StepKind.reps,
              _ => StepKind.timed,
            },
            block: block,
            item: item,
            roundCount: block.rounds.length,
          ),
  ];
}

/// El motor de una Fragua: el paso actual, el tiempo, lo que se hizo.
///
/// Es un ChangeNotifier: avisa a sus oyentes (la pantalla, con un
/// ListenableBuilder) cada vez que cambia algo. La lógica vive acá, sin
/// widgets, así se testea sola; la pantalla solo la muestra y le pasa los
/// toques del usuario.
///
/// El tiempo se calcula siempre desde la hora real ([_now]), no contando
/// ticks: si el Timer de la pantalla se atrasa o la app pasa a segundo plano,
/// la cuenta regresiva sigue siendo exacta.
class WorkoutRunner extends ChangeNotifier {
  /// [clock] es inyectable, como en el backend Go: los tests pasan un reloj
  /// falso que adelantan a mano.
  WorkoutRunner(this.session, {DateTime Function()? clock, String? clientId})
    : _now = clock ?? DateTime.now,
      clientId = clientId ?? newUuid(),
      steps = buildSteps(session);

  /// Reconstruye un runner a partir de un snapshot guardado (ver
  /// [toSnapshot]): para retomar una Fragua después de que el sistema cerró
  /// la app.
  ///
  /// Queda PAUSADO en el momento en que se guardó: el tiempo que la app
  /// estuvo cerrada no cuenta (un descanso no "se termina solo" mientras el
  /// teléfono estaba en el bolsillo). El usuario retoma con play.
  factory WorkoutRunner.restore(
    Session session,
    Map<String, dynamic> snapshot, {
    DateTime Function()? clock,
  }) {
    final runner = WorkoutRunner(
      session,
      clock: clock,
      clientId: snapshot['client_id'] as String,
    );
    DateTime time(String key) => DateTime.parse(snapshot[key] as String);
    runner
      .._index = snapshot['index'] as int
      .._startedAt = time('started_at')
      .._stepStartedAt = time('step_started_at')
      .._pausedInStep = Duration(
        milliseconds: snapshot['paused_in_step_ms'] as int,
      )
      // Si ya estaba pausado, sigue pausado desde entonces; si no, se pausa
      // en el momento del último guardado.
      .._pausedAt = snapshot['paused_at'] != null
          ? time('paused_at')
          : time('saved_at')
      .._repsDraft = snapshot['reps_draft'] as int
      .._amrapRounds = snapshot['amrap_rounds'] as int;
    for (final r in snapshot['results'] as List) {
      final result = ItemResult.fromJson(r as Map<String, dynamic>);
      runner._results[result.blockItemId] = result;
    }
    for (final MapEntry(:key, :value)
        in (snapshot['amraps'] as Map<String, dynamic>).entries) {
      runner._amrapsDone[int.parse(key)] = value as int;
    }
    if (runner._index >= runner.steps.length) {
      runner._finishedAt = time('saved_at');
    }
    return runner;
  }

  final Session session;
  final List<WorkoutStep> steps;
  final DateTime Function() _now;

  /// La clave de idempotencia de esta Fragua (ver NewWorkout.clientId). Se
  /// genera una vez y viaja en el snapshot: un reintento usa la misma.
  final String clientId;

  int _index = 0;
  DateTime? _startedAt;
  DateTime? _finishedAt;

  DateTime _stepStartedAt = DateTime(0);
  Duration _pausedInStep = Duration.zero;
  DateTime? _pausedAt;

  /// Las reps que se van a registrar en el paso actual: empiezan en las
  /// indicadas y el usuario las ajusta con +/−.
  int _repsDraft = 0;

  /// Vueltas completadas en el AMRAP actual.
  int _amrapRounds = 0;

  /// Vueltas de los AMRAP ya terminados, por posición del bloque.
  final Map<int, int> _amrapsDone = {};

  /// Sube con cada cambio que vale la pena guardar (no con cada tick): la
  /// pantalla lo usa para saber cuándo guardar el snapshot.
  int _revision = 0;

  /// Lo hecho en cada ejercicio, por id de ítem. Un Map y no una lista: si
  /// un ítem se registrara dos veces, queda el último.
  final Map<int, ItemResult> _results = {};

  // ── Estado de lectura ──────────────────────────────────────────────────────

  bool get isStarted => _startedAt != null;
  bool get isFinished => isStarted && _index >= steps.length;
  bool get isPaused => _pausedAt != null;

  int get index => _index;
  WorkoutStep get current => steps[_index];
  WorkoutStep? get next => _index + 1 < steps.length ? steps[_index + 1] : null;

  /// Avance de 0 a 1, para la barra de progreso.
  double get progress => steps.isEmpty ? 1 : _index / steps.length;

  int get repsDraft => _repsDraft;
  int get amrapRounds => _amrapRounds;
  int get revision => _revision;
  DateTime? get startedAt => _startedAt;

  /// Ejercicios registrados hasta ahora (los "golpes" de la Fragua).
  int get completedExercises => _results.length;

  /// Cuánto lleva el paso actual, sin contar las pausas.
  Duration get stepElapsed {
    final end = _pausedAt ?? _now();
    return end.difference(_stepStartedAt) - _pausedInStep;
  }

  /// Cuánto le queda al paso actual; null si no tiene tiempo (por reps).
  Duration? get remaining {
    final d = current.duration;
    if (d == null) return null;
    final r = d - stepElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// Cuánto lleva la Fragua entera (con pausas incluidas: es tiempo real).
  Duration get totalElapsed =>
      (_finishedAt ?? _now()).difference(_startedAt ?? _now());

  // ── Acciones ───────────────────────────────────────────────────────────────

  void start() {
    assert(!isStarted, 'la Fragua ya empezó');
    _startedAt = _now();
    _enterStep(0);
    _changed();
  }

  /// Ajusta las reps a registrar en el paso actual (+1 / −1).
  void adjustReps(int delta) {
    _repsDraft = max(0, _repsDraft + delta);
    _changed();
  }

  void addAmrapRound() {
    _amrapRounds++;
    _changed();
  }

  /// El usuario marca el paso como hecho (LISTO): se registra y se avanza.
  void complete() {
    final step = current;
    final item = step.item;
    switch (step.kind) {
      case StepKind.reps:
        _results[item!.id] = ItemResult.reps(
          item.id,
          _repsDraft,
          exerciseSlug: item.exercise!.slug,
        );
      case StepKind.timed:
        // Terminó antes de tiempo: se registra lo que hizo.
        final done = min(stepElapsed.inSeconds, step.duration!.inSeconds);
        if (done > 0) {
          _results[item!.id] = ItemResult.duration(
            item.id,
            done,
            exerciseSlug: item.exercise!.slug,
          );
        }
      case StepKind.amrap:
        _amrapsDone[step.block.position] = _amrapRounds;
      case StepKind.rest:
        break; // nada que registrar
    }
    _advance();
  }

  /// Saltea el paso sin registrar nada.
  void skip() => _advance();

  void pause() {
    if (isPaused || isFinished) return;
    _pausedAt = _now();
    _changed();
  }

  void resume() {
    final pausedAt = _pausedAt;
    if (pausedAt == null) return;
    _pausedInStep += _now().difference(pausedAt);
    _pausedAt = null;
    _changed();
  }

  /// Lo llama la pantalla periódicamente (varias veces por segundo). Si un
  /// paso con tiempo llegó a cero, avanza solo. Devuelve true si avanzó, para
  /// que la pantalla vibre.
  bool tick() {
    if (!isStarted || isFinished || isPaused) return false;
    if (remaining == Duration.zero) {
      switch (current.kind) {
        case StepKind.timed:
          final item = current.item!;
          _results[item.id] = ItemResult.duration(
            item.id,
            item.durationS!,
            exerciseSlug: item.exercise!.slug,
          );
        case StepKind.amrap:
          _amrapsDone[current.block.position] = _amrapRounds;
        case StepKind.reps || StepKind.rest:
          break;
      }
      _advance();
      return true;
    }
    // Sin cambio de paso, igual hay que redibujar la cuenta regresiva.
    notifyListeners();
    return false;
  }

  /// La Fragua terminada, lista para registrar en la API.
  NewWorkout toNewWorkout() {
    assert(isFinished, 'la Fragua todavía no terminó');
    return NewWorkout(
      clientId: clientId,
      sessionId: session.id,
      startedAt: _startedAt!,
      finishedAt: _finishedAt!,
      items: _results.values.toList(),
      amrapRounds: Map.of(_amrapsDone),
    );
  }

  /// Una "foto" del estado, serializable a JSON, para guardarla en el
  /// teléfono. [WorkoutRunner.restore] hace el camino inverso.
  Map<String, Object?> toSnapshot() => {
    'client_id': clientId,
    'index': _index,
    'started_at': _startedAt?.toIso8601String(),
    'step_started_at': _stepStartedAt.toIso8601String(),
    'paused_in_step_ms': _pausedInStep.inMilliseconds,
    'paused_at': _pausedAt?.toIso8601String(),
    'saved_at': _now().toIso8601String(),
    'reps_draft': _repsDraft,
    'amrap_rounds': _amrapRounds,
    // Las claves de un objeto JSON son siempre strings.
    'amraps': {for (final e in _amrapsDone.entries) '${e.key}': e.value},
    'results': [for (final r in _results.values) r.toJson()],
  };

  void _advance() {
    _enterStep(_index + 1);
    _changed();
  }

  void _changed() {
    _revision++;
    notifyListeners();
  }

  void _enterStep(int i) {
    _index = i;
    _stepStartedAt = _now();
    _pausedInStep = Duration.zero;
    _pausedAt = null;
    if (i >= steps.length) {
      _finishedAt = _now();
      return;
    }
    _repsDraft = steps[i].item?.reps ?? 0;
    _amrapRounds = 0;
  }
}
