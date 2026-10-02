import 'package:naguan_app/catalog/session.dart';

/// El detalle de un ejercicio: lo que devuelve `GET /exercises/{slug}`.
class Exercise {
  const Exercise({
    required this.slug,
    required this.name,
    required this.unilateral,
    required this.videos,
    required this.muscles,
    required this.joints,
    required this.easier,
    required this.harder,
    this.description,
  });

  final String slug;
  final String name;

  /// Se hace de a un lado por vez.
  final bool unilateral;

  /// En Markdown (párrafos, listas y negrita): ver MarkdownText.
  final String? description;

  /// Uno sin lado, o uno por lado (izquierdo primero).
  final List<ExerciseVideo> videos;
  final List<Tag> muscles;
  final List<Tag> joints;

  /// Vecinos en el grafo de progresiones: de dónde se llega a este
  /// ejercicio y hacia dónde se progresa.
  final List<ExerciseRef> easier;
  final List<ExerciseRef> harder;

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'slug': String slug,
        'name': String name,
        'unilateral': bool unilateral,
        'description': String? description,
        'videos': List videos,
        'muscles': List muscles,
        'joints': List joints,
        'easier': List easier,
        'harder': List harder,
      } =>
        Exercise(
          slug: slug,
          name: name,
          unilateral: unilateral,
          description: description,
          videos: [
            for (final v in videos)
              ExerciseVideo.fromJson(v as Map<String, dynamic>),
          ],
          muscles: [for (final m in muscles) Tag.fromJson(m)],
          joints: [for (final j in joints) Tag.fromJson(j)],
          easier: [for (final e in easier) ExerciseRef.fromJson(e)],
          harder: [for (final h in harder) ExerciseRef.fromJson(h)],
        ),
      _ => throw FormatException('Ejercicio con formato inválido: $json'),
    };
  }
}

class ExerciseVideo {
  const ExerciseVideo({required this.url, this.side});

  /// Hoy, un link de YouTube. La API no lo interpreta; la app sí (ver
  /// YoutubeVideo).
  final String url;

  /// Null: vale para los dos lados.
  final Side? side;

  factory ExerciseVideo.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'url': String url} => ExerciseVideo(
        url: url,
        side: switch (json['side']) {
          String side => Side.values.byName(side),
          _ => null,
        },
      ),
      _ => throw FormatException('Video con formato inválido: $json'),
    };
  }
}

/// Un músculo o una articulación.
class Tag {
  const Tag({required this.slug, required this.name});

  final String slug;
  final String name;

  // Recibe `Object?` (y no un Map) para poder llamarlo directo sobre los
  // elementos de una List sin tipo: el pattern de abajo verifica la forma.
  factory Tag.fromJson(Object? json) {
    return switch (json) {
      {'slug': String slug, 'name': String name} => Tag(slug: slug, name: name),
      _ => throw FormatException('Etiqueta con formato inválido: $json'),
    };
  }
}
