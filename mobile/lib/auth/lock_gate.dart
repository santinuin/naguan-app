import 'package:flutter/material.dart';
import 'package:naguan_app/auth/auth_service.dart';
import 'package:naguan_app/auth/device_lock.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Candado de la app: con una sesión guardada, pide huella (o el PIN del
/// teléfono) antes de mostrar nada.
///
/// Se bloquea en dos momentos:
/// - **Al abrir la app** con una sesión recuperada del disco. Si recién
///   entraste con contraseña no: ya te verificaste.
/// - **Al volver** después de [lockAfter] o más en segundo plano. Salir un
///   momento (cambiar la música en medio de una Fragua) no bloquea.
///
/// Va en `MaterialApp.builder`, **por encima del Navigator**, y no como una
/// pantalla más: las pantallas que se abren con Navigator.push quedan arriba
/// de `home`, así que un candado puesto en `home` quedaría tapado por ellas.
/// Desde el builder envuelve a todas.
class LockGate extends StatefulWidget {
  const LockGate({
    super.key,
    required this.auth,
    required this.lock,
    required this.child,
    this.lockAfter = const Duration(minutes: 5),
    this.now = DateTime.now,
  });

  final AuthService auth;
  final DeviceLock lock;

  /// La app entera (el Navigator que arma MaterialApp).
  final Widget child;

  final Duration lockAfter;

  /// El reloj, inyectable como en WorkoutRunner: los tests simulan que pasó
  /// el tiempo sin esperarlo. `DateTime.now` sin paréntesis es la función
  /// (un tear-off), no su resultado.
  final DateTime Function() now;

  @override
  State<LockGate> createState() => _LockGateState();
}

/// `with WidgetsBindingObserver`: un *mixin*, código que se "mezcla" en la
/// clase. Java no tiene equivalente directo (lo más cercano son los métodos
/// default de una interfaz, pero un mixin también puede tener estado). Aporta
/// callbacks de la app con implementación vacía; se sobrescribe solo el que
/// interesa, [didChangeAppLifecycleState].
class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  /// Si el candado tapa la app.
  late bool _locked;

  /// Si la app ya se mostró alguna vez. Hasta el primer desbloqueo no se
  /// construye: ni se ve, ni hace requests.
  late bool _shown;

  /// Hay un diálogo del sistema abierto. Evita pedir dos a la vez (local_auth
  /// lo rechaza con `authInProgress`) y deshabilita el botón.
  bool _unlocking = false;

  /// El último intento no salió (cancelado o fallido).
  bool _failed = false;

  /// Cuándo pasó la app a segundo plano.
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    // Registrarse para recibir los cambios de ciclo de vida. Lo que se
    // registra en initState se desregistra en dispose, como los controllers.
    WidgetsBinding.instance.addObserver(this);

    // supabase_flutter ya recuperó la sesión del disco antes de runApp, así
    // que acá se sabe si hay que bloquear.
    _locked = widget.auth.isSignedIn;
    _shown = !_locked;
    if (_locked) {
      // Después del primer frame: el diálogo del sistema necesita que la
      // Activity ya muestre algo. Además, _unlock llama a setState, que no
      // se puede llamar durante initState.
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// El ciclo de vida de la app: resumed (al frente), inactive (tapada por
  /// algo del sistema, p. ej. el diálogo de huella), hidden y paused (en
  /// segundo plano).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // ??= asigna solo si es null: cuenta desde la primera vez que se fue.
        _backgroundedAt ??= widget.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            !_locked &&
            widget.auth.isSignedIn &&
            widget.now().difference(since) >= widget.lockAfter) {
          setState(() {
            _locked = true;
            _failed = false;
          });
          _unlock();
        }
      // switch de Dart 3 es exhaustivo con enums: hay que cubrir todos los
      // casos o tener un default. Los cases no "caen" al siguiente (no hace
      // falta break).
      default:
        break;
    }
  }

  Future<void> _unlock() async {
    if (_unlocking) return;
    setState(() => _unlocking = true);

    final ok = await widget.lock.unlock();

    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _locked = !ok;
      _failed = !ok;
      if (ok) _shown = true;
    });
  }

  /// La salida si la huella no anda: cerrar la sesión y entrar con la
  /// contraseña. Sin esto, alguien que no puede verificarse (dedo lastimado,
  /// teléfono nuevo) quedaría encerrado.
  Future<void> _signOut() async {
    await widget.auth.signOut();
    if (!mounted) return;
    setState(() {
      _locked = false;
      _failed = false;
      // Mostrar la app ahora es seguro: sin sesión, AuthGate muestra el
      // ingreso.
      _shown = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Un Stack apila a sus hijos: el último queda arriba. La app sigue viva
    // debajo del candado (una Fragua en curso no pierde su estado ni su
    // timer); el candado es opaco y se queda con todos los toques.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_shown) widget.child,
        if (_locked)
          _LockScreen(
            unlocking: _unlocking,
            failed: _failed,
            onUnlock: _unlock,
            onSignOut: _signOut,
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.unlocking,
    required this.failed,
    required this.onUnlock,
    required this.onSignOut,
  });

  final bool unlocking;
  final bool failed;
  final VoidCallback onUnlock;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ForjaSpace.s4,
            ForjaSpace.s12,
            ForjaSpace.s4,
            ForjaSpace.s8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('NAGUAN', style: theme.textTheme.displayLarge),
              const SizedBox(height: ForjaSpace.s2),
              Text(
                failed ? 'No se pudo desbloquear.' : 'Desbloqueá para entrar.',
                style: failed
                    ? theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.error,
                      )
                    : theme.textTheme.bodyLarge,
              ),
              // Spacer ocupa el espacio libre: empuja los botones abajo, a
              // mano del pulgar.
              const Spacer(),
              FilledButton(
                onPressed: unlocking ? null : onUnlock,
                child: const Text('DESBLOQUEAR'),
              ),
              const SizedBox(height: ForjaSpace.s2),
              TextButton(
                onPressed: unlocking ? null : onSignOut,
                child: const Text('ENTRAR CON CONTRASEÑA'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
