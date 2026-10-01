import 'package:flutter/material.dart';
import 'package:naguan_app/auth/auth_service.dart';
import 'package:naguan_app/auth/login_screen.dart';

/// Decide qué mostrar según haya sesión o no: la pantalla de ingreso, o la
/// app ([signedIn]).
///
/// Es reactivo: escucha el stream de cambios de sesión, así que entrar,
/// salir o que la sesión se pierda (refresh token revocado) cambia la
/// pantalla sola, sin que nadie navegue a mano.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.auth, required this.signedIn});

  final AuthService auth;

  /// Lo que se muestra con sesión. Es un builder (una función) para que la
  /// pantalla se construya recién cuando hace falta.
  final WidgetBuilder signedIn;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Igual que el Future de LoadView: el stream se obtiene una vez y se
  /// guarda. `signedInChanges` arma un stream nuevo en cada llamada (hace
  /// un .map); pedirlo en build() haría que el StreamBuilder se
  /// desuscribiera y volviera a suscribir en cada rebuild.
  late final Stream<bool> _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.auth.signedInChanges;
  }

  @override
  Widget build(BuildContext context) {
    // StreamBuilder es a un Stream lo que FutureBuilder a un Future: se
    // reconstruye con cada valor nuevo. initialData evita un frame vacío
    // antes del primer evento: el estado actual se conoce desde el inicio.
    return StreamBuilder<bool>(
      stream: _changes,
      initialData: widget.auth.isSignedIn,
      builder: (context, snapshot) {
        final isSignedIn = snapshot.data ?? false;
        return isSignedIn
            ? widget.signedIn(context)
            : LoginScreen(auth: widget.auth);
      },
    );
  }
}
