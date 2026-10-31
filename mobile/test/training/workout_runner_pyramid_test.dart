import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/training/training_models.dart';

import 'workout_runner_test.dart' show FakeClock;

Map<String, Object> _item(int id, int pos, String slug, int reps) => {
  'id': id,
  'round': 1,
  'position': pos,
  'kind': 'exercise',
  'exercise': {'slug': slug, 'name': slug},
  'reps': reps,
};

/// Una pirámide de 60 s con swing y thruster de a 2, y después 10 flexiones.
Session pyramidSession() => Session.fromJson({
  'id': 8,
  'kind': 'workout',
  'title': 'Pirámide',
  'description': null,
  'blocks': [
    {
      'position': 1,
      'type': 'pyramid',
      'time_cap_s': 60,
      'items': [_item(1, 1, 'swing', 2), _item(2, 2, 'thruster', 2)],
    },
    {
      'position': 2,
      'type': 'rounds',
      'items': [_item(3, 1, 'flexion', 10)],
    },
  ],
});

void main() {
  late FakeClock clock;
  late WorkoutRunner runner;

  /// Hace el peldaño actual en [took] y deja correr el descanso entero.
  void doRung(Duration took) {
    clock.advance(took);
    runner.complete(); // HECHO
    clock.advance(took); // el descanso dura lo mismo
    runner.tick();
  }

  setUp(() {
    clock = FakeClock();
    runner = WorkoutRunner(pyramidSession(), clock: clock.now)..start();
    clock.advance(WorkoutRunner.leadIn); // la preparación
    runner.tick();
  });

  test('la pirámide es un solo paso con tope', () {
    expect(runner.steps.first.kind, StepKind.pyramid);
    expect(runner.remaining, const Duration(seconds: 60));
    expect(runner.rung, 1);
  });

  test('HECHO cuenta el peldaño y descansa lo que se tardó', () {
    clock.advance(const Duration(seconds: 4));
    runner.complete();

    expect(runner.pyramidPeak, 1);
    expect(runner.rungSum, 1);
    expect(runner.rung, 2, reason: 'sigue subiendo');
    expect(runner.isPyramidResting, isTrue);
    expect(runner.pyramidRestLeft, const Duration(seconds: 4));

    // El descanso cuenta 3, 2, 1 y piiii, y arranca el peldaño 2 solo.
    clock.advance(const Duration(seconds: 1));
    expect(runner.tick(), Cue.count);
    clock.advance(const Duration(seconds: 3));
    expect(runner.tick(), Cue.go);
    expect(runner.isPyramidResting, isFalse);
  });

  test('HECHO en el descanso lo corta', () {
    clock.advance(const Duration(seconds: 5));
    runner.complete();
    runner.complete(); // SEGUIR
    expect(runner.isPyramidResting, isFalse);
    expect(runner.rung, 2);
  });

  test('BAJAR baja desde el último peldaño y, en 1, vuelve a subir', () {
    doRung(const Duration(seconds: 1)); // 1
    doRung(const Duration(seconds: 1)); // 2
    doRung(const Duration(seconds: 1)); // 3
    runner.pyramidDown(); // el 3 fue el máximo
    expect(runner.isDescending, isTrue);
    expect(runner.rung, 2);
    doRung(const Duration(seconds: 1)); // 2
    doRung(const Duration(seconds: 1)); // 1
    expect(runner.isDescending, isFalse, reason: 'sobra tiempo: otra vez');
    expect(runner.rung, 1);
    expect(runner.pyramidPeak, 3);
    expect(runner.rungSum, 1 + 2 + 3 + 2 + 1);
  });

  test('al llegar al tope registra el pico, la suma y las reps', () {
    doRung(const Duration(seconds: 2)); // 1
    doRung(const Duration(seconds: 2)); // 2
    clock.advance(const Duration(seconds: 60)); // se acaba el tiempo
    runner.tick();

    expect(runner.current.block.position, 2, reason: 'siguió al bloque 2');
    runner.complete(); // las flexiones
    final workout = runner.toNewWorkout();
    expect(workout.pyramids, {1: (peak: 2, rungSum: 3)});
    // Las reps de cada ejercicio: la suma de peldaños × su incremento.
    final reps = {for (final it in workout.items) it.blockItemId: it.reps};
    expect(reps, {1: 6, 2: 6, 3: 10});
    expect(workout.toJson()['pyramids'], [
      {'block_position': 1, 'peak': 2, 'rung_sum': 3},
    ]);
    // Ida y vuelta por JSON, como en la cola offline.
    final queued = NewWorkout.fromJson(
      jsonDecode(jsonEncode(workout.toJson())) as Map<String, dynamic>,
    );
    expect(queued.pyramids, {1: (peak: 2, rungSum: 3)});
  });

  test('TERMINAR PIRÁMIDE registra lo hecho y sigue; sin peldaños, nada', () {
    doRung(const Duration(seconds: 2));
    runner.finishPyramid();
    expect(runner.current.block.position, 2);
    expect(runner.completedExercises, 2);

    runner.back(); // vuelve a la pirámide: se deshace lo registrado
    expect(runner.current.kind, StepKind.pyramid);
    expect(runner.completedExercises, 0);
    expect(runner.rung, 1);

    clock.advance(WorkoutRunner.leadIn);
    runner.tick();
    runner.finishPyramid(); // sin hacer ningún peldaño
    expect(runner.completedExercises, 0);
  });

  test('la pirámide en curso sobrevive al snapshot', () {
    doRung(const Duration(seconds: 2)); // 1
    clock.advance(const Duration(seconds: 3));
    runner.complete(); // peldaño 2 en 3 s: descansa 3
    final restored = WorkoutRunner.restore(
      pyramidSession(),
      jsonDecode(jsonEncode(runner.toSnapshot())) as Map<String, dynamic>,
      clock: clock.now,
    );
    expect(restored.rung, 3);
    expect(restored.pyramidPeak, 2);
    expect(restored.rungSum, 3);
    expect(restored.pyramidRestLeft, const Duration(seconds: 3));
  });
}
