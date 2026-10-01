import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/training/offline/active_workout_store.dart';
import 'package:naguan_app/training/offline/pending_workouts.dart';
import 'package:naguan_app/training/training_models.dart';

import '../catalog/fake_catalog_client.dart';
import '../common/memory_local_store.dart';
import 'workout_runner_test.dart' show testSession;

NewWorkout workout(String clientId) => NewWorkout(
  clientId: clientId,
  sessionId: 1,
  startedAt: DateTime.utc(2026, 10, 1, 20),
  finishedAt: DateTime.utc(2026, 10, 1, 20, 30),
  items: const [ItemResult.reps(10, 12)],
  amrapRounds: const {2: 5},
);

void main() {
  group('PendingWorkouts', () {
    test('guarda y relee las Fraguas, sin duplicar por client_id', () async {
      final queue = PendingWorkouts(MemoryLocalStore());

      await queue.add(workout('a'));
      await queue.add(workout('a')); // el mismo otra vez
      await queue.add(workout('b'));

      final all = await queue.list();
      expect(all.map((w) => w.clientId), ['a', 'b']);
      expect(all.first.amrapRounds, {2: 5});
      expect(all.first.items.single.reps, 12);
    });

    test('flush registra en orden y se corta sin conexión', () async {
      final queue = PendingWorkouts(MemoryLocalStore());
      await queue.add(workout('a'));
      await queue.add(workout('b'));
      final client = FakeTrainingClient();

      final left = queue.flush(client);
      // La primera se registra; la segunda falla sin conexión.
      await Future<void>.delayed(Duration.zero);
      client.recordCalls[0].complete(
        const WorkoutResult(id: 1, newRecords: []),
      );
      await Future<void>.delayed(Duration.zero);
      client.recordCalls[1].completeError(const ApiException('sin red'));

      expect(await left, 1);
      expect((await queue.list()).single.clientId, 'b');
    });

    test('flush descarta una Fragua que la API rechaza (4xx)', () async {
      final queue = PendingWorkouts(MemoryLocalStore());
      await queue.add(workout('a'));
      final client = FakeTrainingClient();

      final left = queue.flush(client);
      await Future<void>.delayed(Duration.zero);
      client.recordCalls.single.completeError(
        const ApiException('no existe la sesión', statusCode: 400),
      );

      expect(await left, 0);
      expect(await queue.list(), isEmpty);
    });
  });

  group('ActiveWorkoutStore', () {
    final now = DateTime.utc(2026, 10, 1, 21);
    final snapshot = {'started_at': '2026-10-01T20:00:00.000Z', 'index': 0};

    test('guarda y recupera la sesión y el snapshot', () async {
      final store = ActiveWorkoutStore(MemoryLocalStore());
      await store.save(testSession(), snapshot);

      final saved = await store.load(now: now);

      expect(saved?.session.id, 99);
      expect(saved?.snapshot['index'], 0);
    });

    test('descarta una Fragua de más de 12 horas', () async {
      final store = ActiveWorkoutStore(MemoryLocalStore());
      await store.save(testSession(), snapshot);

      expect(await store.load(now: now.add(const Duration(hours: 13))), isNull);
    });

    test('descarta datos corruptos en vez de romper', () async {
      final local = MemoryLocalStore()..values['active_workout'] = '{roto';

      expect(await ActiveWorkoutStore(local).load(now: now), isNull);
      expect(local.values, isEmpty);
    });
  });
}
