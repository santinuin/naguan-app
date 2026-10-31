import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/training/training_models.dart';

import 'workout_runner_test.dart' show FakeClock;

Map<String, Object> _item(int id, String slug, Map<String, Object> extra) => {
  'id': id,
  'round': 1,
  'position': 1,
  'kind': 'exercise',
  'exercise': {'slug': slug, 'name': slug},
  ...extra,
};

Map<String, Object> _block(
  int position,
  String phase,
  List<Map<String, Object>> items, {
  bool optional = false,
}) => {
  'position': position,
  'type': 'rounds',
  'phase': phase,
  'optional': optional,
  'items': items,
};

/// Calentamiento (10 sentadillas); entrenamiento: plancha al máximo tiempo,
/// swings de 60 s contados y un extra opcional (flexiones); movilidad.
Session detailSession() => Session.fromJson({
  'id': 9,
  'kind': 'workout',
  'title': 'Detalles',
  'description': null,
  'time_record': true,
  'blocks': [
    _block(1, 'warmup', [
      _item(1, 'sentadilla', {'reps': 10}),
    ]),
    _block(2, 'main', [
      _item(2, 'plancha', {'duration_s': 60, 'open': true}),
    ]),
    _block(3, 'main', [
      _item(3, 'swing', {'duration_s': 60, 'count_reps': true}),
    ]),
    _block(4, 'main', [
      _item(4, 'flexion', {'reps': 10}),
    ], optional: true),
    _block(5, 'mobility', [
      _item(5, 'estiramiento', {'reps': 1}),
    ]),
  ],
});

void main() {
  late FakeClock clock;
  late WorkoutRunner runner;

  setUp(() {
    clock = FakeClock();
    runner = WorkoutRunner(detailSession(), clock: clock.now)..start();
    clock.advance(const Duration(seconds: 30));
    runner.complete(); // el calentamiento
    clock.advance(WorkoutRunner.leadIn); // la preparación de la plancha
    runner.tick();
  });

  test('el máximo tiempo posible cuenta hacia arriba y registra lo hecho', () {
    expect(runner.remaining, isNull, reason: 'no tiene fin');
    clock.advance(const Duration(seconds: 95));
    expect(runner.tick(), isNull, reason: 'no avanza solo');
    expect(runner.elapsedInStep, const Duration(seconds: 95));
    runner.complete(); // TERMINÉ
    expect(runner.current.block.position, 3);
  });

  test('un ítem que cuenta reps las pide al terminar el tiempo', () {
    runner.complete(); // la plancha
    clock.advance(WorkoutRunner.leadIn);
    runner.tick();
    clock.advance(const Duration(seconds: 60));
    expect(runner.tick(), Cue.go);
    expect(runner.isAskingReps, isTrue);
    expect(runner.current.block.position, 3, reason: 'espera las reps');

    runner.adjustReps(42);
    runner.complete(); // LISTO
    expect(runner.isAskingReps, isFalse);
    // Llega al opcional: se ofrece, en pausa.
    expect(runner.isOfferingOptional, isTrue);
    expect(runner.isPaused, isTrue);
  });

  test('TERMINAR ACÁ saltea el opcional; HACERLO lo hace', () {
    runner.complete(); // plancha
    clock.advance(WorkoutRunner.leadIn + const Duration(seconds: 60));
    runner.tick(); // los swings terminan solos
    runner.complete(); // LISTO (0 reps)
    expect(runner.isOfferingOptional, isTrue);

    runner.skipOptional();
    expect(runner.isOfferingOptional, isFalse);
    expect(runner.current.block.phase, BlockPhase.mobility);
    expect(runner.isPaused, isFalse);

    // ATRÁS desde la movilidad vuelve al extra (arrepentirse de haberlo
    // salteado): se ofrece de nuevo.
    runner.back();
    expect(runner.isOfferingOptional, isTrue);
    expect(runner.current.block.position, 4);
    runner.acceptOptional();
    expect(runner.isOfferingOptional, isFalse);
    expect(runner.isPaused, isFalse);
    expect(runner.current.block.position, 4);
  });

  test(
    'registra las reps contadas, el tiempo y la duración del entrenamiento',
    () {
      clock.advance(const Duration(seconds: 80));
      runner.complete(); // plancha: 80 s
      clock.advance(WorkoutRunner.leadIn + const Duration(seconds: 60));
      runner.tick();
      runner.adjustReps(40);
      runner.complete(); // 40 swings en 60 s
      runner.skipOptional(); // sin extra
      clock.advance(const Duration(minutes: 5));
      runner.complete(); // la movilidad

      final workout = runner.toNewWorkout();
      final byId = {for (final it in workout.items) it.blockItemId: it};
      expect(byId[2]!.durationS, 80);
      expect((byId[3]!.durationS, byId[3]!.reps), (60, 40));
      expect(byId.containsKey(4), isFalse, reason: 'el extra no se hizo');
      // Del primer paso del entrenamiento (antes de su preparación) hasta
      // salir del último: 3 + 80 + 3 + 60 s. Ni el calentamiento ni la
      // movilidad.
      expect(workout.mainDurationS, 146);

      // Ida y vuelta por JSON, como en la cola offline.
      final queued = NewWorkout.fromJson(
        jsonDecode(jsonEncode(workout.toJson())) as Map<String, dynamic>,
      );
      expect(queued.mainDurationS, 146);
      final counted = queued.items.firstWhere((i) => i.blockItemId == 3);
      expect((counted.durationS, counted.reps), (60, 40));
    },
  );

  test('la pregunta de las reps sobrevive al snapshot', () {
    runner.complete(); // plancha
    clock.advance(WorkoutRunner.leadIn + const Duration(seconds: 60));
    runner.tick();
    final restored = WorkoutRunner.restore(
      detailSession(),
      jsonDecode(jsonEncode(runner.toSnapshot())) as Map<String, dynamic>,
      clock: clock.now,
    );
    expect(restored.isAskingReps, isTrue);
    restored.adjustReps(30);
    restored.resume();
    restored.complete();
    expect(restored.isOfferingOptional, isTrue);
  });
}
