import 'package:flutter/material.dart';

/// Un texto que nunca salta de línea: si no entra en el ancho, se achica.
///
/// Es para las etiquetas cortas (botones, pills, selectores): "IZQUIERDA"
/// partida en "IZQUIERD / A" dentro de un botón angosto no se lee, y
/// depende del teléfono (el ancho de la pantalla, la letra del sistema).
/// Achicada un poco sí se lee. Para títulos largos, que sí pueden ocupar
/// varias líneas, está ForjaHeadline.
///
/// La regla de la app: las etiquetas de botones, pills y selectores van con
/// OneLineText, nunca con un Text suelto.
class OneLineText extends StatelessWidget {
  const OneLineText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // scaleDown: achica el texto si no entra y lo deja igual si entra
    // (BoxFit.contain también lo agrandaría). maxLines + softWrap: false
    // hacen que el Text mida su largo en una sola línea, que es lo que el
    // FittedBox compara contra el ancho disponible.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: style, maxLines: 1, softWrap: false),
    );
  }
}
