import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/history/dates.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';

/// Los Mojones: la mejor marca del usuario en cada ejercicio que hizo, con
/// el día en que la logró. Tocar uno abre el ejercicio.
///
/// A diferencia del historial, es una sola carga (una fila por ejercicio,
/// no crece sin límite): alcanza con LoadView y la pantalla no tiene estado.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key, required this.catalog, required this.client});

  final CatalogClient catalog;
  final TrainingClient client;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ForjaSpace.s4,
              0,
              ForjaSpace.s4,
              ForjaSpace.s6,
            ),
            child: Text('MOJONES', style: textTheme.displayMedium),
          ),
          Expanded(
            child: LoadView<List<Record>>(
              load: client.fetchRecords,
              builder: (context, records) => records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(ForjaSpace.s4),
                      child: Text(
                        'Templá una Fragua: tus mejores marcas quedan acá.',
                        style: textTheme.bodyLarge,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: ForjaSpace.s8),
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = records[index];
                        // Sin slug (una API vieja) la fila no se puede
                        // abrir: onTap null deja el InkWell desactivado.
                        final slug = record.exerciseSlug;
                        return _RecordRow(
                          record: record,
                          onTap: slug == null
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ExerciseScreen(
                                      catalog: catalog,
                                      slug: slug,
                                    ),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record, required this.onTap});

  final Record record;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final value = record.isReps
        ? formatReps(record.value)
        : formatDuration(record.value);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.exercise, style: textTheme.headlineSmall),
                  if (record.achievedOn case final day?) ...[
                    const SizedBox(height: ForjaSpace.s1),
                    Text(formatDate(day), style: textTheme.labelSmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ForjaSpace.s4),
            // La marca, que es lo que se viene a mirar: a la derecha y en
            // el estilo de título, como el valor de una tabla.
            Text(value, style: textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
