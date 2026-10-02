import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';

/// El fondo de Forja: el color `bg` con el grano de serigrafía encima.
///
/// La textura (assets/textures/grain.png, generada con
/// tool/make_grain.dart) es blanca con transparencia; acá se tiñe
/// con `ink` y se le baja la opacidad según el tema. Así la misma imagen
/// sirve para Hierro (motas claras sobre carbón) y para Hueso (motas
/// oscuras sobre papel).
///
/// Va debajo de cada pantalla (ver ForjaPageTransitionsBuilder), y por eso
/// los Scaffold son transparentes. El grano queda solo sobre el fondo: los
/// paneles (Card) y los botones tienen su propio color opaco encima.
class ForjaBackground extends StatelessWidget {
  const ForjaBackground({super.key, required this.child});

  final Widget child;

  static const _grain = AssetImage('assets/textures/grain.png');

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bg,
        image: DecorationImage(
          image: _grain,
          // Se repite en mosaico; la textura empalma consigo misma en los
          // bordes, así que no se ven costuras.
          repeat: ImageRepeat.repeat,
          // Sin suavizado al agrandarla: cada mota queda con bordes duros,
          // como un punto de tinta, y no como una mancha borrosa.
          filterQuality: FilterQuality.none,
          // srcIn: toma la forma (el alfa) de la imagen y la pinta del
          // color dado. Es "teñir" la textura.
          colorFilter: ColorFilter.mode(palette.ink, BlendMode.srcIn),
          opacity: palette.grainOpacity,
        ),
      ),
      // RepaintBoundary separa el contenido en su propia capa de pintura.
      // Sin ella, cada vez que algo de la pantalla se redibuja (la cuenta
      // regresiva de una Fragua, varias veces por segundo) se volvería a
      // pintar también el mosaico del fondo.
      child: RepaintBoundary(child: child),
    );
  }
}

/// Las transiciones entre pantallas de siempre, pero con el fondo de Forja
/// debajo de cada pantalla.
///
/// ¿Por qué acá y no en cada Scaffold? Porque así cada pantalla que se abre
/// con Navigator.push trae su fondo sin que nadie se acuerde de ponerlo: el
/// tema le dice a cada MaterialPageRoute cómo animarse, y esa animación
/// envuelve la pantalla entera. Durante la transición, cada página es una
/// hoja opaca con su grano, y no se mezclan entre sí.
class ForjaPageTransitionsBuilder extends PageTransitionsBuilder {
  const ForjaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Se delega en el PageTransitionsTheme por defecto (las animaciones
    // propias de Android o de iOS): solo cambia la pantalla que se anima.
    return const PageTransitionsTheme().buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      ForjaBackground(child: child),
    );
  }
}
