import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/one_line_text.dart';

/// Etiqueta técnica del sistema de diseño: texto `label` (Space Mono en
/// mayúsculas, con tracking) dentro de una pill con borde fino en `stroke`.
///
/// Es un StatelessWidget: todo lo que muestra sale de sus parámetros y del
/// tema, no tiene estado propio que cambie con el tiempo.
class ForjaPill extends StatelessWidget {
  const ForjaPill(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;

    // DecoratedBox pinta (borde, fondo) y Padding separa: en Flutter cada
    // widget hace una sola cosa y se componen anidándolos. Container junta
    // varias de estas en uno, pero así se ve qué hace cada capa.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: palette.stroke, width: 2),
        borderRadius: BorderRadius.circular(ForjaRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ForjaSpace.s2 + ForjaSpace.s1,
          vertical: ForjaSpace.s1,
        ),
        // Una pill nunca salta de línea: si no entra, se achica.
        child: OneLineText(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
