import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/catalog/programs_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

/// Cliente falso: cada llamada a fetchPrograms devuelve el Future de un
/// Completer nuevo, que el test completa cuando quiere. Así se puede ver el
/// estado "cargando" y contar los reintentos.
class FakeCatalogClient implements CatalogClient {
  final calls = <Completer<List<ProgramSummary>>>[];

  @override
  final String baseUrl = 'http://fake';

  @override
  Future<List<ProgramSummary>> fetchPrograms() {
    final completer = Completer<List<ProgramSummary>>();
    calls.add(completer);
    return completer.future;
  }
}

Future<void> pumpScreen(WidgetTester tester, CatalogClient client) {
  return tester.pumpWidget(
    MaterialApp(
      theme: forjaHierro,
      home: ProgramsScreen(client: client),
    ),
  );
}

void main() {
  testWidgets('muestra un indicador mientras carga', (tester) async {
    await pumpScreen(tester, FakeCatalogClient());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('muestra las sendas con su cantidad de fraguas', (tester) async {
    final client = FakeCatalogClient();
    await pumpScreen(tester, client);

    client.calls.single.complete(const [
      ProgramSummary(
        slug: 'unbreakable',
        name: 'Unbreakable',
        sessionCount: 50,
      ),
      ProgramSummary(
        slug: 'solo',
        name: 'Solo',
        sessionCount: 1,
        description: 'Una prueba.',
      ),
    ]);
    await tester.pump();

    expect(find.text('SENDAS'), findsOneWidget);
    expect(find.text('UNBREAKABLE'), findsOneWidget);
    expect(find.text('50 FRAGUAS'), findsOneWidget);
    // Singular y descripción opcional.
    expect(find.text('1 FRAGUA'), findsOneWidget);
    expect(find.text('Una prueba.'), findsOneWidget);
  });

  testWidgets('ante un error permite reintentar', (tester) async {
    final client = FakeCatalogClient();
    await pumpScreen(tester, client);

    client.calls.single.completeError(const CatalogException('sin red'));
    await tester.pump();

    expect(find.text('SIN SEÑAL'), findsOneWidget);

    await tester.tap(find.text('REINTENTAR'));
    await tester.pump();

    // Un request nuevo, y la pantalla vuelve a "cargando".
    expect(client.calls, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    client.calls.last.complete(const []);
    await tester.pump();

    expect(find.text('SENDAS'), findsOneWidget);
  });
}
