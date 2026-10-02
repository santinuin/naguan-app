import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// El bloqueo del teléfono (huella, cara, PIN, patrón) como candado de la
/// app.
///
/// La app nunca ve la huella: le pide al sistema operativo que verifique a
/// quien tiene el teléfono, y recibe un sí o un no. Interfaz propia para que
/// LockGate se teste con un fake, sin hardware.
abstract interface class DeviceLock {
  /// Pide desbloquear. true si el usuario se verificó (o si el teléfono no
  /// tiene ningún bloqueo configurado: ver [LocalAuthDeviceLock]); false si
  /// canceló o falló.
  Future<bool> unlock();
}

/// DeviceLock con local_auth (BiometricPrompt en Android).
class LocalAuthDeviceLock implements DeviceLock {
  final _auth = LocalAuthentication();

  @override
  Future<bool> unlock() async {
    // Sin bloqueo de pantalla configurado no hay con qué verificar, y se
    // deja pasar. No es un agujero: quien tiene el teléfono ya puede usarlo
    // entero, y no puede sacarle el bloqueo a un teléfono ajeno sin
    // desbloquearlo antes. El candado de la app vale lo mismo que el del
    // teléfono, nunca más.
    if (!await _auth.isDeviceSupported()) return true;

    try {
      return await _auth.authenticate(
        localizedReason: 'Desbloqueá para entrar a la Forja.',
        // false: si la huella falla o no hay, el sistema ofrece el PIN o el
        // patrón del teléfono. Con true, alguien sin huella cargada (o con
        // el dedo lastimado) quedaría afuera.
        biometricOnly: false,
        // Si entra una llamada con el diálogo abierto, al volver se reintenta
        // en vez de devolver un error.
        persistAcrossBackgrounding: true,
        // Los textos del diálogo del sistema; por defecto están en inglés.
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'DESBLOQUEÁ NAGUAN',
            signInHint: 'Huella, cara o PIN del teléfono.',
            cancelButton: 'CANCELAR',
          ),
        ],
      );
    } on LocalAuthException catch (e) {
      // Se sacó el bloqueo de pantalla entre el chequeo y el diálogo: mismo
      // criterio que arriba.
      if (e.code == LocalAuthExceptionCode.noCredentialsSet) return true;
      // Cancelado, demasiados intentos, sin pantalla disponible...: no se
      // entra. LockGate deja reintentar o salir.
      return false;
    }
  }
}
