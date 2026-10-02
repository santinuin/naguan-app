import 'package:flutter/material.dart';

/// Un título que salta de línea entre palabras, pero nunca adentro de una.
///
/// Flutter corta el texto entre palabras; pero si UNA palabra sola no entra
/// en el ancho, la parte por la mitad ("ANTEROPOSTERIO / RES"). Con Archivo
/// Black a 40 px entran unas 12 mayúsculas en un teléfono, y el catálogo
/// tiene palabras de 17. El sistema de diseño lo prohíbe: "nunca dentro de
/// una palabra".
///
/// Este widget mide la palabra más larga con el estilo pedido y, si no
/// entra, achica la fuente lo justo para que entre. Los títulos que ya
/// entran no cambian.
///
/// No sirve FittedBox (como en la marca): escala TODO el texto a una línea,
/// y un título de cinco palabras quedaría diminuto en vez de usar dos
/// renglones.
class ForjaHeadline extends StatelessWidget {
  const ForjaHeadline(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder da las restricciones del padre (el ancho disponible) en
    // el momento de construir: el ancho no se conoce antes del layout.
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style.merge(this.style);
        final fitted = fitLongestWord(
          text,
          style,
          maxWidth: constraints.maxWidth,
          // La letra del sistema (accesibilidad) agranda el texto: hay que
          // medir con la misma escala con la que se va a dibujar.
          textScaler: MediaQuery.textScalerOf(context),
        );
        return Text(text, style: fitted, textAlign: textAlign);
      },
    );
  }
}

/// El estilo con la fuente achicada para que la palabra más larga de [text]
/// entre en [maxWidth] (o el mismo estilo, si ya entra). Una función pura,
/// separada del widget para testearla sin dibujar nada.
TextStyle fitLongestWord(
  String text,
  TextStyle style, {
  required double maxWidth,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final fontSize = style.fontSize;
  if (fontSize == null || !maxWidth.isFinite) return style;

  var widest = 0.0;
  for (final word in text.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    // TextPainter es el motor que usa Text por dentro: mide sin dibujar.
    // Es un recurso nativo, por eso se libera con dispose().
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  if (widest <= maxWidth) return style;
  // El ancho de un texto es proporcional al tamaño de la fuente. El 0.98
  // deja un margen por el redondeo de los píxeles.
  return style.copyWith(fontSize: fontSize * maxWidth / widest * 0.98);
}
