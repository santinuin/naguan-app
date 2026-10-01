import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento local simple (texto por clave): lo que la app necesita del
/// disco del teléfono. Sobrevive a cerrar la app y a reiniciar el teléfono.
///
/// Es una interfaz propia (como AuthService): la app usa la implementación
/// con shared_preferences, y los tests una en memoria.
abstract interface class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// LocalStore sobre shared_preferences: en Android guarda en un archivo
/// privado de la app (SharedPreferences del sistema); en iOS, en
/// NSUserDefaults. Sirve para datos chicos; para muchos datos o consultas
/// haría falta una base local (sqflite, drift).
///
/// SharedPreferencesAsync es la API nueva del paquete: cada lectura va al
/// disco, sin una copia en memoria que pueda quedar desactualizada.
class PrefsLocalStore implements LocalStore {
  final _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}
