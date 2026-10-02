import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/program_screen.dart';
import 'package:naguan_app/catalog/programs_screen.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/training/history/history_screen.dart';
import 'package:naguan_app/training/training_models.dart';

import 'fake_catalog_client.dart';

const someStats = Stats(brasa: Brasa(days: 4, atRisk: false), totalWorkouts: 9);

ProgramProgress progress(
  String slug,
  String name, {
  int completed = 0,
  int total = 10,
  SessionRef? next,
  Set<int> done = const {},
}) => ProgramProgress(
  slug: slug,
  name: name,
  completed: completed,
  total: total,
  next: next,
  completedSessionIds: done,
);

Future<void> pumpScreen(
  WidgetTester tester,
  FakeCatalogClient catalog,
  FakeTrainingClient training,
) {
  return tester.pumpWidget(
    MaterialApp(
      theme: forjaHierro,
      home: ProgramsScreen(
        catalog: catalog,
        training: fakeServices(client: training),
        onSignOut: () {},
      ),
    ),
  );
}

/// Completa la carga de la pantalla de inicio (progreso + stats).
Future<void> loadHome(
  WidgetTester tester,
  FakeTrainingClient training,
  List<ProgramProgress> programs, {
  Stats stats = someStats,
}) async {
  // El flush de la cola (vacía) y la lectura del disco son asincrónicos:
  // un pump deja que corran antes de que salgan los requests.
  await tester.pump();
  training.progressCalls.last.complete(programs);
  training.statsCalls.last.complete(stats);
  await tester.pump();
}

void main() {
  testWidgets('pide progreso y stats en paralelo, y muestra un indicador', (
    tester,
  ) async {
    final training = FakeTrainingClient();
    await pumpScreen(tester, FakeCatalogClient(), training);
    await tester.pump(); // el flush de la cola (vacía) va primero

    // Los dos requests salieron a la vez (sin esperar uno al otro).
    expect(training.progressCalls, hasLength(1));
    expect(training.statsCalls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('muestra la brasa y las sendas con su progreso', (tester) async {
    final training = FakeTrainingClient();
    await pumpScreen(tester, FakeCatalogClient(), training);

    await loadHome(tester, training, [
      progress('unbreakable', 'Unbreakable', completed: 3, total: 50),
    ]);

    expect(find.text('SENDAS'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // días de brasa
    expect(find.text('UNBREAKABLE'), findsOneWidget);
    expect(find.text('3 / 50 FRAGUAS'), findsOneWidget);
  });

  testWidgets('avisa cuando la brasa está en riesgo', (tester) async {
    final training = FakeTrainingClient();
    await pumpScreen(tester, FakeCatalogClient(), training);

    await loadHome(
      tester,
      training,
      [],
      stats: const Stats(brasa: Brasa(days: 6, atRisk: true), totalWorkouts: 6),
    );

    expect(find.text('No la dejes apagar.'), findsOneWidget);
  });

  testWidgets('abre el historial y al volver recarga el inicio', (
    tester,
  ) async {
    final training = FakeTrainingClient();
    await pumpScreen(tester, FakeCatalogClient(), training);
    await loadHome(tester, training, []);

    await tester.tap(find.text('HISTORIAL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(training.workoutsCalls, hasLength(1));

    training.workoutsCalls.single.complete(const []);
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Volvió: el inicio pide de nuevo el progreso.
    expect(training.progressCalls, hasLength(2));
  });

  testWidgets('ante un error permite reintentar', (tester) async {
    final training = FakeTrainingClient();
    await pumpScreen(tester, FakeCatalogClient(), training);

    await tester.pump();
    training.progressCalls.single.completeError(const ApiException('sin red'));
    training.statsCalls.single.complete(someStats);
    await tester.pump();
    expect(find.text('SIN SEÑAL'), findsOneWidget);

    await tester.tap(find.text('REINTENTAR'));
    await tester.pump();
    await tester.pump();

    expect(training.progressCalls, hasLength(2));
    await loadHome(tester, training, []);
    expect(find.text('SENDAS'), findsOneWidget);
  });

  testWidgets('abre la senda con checks y al volver recarga el inicio', (
    tester,
  ) async {
    // El árbol de semántica (lo que leen los lectores de pantalla) está
    // apagado por defecto en los tests: lo encendemos para buscar el check
    // por su etiqueta, y lo liberamos al final con dispose.
    final semantics = tester.ensureSemantics();
    final catalog = FakeCatalogClient();
    final training = FakeTrainingClient();
    await pumpScreen(tester, catalog, training);
    await loadHome(tester, training, [
      progress('ring-master', 'Ring Master', total: 2),
    ]);

    await tester.tap(find.text('RING MASTER'));
    // Dos frames: en el primero, Flutter construye ProgramScreen fuera de
    // escena (offstage) para preparar la transición, y los find no lo ven.
    // Ojo: acá NO sirve pumpAndSettle: espera a que no queden animaciones,
    // y el indicador de carga gira para siempre.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ProgramScreen), findsOneWidget);
    expect(catalog.requestedSlugs, ['ring-master']);

    catalog.programCalls.single.complete(
      const Program(
        slug: 'ring-master',
        name: 'Ring Master',
        sessions: [
          SessionSummary(position: 1, id: 10, title: 'Fundamentos'),
          SessionSummary(position: 2, id: 11, title: 'Fuerza'),
        ],
      ),
    );
    training.programProgressCalls.single.complete(
      progress(
        'ring-master',
        'Ring Master',
        completed: 1,
        total: 2,
        next: const SessionRef(position: 2, id: 11, title: 'Fuerza'),
        done: {10},
      ),
    );
    // Con la carga terminada ya no hay animaciones infinitas: pumpAndSettle
    // espera a que termine la transición.
    await tester.pumpAndSettle();

    // El InkWell de la fila fusiona la semántica de sus hijos en un nodo
    // ("Templada, FRAGUA 01, Fundamentos"): un lector de pantalla anuncia la
    // fila entera. Por eso se busca con una expresión regular y no con la
    // etiqueta exacta. "Sin templar" no matchea: la regex distingue
    // mayúsculas.
    expect(find.bySemanticsLabel(RegExp('Templada')), findsOneWidget);
    expect(find.text('SIGUE'), findsOneWidget);

    // Volver: la pantalla de inicio se recarga (la key de LoadView cambió).
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(training.progressCalls, hasLength(2));
    semantics.dispose();
  });
}
