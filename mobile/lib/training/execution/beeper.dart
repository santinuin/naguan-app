import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';

/// Los pitidos de la cuenta regresiva: el runner decide CUÁNDO pitar (un
/// [Cue]); esto solo sabe CÓMO sonar.
///
/// Una interfaz chica para que la pantalla no dependa de un plugin nativo:
/// en los tests se pasa un fake que anota los pitidos.
abstract interface class Beeper {
  void play(Cue cue);
}

/// Los pitidos de verdad, con `audioplayers`.
///
/// Se crea una vez (en main) y vive lo que la app: los sonidos se cargan al
/// arrancar y quedan listos, así el primer "pi" no espera a leer el archivo.
class AudioBeeper implements Beeper {
  AudioBeeper() : _players = _load() {
    // Si la carga falla y nunca se llega a pitar, nadie escucha ese error y
    // Dart lo reporta como "no manejado". ignore() le pone un oyente que lo
    // descarta; quien sí haga await (en _play) igual lo recibe.
    _players.ignore();
  }

  /// Un reproductor por sonido, ya cargado. Es un Future: se empieza a
  /// cargar en el constructor (que no puede ser async) y [play] lo espera
  /// (la primera vez; después ya está completo y await vuelve al toque).
  final Future<Map<Cue, AudioPlayer>> _players;

  static Future<Map<Cue, AudioPlayer>> _load() async {
    // mixWithOthers: el pitido suena encima de la música, sin pausarla ni
    // bajarle el volumen. Con "duckOthers" (bajarla un instante) el sistema
    // devuelve el volumen cuando el sonido termina, pero el modo de baja
    // latencia no avisa cuándo termina: la música quedaría baja toda la
    // Fragua.
    //
    // Sin respectSilence: suena por el canal de multimedia aunque el
    // teléfono esté en silencio (lo regula el volumen de multimedia).
    final context = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();

    Future<AudioPlayer> player(String asset) async {
      final p = AudioPlayer();
      // lowLatency: en Android usa SoundPool, pensado para efectos cortos
      // (juegos): el sonido queda en memoria y arranca sin demora. El modo
      // por defecto (MediaPlayer) es para música y tarda en empezar.
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setAudioContext(context);
      // Con el modo por defecto (release), stop() libera el sonido y habría
      // que volver a cargarlo antes de cada pitido.
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setSource(AssetSource(asset)); // relativo a assets/
      return p;
    }

    return {
      Cue.count: await player('sounds/pi.wav'),
      Cue.go: await player('sounds/piii.wav'),
    };
  }

  @override
  void play(Cue cue) => unawaited(_play(cue));

  Future<void> _play(Cue cue) async {
    try {
      final player = (await _players)[cue]!;
      // stop + resume: si el pitido anterior todavía suena, vuelve a
      // empezar desde el principio.
      await player.stop();
      await player.resume();
    } catch (e) {
      // Un pitido que falla no puede romper la Fragua: queda en el log y
      // la cuenta se sigue viendo en la pantalla.
      debugPrint('No se pudo pitar: $e');
    }
  }
}
