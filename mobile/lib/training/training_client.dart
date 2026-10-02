import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/training/training_models.dart';

/// Cliente de los endpoints del usuario (`/v1/me/...`): progreso, Brasa,
/// Mojones y registro de Fraguas.
class TrainingClient {
  const TrainingClient(this._api);

  final ApiClient _api;

  Future<List<ProgramProgress>> fetchProgress() async {
    final json = await _api.getJson('/me/programs');
    if (json is! List) {
      throw const ApiException('se esperaba una lista de progreso');
    }
    return [
      for (final p in json) ProgramProgress.fromJson(p as Map<String, dynamic>),
    ];
  }

  Future<ProgramProgress> fetchProgramProgress(String slug) async {
    final json = await _api.getJson(
      '/me/programs/${Uri.encodeComponent(slug)}',
    );
    return ProgramProgress.fromJson(json as Map<String, dynamic>);
  }

  Future<void> resetProgram(String slug) =>
      _api.delete('/me/programs/${Uri.encodeComponent(slug)}/progress');

  /// Las estadísticas de hoy: la app manda su fecha local, porque la Brasa
  /// se cuenta en días del teléfono.
  Future<Stats> fetchStats({DateTime? now}) async {
    final today = localDateString(now ?? DateTime.now());
    final json = await _api.getJson('/me/stats?today=$today');
    return Stats.fromJson(json as Map<String, dynamic>);
  }

  /// Una página del historial, de la Fragua más reciente a la más vieja.
  /// [before] es el id de la última Fragua de la página anterior (null = la
  /// primera página).
  Future<List<Workout>> fetchWorkouts({int? before, int limit = 20}) async {
    final query = before == null
        ? 'limit=$limit'
        : 'limit=$limit&before=$before';
    final json = await _api.getJson('/me/workouts?$query');
    if (json is! List) {
      throw const ApiException('se esperaba una lista de fraguas');
    }
    return [for (final w in json) Workout.fromJson(w as Map<String, dynamic>)];
  }

  /// Los Mojones: la mejor marca en cada ejercicio.
  Future<List<Record>> fetchRecords() async {
    final json = await _api.getJson('/me/records');
    if (json is! List) {
      throw const ApiException('se esperaba una lista de mojones');
    }
    return [for (final r in json) Record.fromJson(r as Map<String, dynamic>)];
  }

  Future<WorkoutResult> recordWorkout(NewWorkout workout) async {
    final json = await _api.postJson('/me/workouts', workout.toJson());
    return WorkoutResult.fromJson(json as Map<String, dynamic>);
  }
}
