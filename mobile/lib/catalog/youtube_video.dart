import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Un video de YouTube embebido: arranca solo, sin sonido y en bucle, como
/// una demo del movimiento. Los controles de YouTube quedan para pausar o
/// activar el sonido.
///
/// Por dentro es un WebView (un navegador embebido) con el reproductor
/// oficial de YouTube: el paquete habla con él por JavaScript. Es la única
/// pieza de la app que conoce YouTube; si los videos pasan a R2, se cambia
/// este widget y nada más.
///
/// Un WebView no existe en los widget tests: las pantallas lo reciben como
/// un builder (ver ExerciseScreen.videoBuilder) y los tests lo reemplazan.
class YoutubeVideo extends StatefulWidget {
  const YoutubeVideo({super.key, required this.url});

  final String url;

  /// Los shorts son verticales (9:16); el resto, horizontales.
  bool get isShort => url.contains('/shorts/');

  @override
  State<YoutubeVideo> createState() => _YoutubeVideoState();
}

class _YoutubeVideoState extends State<YoutubeVideo> {
  /// Null si la URL no es de un video de YouTube.
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _loop;

  @override
  void initState() {
    super.initState();
    final id = YoutubePlayerController.convertUrlToId(widget.url);
    if (id == null) return;

    final controller = YoutubePlayerController.fromVideoId(
      videoId: id,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: true,
        showFullscreenButton: true,
        // Sin videos sugeridos de otros canales al final.
        strictRelatedVideos: true,
        interfaceLanguage: 'es',
        captionLanguage: 'es',
      ),
    );
    // El parámetro `loop` del reproductor de YouTube solo funciona con
    // listas de reproducción. Para un video suelto, el bucle se hace a
    // mano: al terminar, volver al principio. `listen` es como subscribe()
    // de un Flux; la suscripción se cancela en dispose.
    _loop = controller.listen((value) {
      if (value.playerState == PlayerState.ended) {
        controller.seekTo(seconds: 0, allowSeekAhead: true);
        controller.playVideo();
      }
    });
    _controller = controller;
  }

  @override
  void dispose() {
    _loop?.cancel();
    // close() libera el WebView del reproductor.
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const Text('Video no disponible.');
    }

    final aspectRatio = widget.isShort ? 9 / 16 : 16 / 9;
    // Un short a todo el ancho mediría más que la pantalla: se limita el
    // alto y se centra. ConstrainedBox pone el tope; el reproductor se
    // ajusta adentro respetando la proporción.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: YoutubePlayer(
            controller: controller,
            aspectRatio: aspectRatio,
          ),
        ),
      ),
    );
  }
}
