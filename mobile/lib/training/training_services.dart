import 'package:naguan_app/training/offline/active_workout_store.dart';
import 'package:naguan_app/training/offline/pending_workouts.dart';
import 'package:naguan_app/training/training_client.dart';

/// Todo lo que las pantallas necesitan del entrenamiento, en un solo objeto.
///
/// Pasar tres dependencias por separado a través de cuatro pantallas ensucia
/// cada constructor; agruparlas es el mismo criterio que el `Deps` del router
/// en Go. Se arma una vez en main.
class TrainingServices {
  const TrainingServices({
    required this.client,
    required this.activeWorkout,
    required this.pending,
  });

  /// La API de `/v1/me/...`.
  final TrainingClient client;

  /// La Fragua en curso guardada en el teléfono (para retomarla).
  final ActiveWorkoutStore activeWorkout;

  /// Las Fraguas templadas sin registrar (sin señal al terminar).
  final PendingWorkouts pending;
}
