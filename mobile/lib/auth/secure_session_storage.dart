import 'package:naguan_app/common/local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Dónde guarda supabase_flutter la sesión: en un [LocalStore] cifrado en vez
/// de su opción por defecto (shared_preferences, en texto plano).
///
/// supabase_flutter define el "puerto" ([supa.LocalStorage]) y nosotros
/// enchufamos el adaptador: el mismo patrón que AuthService o LocalStore,
/// pero al revés (acá la interfaz es de la librería y la implementación es
/// nuestra). Se pasa en `Supabase.initialize(authOptions: ...)`.
///
/// La "sesión" es un JSON con el token de acceso, el **refresh token** (el
/// valioso: con él se consiguen tokens nuevos durante semanas) y los datos
/// del usuario. supabase_flutter lo serializa; acá solo se guarda el texto.
///
/// `extends` y no `implements`: LocalStorage es una clase abstracta común
/// (no una `interface class`), y heredarla es como lo propone la librería.
class SecureSessionStorage extends supa.LocalStorage {
  SecureSessionStorage(this._store);

  final LocalStore _store;

  static const _key = 'supabase_session';

  // El almacén no necesita preparación (flutter_secure_storage se inicializa
  // solo en la primera operación).
  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => await _store.read(_key) != null;

  // El nombre engaña (es de la librería): no devuelve solo el token de
  // acceso sino la sesión completa en JSON, la misma que recibe
  // persistSession.
  @override
  Future<String?> accessToken() => _store.read(_key);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _store.write(_key, persistSessionString);

  @override
  Future<void> removePersistedSession() => _store.remove(_key);
}
