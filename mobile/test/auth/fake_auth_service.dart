import 'dart:async';

import 'package:naguan_app/auth/auth_service.dart';

/// AuthService falso: la sesión es un bool que el test controla, y los
/// cambios se emiten por un StreamController (el "Sinks.many()" de Dart:
/// lo que se agrega con add sale por su stream).
class FakeAuthService implements AuthService {
  FakeAuthService({this.signedIn = false});

  bool signedIn;

  /// Si no es null, signIn falla con este mensaje.
  String? failWith;

  final signInCalls = <(String, String)>[];

  // broadcast: admite varios oyentes (como un Flux "hot").
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isSignedIn => signedIn;

  @override
  Stream<bool> get signedInChanges => _changes.stream;

  @override
  String? get accessToken => signedIn ? 'token-falso' : null;

  @override
  Future<void> signIn({required String email, required String password}) async {
    signInCalls.add((email, password));
    if (failWith case final message?) throw AuthFailure(message);
    _set(true);
  }

  @override
  Future<void> signOut() async => _set(false);

  void _set(bool value) {
    signedIn = value;
    _changes.add(value);
  }
}
