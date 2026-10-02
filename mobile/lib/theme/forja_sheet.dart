import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// El contenido de una hoja inferior como un panel de Forja completo: borde
/// grueso en los cuatro lados, esquinas redondeadas y la manija arriba.
///
/// La hoja de Material se pega al borde de la pantalla y sigue por debajo
/// de la barra de gestos: con un borde grueso, los laterales se cortaban
/// contra las esquinas redondeadas del teléfono y el panel parecía
/// desbordarse hacia abajo. Acá la hoja del sistema es transparente (ver
/// bottomSheetTheme) y el panel se dibuja adentro, separado de los bordes y
/// por encima del área segura (la barra de gestos).
class ForjaSheet extends StatelessWidget {
  const ForjaSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;
    // viewPadding.bottom: lo que ocupa la barra de gestos (o los botones de
    // navegación). El panel termina encima.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ForjaSpace.s2,
        0,
        ForjaSpace.s2,
        ForjaSpace.s2 + bottomInset,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(ForjaRadius.panel),
          border: Border.all(color: palette.stroke, width: ForjaBorder.heavy),
        ),
        // El borde de un BoxDecoration se dibuja ENCIMA del hijo, no lo
        // corre: sin este padding, la manija quedaba pisando el borde.
        child: Padding(
          padding: const EdgeInsets.all(ForjaBorder.heavy),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // La manija: avisa que la hoja se puede bajar para cerrarla.
              Padding(
                padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s2),
                child: SizedBox(
                  width: 32,
                  height: 4,
                  child: ColoredBox(color: palette.inkMuted),
                ),
              ),
              // Flexible: si el contenido es más alto que la pantalla, se
              // achica (y su scroll interno se encarga) en vez de desbordar.
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
