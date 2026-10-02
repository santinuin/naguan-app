import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/theme/one_line_text.dart';

void main() {
  Future<void> pumpIn(WidgetTester tester, double width) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: width,
            child: const OneLineText(
              'IZQUIERDA',
              // FlutterTest: cada letra mide lo mismo que la fuente (20 px):
              // IZQUIERDA ocupa 180 px.
              style: TextStyle(fontSize: 20, fontFamily: 'FlutterTest'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('si no entra, se achica en una línea en vez de cortarse', (
    tester,
  ) async {
    await pumpIn(tester, 90);

    // getRect da el rectángulo en pantalla, con la escala del FittedBox
    // aplicada: el texto (180 px en una línea) quedó a la mitad.
    final text = tester.getRect(find.byType(Text));
    expect(text.width, closeTo(90, 0.5));
    expect(text.height, closeTo(10, 0.5)); // una sola línea, a escala 0.5
  });

  testWidgets('si entra, queda igual', (tester) async {
    await pumpIn(tester, 300);
    expect(tester.getRect(find.byType(Text)).size, const Size(180, 20));
  });
}
