import 'dart:async';

import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/exercise.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/local_store.dart';
import 'package:naguan_app/training/offline/active_workout_store.dart';
import 'package:naguan_app/training/offline/pending_workouts.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';
import 'package:naguan_app/training/training_services.dart';

import '../common/memory_local_store.dart';

/// Devuelve el Future de un Completer nuevo y lo guarda en [calls]: el test
/// decide cuándo y cómo responde (y puede contar llamadas).
Future<T> nextCall<T>(List<Completer<T>> calls) {
  final completer = Completer<T>();
  calls.add(completer);
  return completer.future;
}

/// Cliente falso del catálogo, compartido por los tests de pantallas.
class FakeCatalogClient implements CatalogClient {
  final programCalls = <Completer<Program>>[];
  final sessionCalls = <Completer<Session>>[];
  final exerciseCalls = <Completer<Exercise>>[];
  final requestedSlugs = <String>[];
  final requestedSessionIds = <int>[];

  @override
  Future<Program> fetchProgram(String slug) {
    requestedSlugs.add(slug);
    return nextCall(programCalls);
  }

  @override
  Future<Session> fetchSession(int id) {
    requestedSessionIds.add(id);
    return nextCall(sessionCalls);
  }

  @override
  Future<Exercise> fetchExercise(String slug) {
    requestedSlugs.add(slug);
    return nextCall(exerciseCalls);
  }
}

/// Cliente falso del entrenamiento, con el mismo esquema de Completers.
class FakeTrainingClient implements TrainingClient {
  final progressCalls = <Completer<List<ProgramProgress>>>[];
  final programProgressCalls = <Completer<ProgramProgress>>[];
  final statsCalls = <Completer<Stats>>[];
  final recordCalls = <Completer<WorkoutResult>>[];
  final recorded = <NewWorkout>[];
  final resets = <String>[];

  @override
  Future<List<ProgramProgress>> fetchProgress() => nextCall(progressCalls);

  @override
  Future<ProgramProgress> fetchProgramProgress(String slug) =>
      nextCall(programProgressCalls);

  @override
  Future<Stats> fetchStats({DateTime? now}) => nextCall(statsCalls);

  @override
  Future<void> resetProgram(String slug) async => resets.add(slug);

  @override
  Future<WorkoutResult> recordWorkout(NewWorkout workout) {
    recorded.add(workout);
    return nextCall(recordCalls);
  }
}

/// Los servicios de entrenamiento para los tests: el cliente falso y los
/// almacenes en memoria.
TrainingServices fakeServices({FakeTrainingClient? client, LocalStore? store}) {
  final local = store ?? MemoryLocalStore();
  return TrainingServices(
    client: client ?? FakeTrainingClient(),
    activeWorkout: ActiveWorkoutStore(local),
    pending: PendingWorkouts(local),
  );
}
