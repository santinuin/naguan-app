import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/common/markdown_text.dart';

void main() {
  group('parseMarkdown', () {
    test('párrafos, listas con guion y numeradas', () {
      final blocks = parseMarkdown('''
Apóyate en las manos
y empuja.

- Codos cerca.
- Cadera firme.

1. Bajá.
2. Subí.''');

      expect(blocks, hasLength(5));
      // El salto de línea simple no corta el párrafo: se une con un espacio.
      expect(blocks[0], isA<MdParagraph>());
      expect(blocks[0].spans.single.text, 'Apóyate en las manos y empuja.');
      expect((blocks[1] as MdListItem).marker, '•');
      expect(blocks[1].spans.single.text, 'Codos cerca.');
      expect((blocks[3] as MdListItem).marker, '1.');
      expect(blocks[4].spans.single.text, 'Subí.');
    });

    test('un texto sin Markdown es un solo párrafo', () {
      final blocks = parseMarkdown('Flexión a 90º #sin título');

      expect(blocks.single, isA<MdParagraph>());
      expect(blocks.single.spans.single.text, 'Flexión a 90º #sin título');
    });
  });

  group('parseInline', () {
    test('separa la negrita', () {
      expect(parseInline('**Ten en cuenta:** tensá el core'), [
        (text: 'Ten en cuenta:', bold: true),
        (text: ' tensá el core', bold: false),
      ]);
    });

    test('un ** sin cerrar no pierde texto', () {
      final spans = parseInline('a **b');

      expect(spans.map((s) => s.text).join(), 'a b');
      expect(spans.last.bold, isTrue);
    });
  });

  testWidgets('dibuja párrafos y viñetas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownText('Texto.\n\n- Uno\n- Dos')),
      ),
    );

    expect(find.text('Texto.'), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    expect(find.text('Dos'), findsOneWidget);
  });
}
