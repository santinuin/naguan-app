import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/training/training_models.dart';

import 'workout_runner_test.dart' show FakeClock;

/// Un ítem por reps de un ejercicio con o sin carga.
Map<String, Object> _set(
  int id,
  int round,
  int pos,
  String slug,
  bool loaded,
) => {
  'id': id,
  'round': round,
  'position': pos,
  'kind': 'exercise',
  'exercise': {'slug': slug, 'name': slug, 'loaded': loaded},
  'reps': 5,
};

/// Bloque 1: dos vueltas de press (con carga) + dominada (sin carga).
/// Bloque 2: una serie más de press.
Session loadSession() => Session.fromJson({
  'id': 7,
  'kind': 'workout',
  'title': 'Cargas',
  'description': null,
  'blocks': [
    {
      'position': 1,
      'type': 'rounds',
      'phase': 'main',
      'items': [
        _set(1, 1, 1, 'press', true),
        _set(2, 1, 2, 'dominada', false),
        _set(3, 2, 1, 'press', true),
        _set(4, 2, 2, 'dominada', false),
      ],
    },
    {
      'position': 2,
      'type': 'rounds',
      'phase': 'main',
      'items': [_set(5, 1, 1, 'press', true)],
    },
  ],
});

void main() {
  late FakeClock clock;
  late WorkoutRunner runner;

  setUp(() {
    clock = FakeClock();
    // Los últimos pesos llegan antes de EMPEZAR (ver ExecutionScreen):
    // también hay uno de dominada, de una vez que se le sumó lastre.
    runner = WorkoutRunner(loadSession(), clock: clock.now)
      ..lastLoads = {'press': 60, 'dominada': 10}
      ..start();
  });

  test('la primera serie de un ejercicio con carga propone el último peso', () {
    expect(runner.showsLoad, isTrue);
    expect(runner.loadDraft, 60);
  });

  test('las series siguientes del bloque repiten el peso de la anterior', () {
    runner.adjustLoad(WorkoutRunner.loadStep); // 62,5
    runner.complete(); // press, vuelta 1
    runner.complete(); // dominada, vuelta 1
    expect(runner.loadDraft, 62.5, reason: 'press, vuelta 2');
  });

  test('un bloque nuevo vuelve a proponer el último peso, no el de hoy', () {
    runner.adjustLoad(-WorkoutRunner.loadStep); // 57,5 (aproximación)
    for (var i = 0; i < 4; i++) {
      runner.complete();
    }
    expect(runner.current.block.position, 2);
    expect(runner.loadDraft, 60);
  });

  test('sin carga no se muestra el peso ni se propone el lastre', () {
    runner.complete(); // press
    expect(runner.showsLoad, isFalse);
    expect(runner.loadDraft, isNull, reason: 'el lastre se suma a mano');

    // + LASTRE: aparece el peso, y la serie siguiente del bloque lo repite.
    runner.adjustLoad(WorkoutRunner.loadStep);
    expect(runner.showsLoad, isTrue);
    runner.complete(); // dominada con 2,5
    runner.complete(); // press
    expect(runner.loadDraft, 2.5, reason: 'dominada, vuelta 2');

    // Bajar de cero lo saca: queda sin carga.
    runner.adjustLoad(-WorkoutRunner.loadStep);
    expect(runner.loadDraft, isNull);
    expect(runner.showsLoad, isFalse);
  });

  test('cada serie registra su peso', () {
    runner.setLoad(61.237); // escrito a mano: se redondea a dos decimales
    runner.complete();
    runner.complete(); // dominada sin carga
    final workout = _finish(runner);
    final byId = {for (final it in workout.items) it.blockItemId: it};
    expect(byId[1]!.loadKg, 61.24);
    expect(byId[2]!.loadKg, isNull);
    expect(byId[1]!.toJson()['load_kg'], 61.24);
    expect(byId[2]!.toJson().containsKey('load_kg'), isFalse);
    // El más alto de cada ejercicio, para proponerlo la próxima vez.
    expect(runner.usedLoads, {'press': 61.24});
  });

  test('atrás vuelve con el peso que se había marcado', () {
    runner.setLoad(70);
    runner.complete();
    runner.back();
    expect(runner.index, 0);
    expect(runner.loadDraft, 70);
  });

  test('el peso del paso sobrevive al snapshot', () {
    runner.setLoad(65);
    final restored = WorkoutRunner.restore(
      loadSession(),
      jsonDecode(jsonEncode(runner.toSnapshot())) as Map<String, dynamic>,
      clock: clock.now,
    );
    expect(restored.loadDraft, 65);
  });
}

/// Completa lo que falta (todos los pasos son por reps).
NewWorkout _finish(WorkoutRunner runner) {
  while (!runner.isFinished) {
    runner.complete();
  }
  return runner.toNewWorkout();
}
