import 'package:supabase_flutter/supabase_flutter.dart' as supa;

/// Error de autenticación con un mensaje para mostrar al usuario.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// Lo que la app necesita de la autenticación.
///
/// `abstract interface class` (Dart 3) es una interfaz pura: se puede
/// implementar pero no heredar ni instanciar. Las pantallas dependen de esto
/// y no de Supabase: los tests usan un fake, y cambiar de proveedor toca un
/// solo archivo.
abstract interface class AuthService {
  /// Si hay una sesión activa ahora.
  bool get isSignedIn;

  /// Emite cada vez que cambia el estado: true al entrar, false al salir (o
  /// si la sesión se pierde). Es un Stream: el Flux de Dart.
  Stream<bool> get signedInChanges;

  /// El token de acceso vigente, o null sin sesión. Lo pide el cliente de la
  /// API en cada request.
  String? get accessToken;

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();
}

/// AuthService con Supabase Auth.
///
/// supabase_flutter se encarga de lo difícil: guarda la sesión en el
/// teléfono (sobrevive a cerrar la app) y renueva el token de acceso con el
/// refresh token antes de que venza. Ver docs/autenticacion.md.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final supa.GoTrueClient _auth;

  @override
  bool get isSignedIn => _auth.currentSession != null;

  @override
  Stream<bool> get signedInChanges =>
      // map transforma cada evento, como el map de un Flux.
      _auth.onAuthStateChange.map((state) => state.session != null);

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on supa.AuthException catch (e) {
      // Supabase responde "invalid_credentials" tanto si el email no existe
      // como si la contraseña es incorrecta: a propósito, para no revelar
      // qué emails están registrados.
      if (e.code == 'invalid_credentials') {
        throw const AuthFailure('Email o contraseña incorrectos.');
      }
      throw AuthFailure('No se pudo entrar: ${e.message}');
    } on Exception {
      throw const AuthFailure('Sin conexión con el servidor.');
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
