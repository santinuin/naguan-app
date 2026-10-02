import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/exercise.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/theme/forja_theme.dart';

import 'fake_catalog_client.dart';

/// Un ejercicio como lo manda la API.
Map<String, dynamic> exerciseJson({
  String slug = 'plancha-lateral',
  String name = 'Plancha lateral',
}) => {
  'slug': slug,
  'name': name,
  'unilateral': true,
  'description': 'Apoyá el antebrazo.\n\n- **Cadera** arriba.',
  'videos': [
    {'side': 'left', 'url': 'https://youtube.com/shorts/aaaaaaaaaaa'},
    {'side': 'right', 'url': 'https://youtube.com/shorts/bbbbbbbbbbb'},
  ],
  'muscles': [
    {'slug': 'abdominales-oblicuos', 'name': 'Abdominales oblicuos'},
  ],
  'joints': [
    {'slug': 'hombros', 'name': 'Hombros'},
  ],
  'easier': [
    {'slug': 'plancha-lateral-rodillas', 'name': 'Plancha lateral rodillas'},
  ],
  'harder': [],
};

/// Reproductor falso: muestra la URL en vez de un WebView.
Widget fakeVideo(String url) => Text('VIDEO $url');

void main() {
  test('Exercise.fromJson lee videos por lado, etiquetas y progresiones', () {
    final ex = Exercise.fromJson(exerciseJson());

    expect(ex.unilateral, isTrue);
    expect(ex.videos.map((v) => v.side), [Side.left, Side.right]);
    expect(ex.muscles.single.name, 'Abdominales oblicuos');
    expect(ex.easier.single.slug, 'plancha-lateral-rodillas');
    expect(ex.harder, isEmpty);
  });

  testWidgets('muestra el ejercicio y cambia de lado el video', (tester) async {
    final client = FakeCatalogClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExerciseScreen(
          catalog: client,
          slug: 'plancha-lateral',
          videoBuilder: fakeVideo,
        ),
      ),
    );
    client.exerciseCalls.single.complete(Exercise.fromJson(exerciseJson()));
    await tester.pump();

    expect(client.requestedSlugs, ['plancha-lateral']);
    expect(find.text('PLANCHA LATERAL'), findsOneWidget);
    expect(find.text('EJERCICIO · DE A UN LADO'), findsOneWidget);
    expect(find.text('ABDOMINALES OBLICUOS'), findsOneWidget);
    expect(find.text('MÁS FÁCIL'), findsOneWidget);
    expect(find.text('MÁS DIFÍCIL'), findsNothing);

    // Arranca con el izquierdo; tocar DERECHA cambia el video.
    expect(find.text('VIDEO https://youtube.com/shorts/aaaaaaaaaaa'), findsOne);
    await tester.tap(find.text('DERECHA'));
    await tester.pump();
    expect(find.text('VIDEO https://youtube.com/shorts/bbbbbbbbbbb'), findsOne);
  });

  testWidgets('una progresión abre ese ejercicio', (tester) async {
    final client = FakeCatalogClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExerciseScreen(
          catalog: client,
          slug: 'plancha-lateral',
          videoBuilder: fakeVideo,
        ),
      ),
    );
    client.exerciseCalls.single.complete(Exercise.fromJson(exerciseJson()));
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Plancha lateral rodillas'), 200);
    await tester.tap(find.text('Plancha lateral rodillas'));
    await tester.pump();

    expect(client.requestedSlugs.last, 'plancha-lateral-rodillas');
    client.exerciseCalls.last.complete(
      Exercise.fromJson(
        exerciseJson(
          slug: 'plancha-lateral-rodillas',
          name: 'Plancha lateral rodillas',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PLANCHA LATERAL RODILLAS'), findsOneWidget);
  });
}
