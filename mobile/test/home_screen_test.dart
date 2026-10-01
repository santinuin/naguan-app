import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/health_client.dart';
import 'package:naguan_app/home_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

/// Cliente falso: el test decide cuándo y cómo termina la consulta,
/// completando [response].
class FakeHealthClient implements HealthClient {
  final response = Completer<String>();

  @override
  final String baseUrl = 'http://fake';

  @override
  Future<String> fetchStatus() => response.future;
}

Future<void> pumpHome(WidgetTester tester, HealthClient client) {
  return tester.pumpWidget(
    MaterialApp(
      theme: forjaHierro,
      home: HomeScreen(client: client),
    ),
  );
}

FilledButton findButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton));
}

void main() {
  testWidgets('arranca sin consultar', (tester) async {
    await pumpHome(tester, FakeHealthClient());

    expect(find.text('Sin consultar'), findsOneWidget);
    expect(find.text('PROBAR'), findsOneWidget);
    expect(findButton(tester).onPressed, isNotNull);
  });

  testWidgets('deshabilita el botón mientras consulta y muestra el status', (
    tester,
  ) async {
    final client = FakeHealthClient();
    await pumpHome(tester, client);

    await tester.tap(find.text('PROBAR'));
    await tester.pump();

    expect(find.text('CONSULTANDO'), findsOneWidget);
    expect(findButton(tester).onPressed, isNull);

    client.response.complete('ok');
    await tester.pump();

    expect(find.text('Backend: ok'), findsOneWidget);
    expect(find.text('PROBAR'), findsOneWidget);
    expect(findButton(tester).onPressed, isNotNull);
  });

  testWidgets('muestra el error si la consulta falla', (tester) async {
    final client = FakeHealthClient();
    await pumpHome(tester, client);

    await tester.tap(find.text('PROBAR'));
    await tester.pump();
    client.response.completeError(Exception('sin red'));
    await tester.pump();

    expect(find.text('Error: Exception: sin red'), findsOneWidget);
    expect(find.text('PROBAR'), findsOneWidget);
  });
}
