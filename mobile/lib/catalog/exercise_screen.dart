import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/exercise.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/catalog/youtube_video.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/common/markdown_text.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/forja_headline.dart';

/// Construye el reproductor para una URL. Un `typedef` le pone nombre a un
/// tipo de función, como una interfaz funcional de Java
/// (`Function<String, Widget>`), pero sin declarar una interfaz.
typedef VideoBuilder = Widget Function(String url);

Widget _youtube(String url) => YoutubeVideo(key: ValueKey(url), url: url);

/// Un ejercicio: video, cómo se hace, qué trabaja y sus progresiones.
class ExerciseScreen extends StatelessWidget {
  const ExerciseScreen({
    super.key,
    required this.catalog,
    required this.slug,
    this.videoBuilder = _youtube,
  });

  final CatalogClient catalog;
  final String slug;

  /// El reproductor. Por defecto, YouTube embebido; los tests pasan uno
  /// falso porque en un widget test no hay WebView. Un valor por defecto
  /// tiene que ser constante: por eso `_youtube` es una función de nivel
  /// superior (su tear-off es const) y no una lambda.
  final VideoBuilder videoBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: LoadView<Exercise>(
        load: () => catalog.fetchExercise(slug),
        builder: (context, exercise) => _ExerciseDetail(
          exercise: exercise,
          videoBuilder: videoBuilder,
          // Una progresión abre otro ExerciseScreen encima: "atrás" vuelve
          // al anterior, como al recorrer links.
          onOpen: (ref) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ExerciseScreen(
                catalog: catalog,
                slug: ref.slug,
                videoBuilder: videoBuilder,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseDetail extends StatelessWidget {
  const _ExerciseDetail({
    required this.exercise,
    required this.videoBuilder,
    required this.onOpen,
  });

  final Exercise exercise;
  final VideoBuilder videoBuilder;
  final ValueChanged<ExerciseRef> onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        0,
        ForjaSpace.s4,
        ForjaSpace.s8,
      ),
      children: [
        Text(
          exercise.unilateral ? 'EJERCICIO · DE A UN LADO' : 'EJERCICIO',
          style: textTheme.labelSmall,
        ),
        const SizedBox(height: ForjaSpace.s2),
        ForjaHeadline(
          exercise.name.toUpperCase(),
          style: textTheme.displayMedium,
        ),
        if (exercise.videos.isNotEmpty) ...[
          const SizedBox(height: ForjaSpace.s6),
          _Videos(videos: exercise.videos, videoBuilder: videoBuilder),
        ],
        if (exercise.description case final description?) ...[
          const SizedBox(height: ForjaSpace.s6),
          MarkdownText(description),
        ],
        if (exercise.muscles.isNotEmpty)
          _Section(
            title: 'MÚSCULOS',
            child: _Tags(tags: exercise.muscles),
          ),
        if (exercise.joints.isNotEmpty)
          _Section(
            title: 'ARTICULACIONES',
            child: _Tags(tags: exercise.joints),
          ),
        if (exercise.easier.isNotEmpty)
          _Section(
            title: 'MÁS FÁCIL',
            child: _Progressions(refs: exercise.easier, onOpen: onOpen),
          ),
        if (exercise.harder.isNotEmpty)
          _Section(
            title: 'MÁS DIFÍCIL',
            child: _Progressions(refs: exercise.harder, onOpen: onOpen),
          ),
      ],
    );
  }
}

/// El video, con un selector de lado si hay uno por lado.
///
/// Es StatefulWidget porque el lado elegido es estado de la pantalla: no
/// viene del servidor ni de un padre, cambia con un toque y a nadie más le
/// importa. Es el caso de manual para setState.
class _Videos extends StatefulWidget {
  const _Videos({required this.videos, required this.videoBuilder});

  final List<ExerciseVideo> videos;
  final VideoBuilder videoBuilder;

  @override
  State<_Videos> createState() => _VideosState();
}

class _VideosState extends State<_Videos> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    final videos = widget.videos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (videos.length > 1) ...[
          Row(
            children: [
              for (final (i, video) in videos.indexed) ...[
                if (i > 0) const SizedBox(width: ForjaSpace.s2),
                Expanded(
                  // El elegido, relleno; el otro, solo con borde.
                  child: i == _selected
                      ? FilledButton(
                          onPressed: () {},
                          child: Text(video.side?.label ?? 'VIDEO ${i + 1}'),
                        )
                      : OutlinedButton(
                          onPressed: () => setState(() => _selected = i),
                          child: Text(video.side?.label ?? 'VIDEO ${i + 1}'),
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: ForjaSpace.s4),
        ],
        // Cambiar de lado cambia la URL, y con ella la key del reproductor
        // (ver _youtube): Flutter descarta el viejo y crea uno nuevo, en vez
        // de reutilizar el State con el video anterior.
        widget.videoBuilder(videos[_selected].url),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: ForjaSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: ForjaSpace.s2),
          child,
        ],
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  const _Tags({required this.tags});

  final List<Tag> tags;

  @override
  Widget build(BuildContext context) {
    // Wrap es una Row que salta de línea cuando no entra: los chips se
    // acomodan solos según el ancho de la pantalla.
    return Wrap(
      spacing: ForjaSpace.s2,
      runSpacing: ForjaSpace.s2,
      children: [for (final tag in tags) ForjaPill(tag.name)],
    );
  }
}

class _Progressions extends StatelessWidget {
  const _Progressions({required this.refs, required this.onOpen});

  final List<ExerciseRef> refs;
  final ValueChanged<ExerciseRef> onOpen;

  @override
  Widget build(BuildContext context) {
    final forja = context.forja;
    return Column(
      children: [
        for (final ref in refs)
          InkWell(
            onTap: () => onOpen(ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s2),
              child: Row(
                children: [
                  Expanded(child: Text(ref.name, style: forja.bodyStrong)),
                  Icon(Icons.chevron_right, color: forja.palette.inkMuted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
