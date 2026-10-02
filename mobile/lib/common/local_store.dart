import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

/// LocalStore cifrado, para secretos (la sesión con su refresh token).
///
/// En Android, flutter_secure_storage cifra cada valor con AES-GCM; la clave
/// AES está a su vez cifrada con una clave RSA que vive en el **Android
/// Keystore**: un almacén del sistema, respaldado por hardware en la mayoría
/// de los teléfonos, del que la clave privada no se puede extraer. Si alguien
/// copia los archivos de la app a otro equipo (un backup, un volcado), solo
/// ve texto cifrado: la clave para descifrarlo nunca sale del teléfono. En
/// iOS usa el Keychain.
///
/// Es más lento que PrefsLocalStore (cada operación cifra o descifra), así
/// que va solo para lo que lo justifica.
class SecureLocalStore implements LocalStore {
  // AndroidOptions() es el cifrado recomendado desde la versión 10 del
  // paquete (RSA OAEP + AES-GCM). Existe AndroidOptions.biometric(), que
  // pide la huella para descifrar, pero el candado de la app ya lo hace
  // LockGate; atar el cifrado a la huella haría que el refresco del token
  // en segundo plano dependiera de que el usuario ponga el dedo.
  final _storage = const FlutterSecureStorage(aOptions: AndroidOptions());

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}
