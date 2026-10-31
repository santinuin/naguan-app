import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/theme/forja_note.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

void main() {
  testWidgets(
    'la nota lleva la etiqueta NOTA y el texto apagado, sin negrita',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: forjaHierro,
          home: const Scaffold(body: ForjaNote('2 s de subida y 2 de bajada.')),
        ),
      );

      expect(find.text('NOTA'), findsOneWidget);
      final text = tester.widget<Text>(
        find.text('2 s de subida y 2 de bajada.'),
      );
      expect(text.style?.color, ForjaPalette.hierro.inkMuted);
      expect(text.style?.fontWeight, isNot(FontWeight.w700));
      expect(text.style?.fontStyle, isNot(FontStyle.italic));
    },
  );
}
