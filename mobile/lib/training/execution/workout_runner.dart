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

/// Un pitido de la cuenta regresiva: "pi" en el 3, el 2 y el 1, y "piiii"
/// en el 0 (arranca el ejercicio, o termina un tiempo). Así se puede entrenar
/// sin mirar el teléfono.
enum Cue { count, go }

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
///
/// Los pasos con tiempo (por tiempo y AMRAP) empiezan con [leadIn] de
/// preparación: el inicio del paso se pone en el futuro, y mientras no
/// llega, lo transcurrido es negativo (ver [isPreparing]). No hace falta
/// otro estado: la pausa, el snapshot y el reloj falso de los tests lo
/// manejan igual que al resto del paso.
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
      // Opcional: un snapshot de una versión anterior no lo trae.
      .._loadDraft = (snapshot['load_draft'] as num?)?.toDouble()
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

  /// La preparación (3, 2, 1) antes de un paso con tiempo.
  static const leadIn = Duration(seconds: 3);

  /// De a cuánto sube y baja el peso con − y +.
  static const loadStep = 2.5;

  /// El peso más alto que acepta la API (workout_item.load_kg).
  static const maxLoadKg = 999.99;

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

  /// El peso del paso actual, en kilos; null: sin carga. Empieza en el
  /// propuesto (ver [_proposedLoad]) y el usuario lo ajusta.
  double? _loadDraft;

  /// El último peso que usaste en cada ejercicio (por slug), de la API o del
  /// teléfono: la propuesta para la primera serie de un bloque. Se puede
  /// asignar después de crear el runner (llega asincrónico), siempre antes
  /// de EMPEZAR. No va en el snapshot: al retomar se vuelve a pedir.
  Map<String, double> lastLoads = const {};

  /// Vueltas completadas en el AMRAP actual.
  int _amrapRounds = 0;

  /// Vueltas de los AMRAP ya terminados, por posición del bloque.
  final Map<int, int> _amrapsDone = {};

  /// Sube con cada cambio que vale la pena guardar (no con cada tick): la
  /// pantalla lo usa para saber cuándo guardar el snapshot.
  int _revision = 0;

  /// El último segundo de la cuenta que ya se anunció con un pitido (ver
  /// [tick]). No va en el snapshot: al retomar, a lo sumo se repite un pi.
  _CountMark? _announced;

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
  double? get loadDraft => _loadDraft;

  /// Si el paso actual muestra el peso: los ejercicios con carga siempre;
  /// los demás, solo si se les sumó lastre.
  bool get showsLoad {
    final exercise = current.item?.exercise;
    if (exercise == null) return false;
    return exercise.loaded || _loadDraft != null;
  }

  int get amrapRounds => _amrapRounds;
  int get revision => _revision;
  DateTime? get startedAt => _startedAt;

  /// Ejercicios registrados hasta ahora (los "golpes" de la Fragua).
  int get completedExercises => _results.length;

  /// Cuánto lleva el paso actual, sin contar las pausas. Negativo durante
  /// la preparación.
  Duration get stepElapsed {
    final end = _pausedAt ?? _now();
    return end.difference(_stepStartedAt) - _pausedInStep;
  }

  /// Cuánto le queda al paso actual; null si no tiene tiempo (por reps).
  Duration? get remaining {
    final d = current.duration;
    if (d == null) return null;
    // Preparándose, el ejercicio todavía no empezó: le queda todo.
    if (isPreparing) return d;
    final r = d - stepElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  /// Si el paso está en la preparación (la cuenta 3, 2, 1 antes de empezar).
  bool get isPreparing => isStarted && !isFinished && stepElapsed.isNegative;

  /// Cuánto falta para que arranque el paso; null si no se está preparando.
  Duration? get preparationLeft => isPreparing ? -stepElapsed : null;

  /// Si hay un paso al que volver con [back].
  bool get canGoBack => isStarted && !isFinished && _previousIndex != null;

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

  /// Ajusta el peso del paso actual (± [loadStep]). Por debajo de cero
  /// queda sin carga (así se saca el lastre).
  void adjustLoad(double delta) => setLoad((_loadDraft ?? 0) + delta);

  /// Fija el peso del paso actual (lo escrito a mano); null o 0: sin carga.
  void setLoad(double? kg) {
    _loadDraft = kg == null || kg <= 0
        ? null
        : (min(kg, maxLoadKg) * 100).round() / 100;
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
          loadKg: _loadDraft,
        );
      case StepKind.timed:
        // Terminó antes de tiempo: se registra lo que hizo.
        final done = min(stepElapsed.inSeconds, step.duration!.inSeconds);
        if (done > 0) {
          _results[item!.id] = ItemResult.duration(
            item.id,
            done,
            exerciseSlug: item.exercise!.slug,
            loadKg: _loadDraft,
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

  /// Vuelve al ejercicio anterior (salteando los Enfriá, que no registran
  /// nada), por si se pasó de largo sin querer. Lo registrado en ese paso se
  /// descarta y el paso empieza de nuevo: con el tiempo completo (y su
  /// preparación), o con las reps que se habían marcado, para corregirlas.
  void back() {
    final i = _previousIndex;
    if (i == null) return;
    final step = steps[i];
    // Map.remove devuelve lo que sacó (o null): el resultado deshecho.
    final undone = switch (step.item) {
      final item? => _results.remove(item.id),
      null => null,
    };
    if (step.kind == StepKind.amrap) _amrapsDone.remove(step.block.position);
    _enterStep(i);
    if (undone?.reps case final reps?) _repsDraft = reps;
    // El peso que se había marcado (también si era sin carga).
    if (undone != null) _loadDraft = undone.loadKg;
    _changed();
  }

  void pause() {
    if (!isStarted || isPaused || isFinished) return;
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
  /// paso con tiempo llegó a cero, avanza solo.
  ///
  /// Devuelve el pitido que toca en este momento, si alguno: [Cue.count] al
  /// entrar en el 3, el 2 y el 1 de una cuenta (la preparación o el final de
  /// un tiempo), y [Cue.go] al llegar a 0 (arranca el ejercicio, o terminó un
  /// tiempo y se avanzó).
  Cue? tick() {
    if (!isStarted || isFinished || isPaused) return null;
    if (remaining == Duration.zero) {
      switch (current.kind) {
        case StepKind.timed:
          final item = current.item!;
          _results[item.id] = ItemResult.duration(
            item.id,
            item.durationS!,
            exerciseSlug: item.exercise!.slug,
            loadKg: _loadDraft,
          );
        case StepKind.amrap:
          _amrapsDone[current.block.position] = _amrapRounds;
        case StepKind.reps || StepKind.rest:
          break;
      }
      // Al terminar solo un Enfriá, el ejercicio que sigue arranca sin
      // preparación: el Enfriá ya hizo su cuenta (3, 2, 1 y piiii).
      final fromRest = current.kind == StepKind.rest;
      _enterStep(_index + 1, withLeadIn: !fromRest);
      _changed();
      // El segundo en que entra el paso nuevo se da por anunciado: si
      // empieza con su preparación, el "pi" del 3 se pisaría con este piiii.
      _announced = _countMark;
      return Cue.go;
    }

    // ¿Se entró en un segundo nuevo de la cuenta? Comparar con el último
    // anunciado (y no "¿pasó un segundo desde el tick anterior?") hace que
    // cada segundo pite una sola vez, aunque haya 4 ticks por segundo.
    final mark = _countMark;
    Cue? cue;
    if (mark != _announced) {
      if (_announced?.preparing == true && mark?.preparing != true) {
        cue = Cue.go; // terminó la preparación: ¡ya!
      } else if (mark != null && mark.seconds <= 3) {
        cue = Cue.count;
      }
      _announced = mark;
    }
    // Sin cambio de paso, igual hay que redibujar la cuenta regresiva.
    notifyListeners();
    return cue;
  }

  /// El segundo que muestra la cuenta ahora (redondeado hacia arriba, como
  /// en la pantalla), y si es de la preparación o del paso. Null en un paso
  /// por reps.
  ///
  /// Es un record: un valor con campos con nombre, sin declarar una clase.
  /// Los records se comparan por valor, así que `!=` en [tick] compara los
  /// dos campos.
  _CountMark? get _countMark {
    if (isFinished) return null; // no hay paso actual
    final left = preparationLeft ?? remaining;
    if (left == null) return null;
    return (
      preparing: isPreparing,
      seconds: (left.inMilliseconds / 1000).ceil(),
    );
  }

  /// El ejercicio anterior al actual (sin contar los Enfriá), o null.
  int? get _previousIndex {
    for (var i = _index - 1; i >= 0; i--) {
      if (steps[i].kind != StepKind.rest) return i;
    }
    return null;
  }

  /// El peso que se propone para el paso [i]: el de la serie anterior del
  /// mismo ejercicio en el mismo bloque (las series de aproximación suben
  /// de a una; las de trabajo repiten); si es la primera del bloque, el
  /// último que usaste ese ejercicio, solo si es un ejercicio con carga (el
  /// lastre no se propone solo: se suma a mano).
  double? _proposedLoad(int i) {
    final step = steps[i];
    final exercise = step.item?.exercise;
    if (exercise == null) return null;
    for (var j = i - 1; j >= 0 && identical(steps[j].block, step.block); j--) {
      final item = steps[j].item;
      if (item?.exercise?.slug != exercise.slug) continue;
      // Una serie anterior que no se registró (se salteó) no dice nada:
      // se sigue buscando.
      if (_results[item!.id] case final done?) return done.loadKg;
    }
    return exercise.loaded ? lastLoads[exercise.slug] : null;
  }

  /// Los pesos de esta Fragua por ejercicio: el más alto de cada uno, para
  /// proponerlo la próxima vez (como hace la API con los registrados).
  Map<String, double> get usedLoads {
    final out = <String, double>{};
    for (final r in _results.values) {
      final (slug, kg) = (r.exerciseSlug, r.loadKg);
      if (slug == null || kg == null) continue;
      out[slug] = max(out[slug] ?? 0, kg);
    }
    return out;
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
    'load_draft': _loadDraft,
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

  /// Entra al paso [i]. Si tiene tiempo y [withLeadIn], con preparación: el
  /// paso "empieza" [leadIn] más tarde.
  void _enterStep(int i, {bool withLeadIn = true}) {
    _index = i;
    _stepStartedAt = _now();
    _pausedInStep = Duration.zero;
    _pausedAt = null;
    _announced = null;
    if (i >= steps.length) {
      _finishedAt = _now();
      return;
    }
    final step = steps[i];
    if (withLeadIn &&
        (step.kind == StepKind.timed || step.kind == StepKind.amrap)) {
      _stepStartedAt = _stepStartedAt.add(leadIn);
    }
    _repsDraft = step.item?.reps ?? 0;
    _loadDraft = _proposedLoad(i);
    _amrapRounds = 0;
  }
}

/// Un segundo de la cuenta regresiva (ver WorkoutRunner._countMark). Un
/// typedef le pone nombre al tipo del record, para no repetirlo.
typedef _CountMark = ({bool preparing, int seconds});
