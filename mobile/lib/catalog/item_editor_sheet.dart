import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/exercise.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/forja_headline.dart';
import 'package:naguan_app/theme/forja_sheet.dart';
import 'package:naguan_app/theme/one_line_text.dart';

/// Lo que elige el usuario en el editor: el ejercicio (el mismo u otro) y
/// el objetivo (reps o segundos, según cómo se mida el ítem).
typedef ItemEdit = ({ExerciseRef exercise, int value});

/// Abre el editor de un ejercicio de la Fragua como hoja inferior. Devuelve
/// lo elegido, o null si se cerró sin confirmar (deslizando hacia abajo o
/// tocando afuera).
///
/// Una hoja modal es una ruta más en el Navigator, como una pantalla:
/// showModalBottomSheet devuelve un Future que se completa con el valor que
/// se pase a `Navigator.pop(context, valor)`. Es la misma forma de "pedir
/// algo y esperar la respuesta" que un showDialog.
Future<ItemEdit?> showItemEditor(
  BuildContext context, {
  required CatalogClient catalog,
  required Item item,
}) {
  return showModalBottomSheet<ItemEdit>(
    context: context,
    // Sin esto la hoja se limita a media pantalla; con las progresiones
    // puede necesitar más.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ForjaSheet(
      child: ItemEditorSheet(catalog: catalog, item: item),
    ),
  );
}

class ItemEditorSheet extends StatefulWidget {
  const ItemEditorSheet({super.key, required this.catalog, required this.item});

  final CatalogClient catalog;

  /// El ítem tal como está ahora en la Fragua (quizá ya ajustado).
  final Item item;

  @override
  State<ItemEditorSheet> createState() => _ItemEditorSheetState();
}

class _ItemEditorSheetState extends State<ItemEditorSheet> {
  // `late` con inicializador: se calcula la primera vez que se lee, cuando
  // `widget` ya está disponible (en la declaración de un campo todavía no lo
  // está). Evita escribir un initState solo para esto.
  late ExerciseRef _exercise = widget.item.exercise!;
  late int _value = widget.item.reps ?? widget.item.durationS!;

  bool get _isReps => widget.item.reps != null;

  /// Las reps se ajustan de a una; los segundos, de a cinco.
  int get _step => _isReps ? 1 : 5;

  void _adjust(int delta) {
    // clamp acota el valor: nunca menos de un paso (0 reps no es un
    // ejercicio) ni más de lo razonable.
    setState(() => _value = (_value + delta).clamp(_step, 999));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final forja = context.forja;
    final original = widget.item.exercise!;
    final stat = forja.stat.copyWith(fontSize: 56, height: 1);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        0,
        ForjaSpace.s4,
        ForjaSpace.s4,
      ),
      child: Column(
        // La hoja mide lo que su contenido, no la pantalla entera.
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ForjaHeadline(
            _exercise.name.toUpperCase(),
            style: textTheme.titleLarge,
          ),
          if (_exercise.slug != original.slug)
            TextButton(
              style: forjaInlineButton,
              onPressed: () => setState(() => _exercise = original),
              child: OneLineText('VOLVER A ${original.name.toUpperCase()}'),
            ),
          TextButton(
            style: forjaInlineButton,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExerciseScreen(
                  catalog: widget.catalog,
                  slug: _exercise.slug,
                ),
              ),
            ),
            child: const OneLineText('CÓMO SE HACE'),
          ),
          const SizedBox(height: ForjaSpace.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                onPressed: _value > _step ? () => _adjust(-_step) : null,
                icon: const Icon(Icons.remove),
                tooltip: _isReps ? 'Una menos' : '5 segundos menos',
              ),
              const SizedBox(width: ForjaSpace.s4),
              Text('$_value', style: stat),
              const SizedBox(width: ForjaSpace.s4),
              IconButton.outlined(
                onPressed: () => _adjust(_step),
                icon: const Icon(Icons.add),
                tooltip: _isReps ? 'Una más' : '5 segundos más',
              ),
            ],
          ),
          const SizedBox(height: ForjaSpace.s2),
          Center(
            child: Text(
              _isReps ? 'REPS' : 'SEGUNDOS',
              style: textTheme.labelSmall,
            ),
          ),
          const SizedBox(height: ForjaSpace.s6),
          // Las progresiones del ejercicio ELEGIDO: al tocar una, la lista
          // se recarga con las de ella, así se puede bajar o subir más de
          // un escalón. La key nueva hace que LoadView vuelva a cargar (ver
          // "Recargar un widget: cambiar su key" en los docs).
          //
          // AnimatedSize anima los cambios de alto (la lista que se acorta,
          // el indicador mientras carga): la hoja crece o se achica suave en
          // vez de saltar.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: LoadView<Exercise>(
              key: ValueKey(_exercise.slug),
              load: () => widget.catalog.fetchExercise(_exercise.slug),
              builder: (context, exercise) => _Progressions(
                exercise: exercise,
                onPick: (ref) => setState(() => _exercise = ref),
              ),
            ),
          ),
          const SizedBox(height: ForjaSpace.s6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pop<ItemEdit>((exercise: _exercise, value: _value)),
              child: const OneLineText('LISTO'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Progressions extends StatelessWidget {
  const _Progressions({required this.exercise, required this.onPick});

  final Exercise exercise;
  final ValueChanged<ExerciseRef> onPick;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (exercise.easier.isEmpty && exercise.harder.isEmpty) {
      return Text(
        'Este ejercicio no tiene progresiones cargadas.',
        style: textTheme.bodyLarge?.copyWith(
          color: context.forja.palette.inkMuted,
        ),
      );
    }

    // Una función local que arma cada sección: evita repetir el mismo
    // bloque para "más fácil" y "más difícil".
    List<Widget> section(String title, List<ExerciseRef> refs) => [
      Text(title, style: textTheme.labelSmall),
      for (final ref in refs)
        InkWell(
          onTap: () => onPick(ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s2),
            child: Row(
              children: [
                Expanded(
                  child: Text(ref.name, style: context.forja.bodyStrong),
                ),
                Icon(
                  Icons.swap_horiz,
                  size: 20,
                  color: context.forja.palette.inkMuted,
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: ForjaSpace.s4),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (exercise.easier.isNotEmpty)
          ...section('MÁS FÁCIL', exercise.easier),
        if (exercise.harder.isNotEmpty)
          ...section('MÁS DIFÍCIL', exercise.harder),
      ],
    );
  }
}
