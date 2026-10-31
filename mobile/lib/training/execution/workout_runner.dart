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

  /// Una pirámide con tope: peldaños de 1, 2, 3... × el incremento de cada
  /// ejercicio, hasta el máximo, de vuelta a 1 y otra vez, hasta el tope.
  pyramid,
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

  /// El ítem del paso; null en un AMRAP o una pirámide (que abarcan el
  /// bloque entero).
  final Item? item;

  /// Cuántas vueltas tiene el bloque (para mostrar "VUELTA 3 / 8").
  final int roundCount;

  int get round => item?.round ?? 1;

  /// La duración del paso, si tiene: el tiempo del ejercicio o del
  /// descanso, o el tope del AMRAP. Null en los pasos por reps.
  Duration? get duration => switch (kind) {
    // El máximo tiempo posible no tiene fin: se cuenta hacia arriba.
    StepKind.timed when item!.open => null,
    StepKind.timed || StepKind.rest => Duration(seconds: item!.durationS!),
    StepKind.amrap || StepKind.pyramid => Duration(seconds: block.timeCapS!),
    StepKind.reps => null,
  };
}

/// Convierte una sesión en la lista de pasos a recorrer.
List<WorkoutStep> buildSteps(Session session) {
  return [
    for (final block in session.blocks)
      if (block.type == BlockType.amrap)
        WorkoutStep(kind: StepKind.amrap, block: block, roundCount: 1)
      else if (block.type == BlockType.pyramid)
        WorkoutStep(kind: StepKind.pyramid, block: block, roundCount: 1)
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
      .._amrapRounds = snapshot['amrap_rounds'] as int
      // Opcionales: un snapshot de una versión anterior no los trae.
      .._askingReps = snapshot['asking_reps'] == true
      .._countedS = (snapshot['counted_s'] as int?) ?? 0
      .._offeringOptional = snapshot['offering_optional'] == true
      .._mainStartedAt = switch (snapshot['main_started_at']) {
        final String t => DateTime.parse(t),
        _ => null,
      }
      .._mainEndedAt = switch (snapshot['main_ended_at']) {
        final String t => DateTime.parse(t),
        _ => null,
      };
    for (final r in snapshot['results'] as List) {
      final result = ItemResult.fromJson(r as Map<String, dynamic>);
      runner._results[result.blockItemId] = result;
    }
    for (final MapEntry(:key, :value)
        in (snapshot['amraps'] as Map<String, dynamic>).entries) {
      runner._amrapsDone[int.parse(key)] = value as int;
    }
    // La pirámide: opcional, un snapshot de una versión anterior no la trae.
    if (snapshot['pyramid'] case final Map<String, dynamic> p) {
      runner
        .._rung = p['rung'] as int
        .._descending = p['descending'] as bool
        .._peak = p['peak'] as int
        .._rungSum = p['rung_sum'] as int
        .._lastRung = p['last_rung'] as int
        .._rungStart = Duration(milliseconds: p['rung_start_ms'] as int)
        .._restEnd = switch (p['rest_end_ms']) {
          final int ms => Duration(milliseconds: ms),
          _ => null,
        };
    }
    for (final MapEntry(:key, :value)
        in ((snapshot['pyramids'] as Map<String, dynamic>?) ?? const {})
            .entries) {
      final v = value as Map<String, dynamic>;
      runner._pyramidsDone[int.parse(key)] = (
        peak: v['peak'] as int,
        rungSum: v['rung_sum'] as int,
      );
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

  /// Un ítem por tiempo que cuenta reps terminó su tiempo y espera que el
  /// usuario diga cuántas hizo ([_countedS] es el tiempo hecho).
  bool _askingReps = false;
  int _countedS = 0;

  /// Se llegó a un bloque opcional y se ofrece hacerlo o terminar ahí. La
  /// Fragua queda en pausa mientras tanto.
  bool _offeringOptional = false;

  /// Cuándo empezó y terminó el entrenamiento (la fase main): su duración
  /// es la marca de una sesión a tiempo.
  DateTime? _mainStartedAt;
  DateTime? _mainEndedAt;

  /// Vueltas de los AMRAP ya terminados, por posición del bloque.
  final Map<int, int> _amrapsDone = {};

  // ── La pirámide en curso ──
  // Los tiempos son de [stepElapsed] (el reloj del paso, sin pausas): así la
  // pausa y el snapshot los cubren sin código aparte.

  /// El peldaño que se está haciendo (o el que sigue, si se descansa).
  int _rung = 1;

  /// Si ya se pasó el máximo y se está bajando.
  bool _descending = false;

  /// El peldaño más alto completado, y la suma de los completados.
  int _peak = 0;
  int _rungSum = 0;

  /// El último peldaño completado (0: ninguno): BAJAR baja desde ahí.
  int _lastRung = 0;

  /// Cuándo empezó el peldaño actual, para saber cuánto se tardó.
  Duration _rungStart = Duration.zero;

  /// Cuándo termina el descanso entre peldaños; null si no se descansa.
  Duration? _restEnd;

  /// Lo hecho en las pirámides ya terminadas, por posición del bloque.
  final Map<int, PyramidResult> _pyramidsDone = {};

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

  /// Si el paso actual espera las reps de un ítem por tiempo.
  bool get isAskingReps => _askingReps;

  /// Si se está ofreciendo hacer un bloque opcional o terminar ahí.
  bool get isOfferingOptional => _offeringOptional;

  /// Cuánto lleva el paso actual, sin la preparación (para el máximo tiempo
  /// posible, que se cuenta hacia arriba).
  Duration get elapsedInStep =>
      stepElapsed.isNegative ? Duration.zero : stepElapsed;

  int get rung => _rung;
  bool get isDescending => _descending;
  int get pyramidPeak => _peak;

  /// Las reps totales de la pirámide hasta ahora, en peldaños (× el
  /// incremento de cada ejercicio).
  int get rungSum => _rungSum;

  /// Si se está descansando entre peldaños.
  bool get isPyramidResting => _restEnd != null;

  /// Cuánto falta del descanso entre peldaños; null si no se descansa.
  Duration? get pyramidRestLeft {
    final end = _restEnd;
    if (end == null) return null;
    final left = end - stepElapsed;
    return left.isNegative ? Duration.zero : left;
  }

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

  /// BAJAR: llegaste a tu máximo. El próximo peldaño es uno menos que el
  /// último completado (y desde ahí se baja).
  void pyramidDown() {
    if (current.kind != StepKind.pyramid || _descending) return;
    _descending = true;
    _rung = max(1, _lastRung - 1);
    _changed();
  }

  /// Termina la pirámide antes del tope: registra lo hecho y sigue.
  void finishPyramid() {
    if (current.kind != StepKind.pyramid) return;
    _recordPyramid();
    _advance();
  }

  /// HACERLO: se hace el bloque opcional; la Fragua sigue.
  void acceptOptional() {
    if (!_offeringOptional) return;
    _offeringOptional = false;
    resume();
  }

  /// TERMINAR ACÁ: se saltea el bloque opcional entero (y los opcionales
  /// que le sigan) sin registrar nada.
  void skipOptional() {
    if (!_offeringOptional) return;
    var j = _index;
    while (j < steps.length && steps[j].block.optional) {
      j++;
    }
    _offeringOptional = false;
    _enterStep(j);
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
      case StepKind.timed when _askingReps:
        // Las reps de un ítem por tiempo que las cuenta.
        _results[item!.id] = ItemResult.counted(
          item.id,
          _countedS,
          _repsDraft,
          exerciseSlug: item.exercise!.slug,
          loadKg: _loadDraft,
        );
      case StepKind.timed:
        // Terminó antes de tiempo (o es el máximo tiempo posible, sin
        // fin): se registra lo que hizo.
        final total = step.duration;
        final done = total == null
            ? elapsedInStep.inSeconds
            : min(stepElapsed.inSeconds, total.inSeconds);
        if (done > 0 && item!.countReps) {
          _askReps(done);
          return;
        }
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
      case StepKind.pyramid:
        // HECHO no termina la pirámide: completa un peldaño (o corta el
        // descanso). Termina sola con el tope, o con finishPyramid.
        _pyramidStep();
        return;
      case StepKind.rest:
        break; // nada que registrar
    }
    _advance();
  }

  /// HECHO en una pirámide. Descansando: corta el descanso y arranca el
  /// peldaño. Si no: el peldaño está hecho, se cuenta y empieza un descanso
  /// de lo mismo que se tardó (el libro: "el descanso es igual al tiempo
  /// que te llevó hacer el ejercicio").
  void _pyramidStep() {
    if (isPreparing) return;
    final now = stepElapsed;
    if (_restEnd != null) {
      _restEnd = null;
      _rungStart = now;
      _changed();
      return;
    }
    _rungSum += _rung;
    _peak = max(_peak, _rung);
    _lastRung = _rung;
    if (!_descending) {
      _rung++;
    } else if (_rung > 1) {
      _rung--;
    } else {
      // Se llegó a 1 bajando y sobra tiempo: se vuelve a subir.
      _descending = false;
      _rung = 1;
    }
    _restEnd = now + (now - _rungStart);
    _changed();
  }

  /// Registra lo hecho en la pirámide actual: el pico y la suma, y para cada
  /// ejercicio sus reps totales (así la API sabe cuál se hizo, si se cambió
  /// por una progresión). Sin peldaños completos, nada.
  void _recordPyramid() {
    final block = current.block;
    if (_rungSum == 0) return;
    _pyramidsDone[block.position] = (peak: _peak, rungSum: _rungSum);
    for (final item in block.items) {
      final exercise = item.exercise;
      if (exercise == null) continue;
      _results[item.id] = ItemResult.reps(
        item.id,
        _rungSum * (item.reps ?? 1),
        exerciseSlug: exercise.slug,
      );
    }
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
    if (step.kind == StepKind.pyramid) {
      _pyramidsDone.remove(step.block.position);
      for (final item in step.block.items) {
        _results.remove(item.id);
      }
    }
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
    if (!isStarted || isFinished || isPaused || _askingReps) return null;
    if (remaining == Duration.zero) {
      switch (current.kind) {
        case StepKind.timed when current.item!.countReps:
          // Terminó el tiempo: antes de seguir, cuántas reps hizo.
          _askReps(current.item!.durationS!);
          return Cue.go;
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
        case StepKind.pyramid:
          _recordPyramid();
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

    // Terminó el descanso entre peldaños: arranca el siguiente.
    if (_restEnd case final end? when stepElapsed >= end) {
      _restEnd = null;
      _rungStart = end;
      _changed();
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
  ///
  /// El descanso entre peldaños de una pirámide cuenta como preparación: pita
  /// 3, 2, 1 y "piiii" al arrancar el peldaño siguiente.
  _CountMark? get _countMark {
    if (isFinished) return null; // no hay paso actual
    final rest = pyramidRestLeft;
    final left = preparationLeft ?? rest ?? remaining;
    if (left == null) return null;
    return (
      preparing: isPreparing || rest != null,
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

  /// Deja el paso esperando las reps de un ítem por tiempo que las cuenta.
  void _askReps(int doneS) {
    _askingReps = true;
    _countedS = doneS;
    _repsDraft = 0;
    _changed();
  }

  /// Cuánto duró el entrenamiento (la fase main), en segundos; null si no
  /// se llegó a hacer.
  int? get mainDurationS {
    final (start, end) = (_mainStartedAt, _mainEndedAt);
    if (start == null || end == null) return null;
    final s = end.difference(start).inSeconds;
    return s > 0 ? s : null;
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
      pyramids: Map.of(_pyramidsDone),
      mainDurationS: mainDurationS,
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
    'asking_reps': _askingReps,
    'counted_s': _countedS,
    'offering_optional': _offeringOptional,
    'main_started_at': _mainStartedAt?.toIso8601String(),
    'main_ended_at': _mainEndedAt?.toIso8601String(),
    'load_draft': _loadDraft,
    'amrap_rounds': _amrapRounds,
    // Las claves de un objeto JSON son siempre strings.
    'amraps': {for (final e in _amrapsDone.entries) '${e.key}': e.value},
    'pyramids': {
      for (final MapEntry(:key, :value) in _pyramidsDone.entries)
        '$key': {'peak': value.peak, 'rung_sum': value.rungSum},
    },
    'pyramid': {
      'rung': _rung,
      'descending': _descending,
      'peak': _peak,
      'rung_sum': _rungSum,
      'last_rung': _lastRung,
      'rung_start_ms': _rungStart.inMilliseconds,
      'rest_end_ms': _restEnd?.inMilliseconds,
    },
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
    // Al salir de un paso del entrenamiento se anota la hora: la última vez
    // que se sale de uno es el final del entrenamiento.
    if (isStarted &&
        _index < steps.length &&
        steps[_index].block.phase == BlockPhase.main) {
      _mainEndedAt = _now();
    }
    _askingReps = false;
    _offeringOptional = false;
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
        (step.kind == StepKind.timed ||
            step.kind == StepKind.amrap ||
            step.kind == StepKind.pyramid)) {
      _stepStartedAt = _stepStartedAt.add(leadIn);
    }
    _rung = 1;
    _descending = false;
    _peak = 0;
    _rungSum = 0;
    _lastRung = 0;
    _rungStart = Duration.zero;
    _restEnd = null;
    if (step.block.phase == BlockPhase.main) _mainStartedAt ??= _now();
    // El primer paso de un bloque opcional: se ofrece hacerlo o terminar
    // ahí, con la Fragua en pausa.
    if (step.block.optional &&
        (i == 0 || !identical(steps[i - 1].block, step.block))) {
      _offeringOptional = true;
      _pausedAt = _now();
    }
    _repsDraft = step.item?.reps ?? 0;
    _loadDraft = _proposedLoad(i);
    _amrapRounds = 0;
  }
}

/// Un segundo de la cuenta regresiva (ver WorkoutRunner._countMark). Un
/// typedef le pone nombre al tipo del record, para no repetirlo.
typedef _CountMark = ({bool preparing, int seconds});
