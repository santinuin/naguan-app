import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/catalog/session_edits.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/training/training_models.dart';

/// Un reloj falso: el test decide qué hora es y la adelanta a mano. Se le
/// pasa al runner su método `now` (un tear-off) como función reloj.
class FakeClock {
  DateTime _t = DateTime.utc(2026, 10, 1, 18);

  DateTime now() => _t;

  void advance(Duration d) => _t = _t.add(d);
}

Map<String, Object> _exercise(
  int id,
  int round,
  int pos, {
  int? reps,
  int? seconds,
}) => {
  'id': id,
  'round': round,
  'position': pos,
  'kind': 'exercise',
  'exercise': {'slug': 'x$id', 'name': 'Ejercicio $id'},
  'reps': ?reps,
  'duration_s': ?seconds,
};

Map<String, Object> _rest(int id, int round, int pos, int seconds) => {
  'id': id,
  'round': round,
  'position': pos,
  'kind': 'rest',
  'duration_s': seconds,
};

/// Sesión de prueba: un bloque con 2 vueltas de (10 flexiones + 30 s de
/// plancha + 20 s de descanso), y un AMRAP de 5 minutos.
Session testSession() {
  const exercise = _exercise, rest = _rest;
  return Session.fromJson({
    'id': 99,
    'kind': 'workout',
    'title': 'Prueba',
    'description': null,
    'blocks': [
      {
        'position': 1,
        'type': 'rounds_with_rest',
        'items': [
          exercise(1, 1, 1, reps: 10),
          exercise(2, 1, 2, seconds: 30),
          rest(3, 1, 3, 20),
          exercise(4, 2, 1, reps: 10),
          exercise(5, 2, 2, seconds: 30),
          rest(6, 2, 3, 20),
        ],
      },
      {
        'position': 2,
        'type': 'amrap',
        'time_cap_s': 300,
        'items': [exercise(7, 1, 1, reps: 5)],
      },
    ],
  });
}

void main() {
  late FakeClock clock;
  late WorkoutRunner runner;

  setUp(() {
    clock = FakeClock();
    runner = WorkoutRunner(testSession(), clock: clock.now)..start();
  });

  test('aplana la sesión en pasos, con el AMRAP como un solo paso', () {
    expect(runner.steps.map((s) => s.kind), [
      StepKind.reps,
      StepKind.timed,
      StepKind.rest,
      StepKind.reps,
      StepKind.timed,
      StepKind.rest,
      StepKind.amrap,
    ]);
    expect(runner.steps.first.roundCount, 2);
  });

  test('un paso por reps espera al usuario y registra las reps ajustadas', () {
    expect(runner.remaining, isNull);
    clock.advance(const Duration(minutes: 3));
    expect(runner.tick(), isNull, reason: 'sin tiempo, no avanza solo');

    runner.adjustReps(2); // hizo 12 en vez de 10
    runner.complete();

    expect(runner.index, 1);
    expect(runner.completedExercises, 1);
  });

  test('un paso por tiempo avanza solo al llegar a cero', () {
    runner.complete(); // pasa las flexiones
    expect(runner.current.kind, StepKind.timed);
    clock.advance(WorkoutRunner.leadIn);

    clock.advance(const Duration(seconds: 29));
    runner.tick();
    expect(runner.remaining, const Duration(seconds: 1));

    clock.advance(const Duration(seconds: 1));
    expect(runner.tick(), Cue.go, reason: 'llegó a cero: avanza');
    expect(runner.current.kind, StepKind.rest);
  });

  test('un paso por tiempo empieza con 3 s de preparación', () {
    runner.complete();

    expect(runner.isPreparing, isTrue);
    expect(runner.preparationLeft, WorkoutRunner.leadIn);
    // El ejercicio todavía no empezó: le queda todo.
    expect(runner.remaining, const Duration(seconds: 30));

    clock.advance(WorkoutRunner.leadIn);
    expect(runner.isPreparing, isFalse);
    expect(runner.preparationLeft, isNull);
    expect(runner.remaining, const Duration(seconds: 30));
  });

  test('pita 3, 2, 1 en la preparación y piiii al arrancar', () {
    runner.complete();

    expect(runner.tick(), Cue.count); // 3
    expect(runner.tick(), isNull, reason: 'el mismo segundo pita una vez');
    clock.advance(const Duration(milliseconds: 1000));
    expect(runner.tick(), Cue.count); // 2
    clock.advance(const Duration(milliseconds: 1000));
    expect(runner.tick(), Cue.count); // 1
    clock.advance(const Duration(milliseconds: 1000));
    expect(runner.tick(), Cue.go); // ¡ya!
    clock.advance(const Duration(milliseconds: 1000));
    expect(runner.tick(), isNull, reason: 'a mitad del ejercicio, silencio');
  });

  test('pita los últimos 3 s de un tiempo y piiii al terminar', () {
    runner.complete();
    clock.advance(WorkoutRunner.leadIn + const Duration(seconds: 26));
    runner.tick(); // quedan 4 s
    final cues = <Cue?>[];
    for (var i = 0; i < 4; i++) {
      clock.advance(const Duration(seconds: 1));
      cues.add(runner.tick());
    }
    expect(cues, [Cue.count, Cue.count, Cue.count, Cue.go]);
    expect(runner.current.kind, StepKind.rest);
  });

  group('después de un Enfriá', () {
    // Enfriá de 10 s y después 20 s de plancha.
    WorkoutRunner restThenTimed() => WorkoutRunner(
      Session.fromJson({
        'id': 1,
        'kind': 'workout',
        'title': 'Enfriá y plancha',
        'description': null,
        'blocks': [
          {
            'position': 1,
            'type': 'rounds_with_rest',
            'items': [_rest(1, 1, 1, 10), _exercise(2, 1, 2, seconds: 20)],
          },
        ],
      }),
      clock: clock.now,
    )..start();

    test('si el Enfriá termina solo, el ejercicio arranca sin preparar', () {
      final r = restThenTimed();
      clock.advance(const Duration(seconds: 10));

      expect(r.tick(), Cue.go);
      expect(r.current.kind, StepKind.timed);
      expect(r.isPreparing, isFalse);
    });

    test('si se corta el Enfriá con SEGUIR, hay preparación', () {
      final r = restThenTimed();
      clock.advance(const Duration(seconds: 4));
      r.complete();

      expect(r.isPreparing, isTrue);
    });
  });

  test('atrás deshace el ejercicio anterior, salteando el Enfriá', () {
    expect(runner.canGoBack, isFalse, reason: 'en el primero no hay atrás');
    runner.adjustReps(2);
    runner.complete(); // 12 flexiones
    clock.advance(WorkoutRunner.leadIn + const Duration(seconds: 30));
    runner.tick(); // la plancha termina sola: 30 s
    expect(runner.current.kind, StepKind.rest);
    runner.complete(); // corta el Enfriá
    expect(runner.completedExercises, 2);

    // En las flexiones de la vuelta 2: vuelve a la plancha, no al Enfriá.
    runner.back();
    expect(runner.index, 1);
    expect(runner.completedExercises, 1, reason: 'la plancha se deshizo');
    expect(runner.isPreparing, isTrue, reason: 'vuelve a empezar');
    expect(runner.remaining, const Duration(seconds: 30));

    // Otra vez: a las flexiones, con las 12 marcadas para corregirlas.
    runner.back();
    expect(runner.index, 0);
    expect(runner.completedExercises, 0);
    expect(runner.repsDraft, 12);
    expect(runner.canGoBack, isFalse);
  });

  test('atrás desde el AMRAP vuelve a la última plancha', () {
    while (runner.current.kind != StepKind.amrap) {
      runner.skip();
    }
    runner.back();
    expect(runner.index, 4);
  });

  test('la pausa congela la cuenta regresiva', () {
    runner.complete();
    clock.advance(WorkoutRunner.leadIn);
    clock.advance(const Duration(seconds: 10));
    runner.pause();
    clock.advance(const Duration(minutes: 5)); // pausado: no cuenta
    expect(runner.remaining, const Duration(seconds: 20));

    runner.resume();
    clock.advance(const Duration(seconds: 5));
    expect(runner.remaining, const Duration(seconds: 15));
  });

  test('terminar antes un paso por tiempo registra lo que se hizo', () {
    runner.complete();
    clock.advance(WorkoutRunner.leadIn);
    clock.advance(const Duration(seconds: 12));
    runner.complete(); // cortó la plancha a los 12 s

    final workout = _finish(runner, clock);
    final plank = workout.items.firstWhere((it) => it.blockItemId == 2);
    expect(plank.durationS, 12);
  });

  test('saltear no registra nada', () {
    runner.skip(); // saltea las flexiones de la vuelta 1

    final workout = _finish(runner, clock);
    expect(workout.items.any((it) => it.blockItemId == 1), isFalse);
  });

  test('al terminar arma el workout para la API', () {
    final workout = _finish(runner, clock);

    expect(runner.isFinished, isTrue);
    expect(workout.sessionId, 99);
    // Ejercicios 1, 2, 4 y 5 (el AMRAP no registra ítems sueltos).
    expect(workout.items.map((it) => it.blockItemId).toSet(), {1, 2, 4, 5});
    expect(workout.duration, greaterThan(Duration.zero));
  });

  test('cada resultado lleva el ejercicio que se hizo', () {
    // Una sesión ajustada antes de empezar: el ítem 1 cambió de ejercicio.
    final session = testSession().swapExercise(
      blockPosition: 1,
      from: 'x1',
      to: const ExerciseRef(slug: 'otro', name: 'Otro'),
    );
    final adjusted = WorkoutRunner(session, clock: clock.now)..start();

    final workout = _finish(adjusted, clock);
    final bySlug = {
      for (final it in workout.items) it.blockItemId: it.exerciseSlug,
    };
    expect(bySlug[1], 'otro');
    expect(bySlug[2], 'x2');
    // Y viaja en el JSON (para la API y para la cola offline).
    final first = workout.items.firstWhere((it) => it.blockItemId == 1);
    expect(first.toJson()['exercise_slug'], 'otro');
    expect(ItemResult.fromJson(first.toJson()).exerciseSlug, 'otro');
  });

  test('registra las vueltas del AMRAP y el client_id', () {
    final workout = _finish(runner, clock, amrapRounds: 6);

    expect(workout.amrapRounds, {2: 6});
    expect(workout.clientId, runner.clientId);
    expect(workout.clientId, hasLength(36));
  });

  test('retomar desde un snapshot sigue donde estaba, en pausa', () {
    runner.complete(); // paso 1 hecho (10 reps)
    clock.advance(WorkoutRunner.leadIn);
    clock.advance(const Duration(seconds: 10)); // 10 s de plancha
    final snapshot = runner.toSnapshot();

    // La app estuvo cerrada una hora.
    clock.advance(const Duration(hours: 1));
    final restored = WorkoutRunner.restore(
      testSession(),
      // Ida y vuelta por JSON, como en el disco.
      jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>,
      clock: clock.now,
    );

    expect(restored.index, 1);
    expect(restored.isPaused, isTrue);
    expect(restored.clientId, runner.clientId);
    // La hora cerrada no cuenta: a la plancha le quedan 20 s.
    expect(restored.remaining, const Duration(seconds: 20));

    restored.resume();
    clock.advance(const Duration(seconds: 5));
    expect(restored.remaining, const Duration(seconds: 15));
    expect(restored.completedExercises, 1);
  });
}

/// Recorre lo que falta de la Fragua: completa los pasos por reps y deja
/// correr el tiempo de los demás.
NewWorkout _finish(
  WorkoutRunner runner,
  FakeClock clock, {
  int amrapRounds = 0,
}) {
  while (!runner.isFinished) {
    if (runner.current.kind == StepKind.amrap) {
      for (var i = 0; i < amrapRounds; i++) {
        runner.addAmrapRound();
      }
    }
    if (runner.remaining case final r?) {
      clock.advance(r);
      runner.tick();
    } else {
      runner.complete();
    }
  }
  return runner.toNewWorkout();
}
