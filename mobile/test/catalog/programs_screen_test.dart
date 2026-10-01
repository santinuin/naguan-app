import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/program_screen.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/catalog/programs_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

import 'fake_catalog_client.dart';

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

    client.programsCalls.single.complete(const [
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

    client.programsCalls.single.completeError(
      const CatalogException('sin red'),
    );
    await tester.pump();

    expect(find.text('SIN SEÑAL'), findsOneWidget);

    await tester.tap(find.text('REINTENTAR'));
    await tester.pump();

    // Un request nuevo, y la pantalla vuelve a "cargando".
    expect(client.programsCalls, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    client.programsCalls.last.complete(const []);
    await tester.pump();

    expect(find.text('SENDAS'), findsOneWidget);
  });

  testWidgets('tocar una senda abre su pantalla y "atrás" vuelve', (
    tester,
  ) async {
    final client = FakeCatalogClient();
    await pumpScreen(tester, client);
    client.programsCalls.single.complete(const [
      ProgramSummary(slug: 'ring-master', name: 'Ring Master', sessionCount: 2),
    ]);
    await tester.pump();

    await tester.tap(find.text('RING MASTER'));
    // Dos frames: en el primero, Flutter construye ProgramScreen fuera de
    // escena (offstage) para preparar la transición, y los find no lo ven;
    // en el siguiente ya está en escena. Ojo: acá NO sirve pumpAndSettle.
    // Espera a que no queden animaciones, y el CircularProgressIndicator de
    // la carga gira para siempre: el test se colgaría ("pumpAndSettle timed
    // out").
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ProgramScreen), findsOneWidget);
    expect(client.requestedSlugs, ['ring-master']);

    client.programCalls.single.complete(
      const Program(
        slug: 'ring-master',
        name: 'Ring Master',
        sessions: [
          SessionSummary(position: 1, id: 10, title: 'Fundamentos'),
          SessionSummary(position: 2, id: 11, title: 'Fuerza'),
        ],
      ),
    );
    // Con la carga terminada ya no hay animaciones infinitas: pumpAndSettle
    // bombea frames hasta que termina la transición entre pantallas.
    await tester.pumpAndSettle();

    expect(find.text('FRAGUA 01'), findsOneWidget);
    expect(find.text('Fuerza'), findsOneWidget);

    // El botón "atrás" del AppBar hace pop: vuelve a la lista.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('SENDAS'), findsOneWidget);
    expect(find.byType(ProgramScreen), findsNothing);
  });
}
