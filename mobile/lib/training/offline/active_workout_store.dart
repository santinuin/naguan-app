import 'dart:convert';

import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/local_store.dart';

/// Una Fragua en curso guardada en el teléfono: la sesión (para no depender
/// de la red al retomar) y el snapshot del runner.
typedef SavedWorkout = ({Session session, Map<String, dynamic> snapshot});

/// Guarda la Fragua en curso mientras se entrena, para poder retomarla si el
/// sistema cierra la app (por memoria, una llamada, la batería...).
class ActiveWorkoutStore {
  const ActiveWorkoutStore(this._store);

  final LocalStore _store;

  static const _key = 'active_workout';

  /// Una Fragua de hace más de esto ya no se retoma: la API no acepta
  /// Fraguas de más de 12 horas.
  static const maxAge = Duration(hours: 12);

  Future<void> save(Session session, Map<String, Object?> snapshot) {
    return _store.write(
      _key,
      jsonEncode({'session': session.toJson(), 'snapshot': snapshot}),
    );
  }

  /// La Fragua guardada, si hay una y no es demasiado vieja. Si el
  /// contenido está corrupto (una versión vieja de la app, un error al
  /// escribir), se descarta en vez de romper la app.
  Future<SavedWorkout?> load({DateTime? now}) async {
    final raw = await _store.read(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final snapshot = json['snapshot'] as Map<String, dynamic>;
      final started = DateTime.parse(snapshot['started_at'] as String);
      if ((now ?? DateTime.now()).difference(started) > maxAge) {
        await clear();
        return null;
      }
      return (
        session: Session.fromJson(json['session'] as Map<String, dynamic>),
        snapshot: snapshot,
      );
    } on Object {
      // on Object atrapa cualquier cosa (también los TypeError de un cast
      // que falla): datos corruptos no pueden impedir abrir la app.
      await clear();
      return null;
    }
  }

  Future<void> clear() => _store.remove(_key);
}
