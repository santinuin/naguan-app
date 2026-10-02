import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Un Markdown mínimo: el que usan las descripciones de los ejercicios.
///
/// Soporta párrafos (separados por una línea en blanco), listas con `- ` o
/// numeradas (`1. `) y **negrita**. Todo lo demás se muestra como texto.
///
/// ¿Por qué no un paquete? El oficial (flutter_markdown) está discontinuado,
/// y las descripciones usan tres construcciones: ochenta líneas propias,
/// testeadas, pesan menos que una dependencia que hay que seguir.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final blocks = parseMarkdown(source);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed) ...[
          // Más aire antes de un párrafo que entre ítems de una lista.
          if (index > 0)
            SizedBox(
              height: block is MdListItem && blocks[index - 1] is MdListItem
                  ? ForjaSpace.s1
                  : ForjaSpace.s4,
            ),
          // switch sobre una sealed class: el compilador sabe que solo hay
          // dos subtipos y exige cubrir ambos (si mañana se agrega un
          // MdHeading, esto deja de compilar hasta que se lo dibuje).
          switch (block) {
            MdParagraph(:final spans) => Text.rich(_rich(spans, style)),
            MdListItem(:final marker, :final spans) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ForjaSpace.s6,
                  child: Text(marker, style: style),
                ),
                Expanded(child: Text.rich(_rich(spans, style))),
              ],
            ),
          },
        ],
      ],
    );
  }

  /// Los tramos como TextSpan: el texto con estilos mezclados de Flutter
  /// (un árbol de spans dentro de un solo Text.rich).
  TextSpan _rich(List<MdSpan> spans, TextStyle style) => TextSpan(
    children: [
      for (final span in spans)
        TextSpan(
          text: span.text,
          style: span.bold ? style.copyWith(fontWeight: FontWeight.w700) : null,
        ),
    ],
  );
}

/// Un bloque de Markdown.
///
/// `sealed` (Dart 3): la clase es abstracta y sus subtipos tienen que estar
/// en este mismo archivo, así que el compilador conoce la lista completa.
/// Es el `sealed interface ... permits` de Java 17.
sealed class MdBlock {
  const MdBlock(this.spans);

  final List<MdSpan> spans;
}

class MdParagraph extends MdBlock {
  const MdParagraph(super.spans);
}

class MdListItem extends MdBlock {
  const MdListItem(this.marker, super.spans);

  /// "•" en las listas con `- `, o el número ("1.") en las numeradas.
  final String marker;
}

/// Un tramo de texto, en negrita o no. Un record con nombres: igualdad
/// estructural gratis, cómodo en los tests.
typedef MdSpan = ({String text, bool bold});

final _numbered = RegExp(r'^(\d+\.)\s+');

/// Parte el texto en bloques. Es una función pura (texto → datos), separada
/// del widget: se testea sin montar nada.
List<MdBlock> parseMarkdown(String source) {
  final blocks = <MdBlock>[];
  // Las líneas del párrafo en curso: en Markdown, un salto de línea simple
  // no corta el párrafo; se une con un espacio.
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MdParagraph(parseInline(paragraph.join(' '))));
    paragraph.clear();
  }

  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flushParagraph();
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      flushParagraph();
      blocks.add(MdListItem('•', parseInline(line.substring(2).trim())));
    } else if (_numbered.firstMatch(line) case final match?) {
      flushParagraph();
      blocks.add(
        MdListItem(match.group(1)!, parseInline(line.substring(match.end))),
      );
    } else {
      paragraph.add(line);
    }
  }
  flushParagraph();
  return blocks;
}

/// Separa la negrita: al partir por `**`, los tramos impares quedan
/// adentro ("a **b** c" → ["a ", "b", " c"]). Un `**` sin cerrar deja el
/// resto en negrita, que es un error visible y no se pierde texto.
List<MdSpan> parseInline(String text) {
  final parts = text.split('**');
  return [
    for (final (i, part) in parts.indexed)
      if (part.isNotEmpty) (text: part, bold: i.isOdd),
  ];
}
