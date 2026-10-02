import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/one_line_text.dart';

/// Una pill que se puede tocar: los filtros y la navegación secundaria del
/// sistema de diseño (radio pill, borde en `stroke`, texto `label`).
///
/// Sin elegir, solo el borde y el texto en rosa; elegida ([selected]),
/// rellena de acento con el texto en tinta. Para ocupar el ancho, va dentro
/// de un Expanded: varias del mismo ancho forman un selector (los lados de
/// un ejercicio) o una fila de accesos (HISTORIAL / MOJONES).
class ForjaPillButton extends StatelessWidget {
  const ForjaPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ForjaRadius.pill),
      side: BorderSide(color: palette.stroke, width: 2),
    );
    // Material da el fondo y la forma; InkWell, el toque (con la onda
    // recortada a la pill gracias a customBorder).
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? palette.accent : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onPressed,
          child: SizedBox(
            // 48: el alto mínimo cómodo para el pulgar.
            height: 48,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: ForjaSpace.s4),
                child: OneLineText(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 14,
                    // Sobre el acento, siempre tinta (on-accent).
                    color: selected ? palette.onAccent : palette.accentText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
