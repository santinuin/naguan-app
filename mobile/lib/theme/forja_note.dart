import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Una nota de apoyo («2 s de subida y 2 de bajada», cómo hacer las series de
/// aproximación): la etiqueta NOTA en `label` y el texto en `body` con
/// `ink-muted`, el color que el sistema de diseño reserva para "descansos,
/// notas, metadatos".
///
/// La jerarquía va por color y familia, no por tamaño ni itálica: el sistema
/// no usa itálicas (y no hay una fuente itálica empaquetada; Flutter la
/// simularía inclinando las letras), y 16 px es su mínimo de lectura.
class ForjaNote extends StatelessWidget {
  const ForjaNote(this.text, {super.key, this.textAlign = TextAlign.start});

  final String text;

  /// Durante la Fragua todo va centrado; en la lista de bloques, a la
  /// izquierda.
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = context.forja.palette.inkMuted;
    // crossAxisAlignment sigue al textAlign: si el texto va centrado, la
    // etiqueta también.
    return Column(
      crossAxisAlignment: textAlign == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text('NOTA', style: textTheme.labelSmall),
        const SizedBox(height: ForjaSpace.s1),
        Text(
          text,
          textAlign: textAlign,
          style: textTheme.bodyLarge?.copyWith(color: muted),
        ),
      ],
    );
  }
}
