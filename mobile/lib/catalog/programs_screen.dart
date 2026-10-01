import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program_screen.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Lista de Sendas (programas) del catálogo. Es la pantalla de inicio.
///
/// Ahora es un StatelessWidget: el estado de la carga (el Future en curso)
/// vive dentro de LoadView.
class ProgramsScreen extends StatelessWidget {
  const ProgramsScreen({super.key, required this.client});

  final CatalogClient client;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadView<List<ProgramSummary>>(
          // Un tear-off: se pasa el método sin llamarlo (sin paréntesis),
          // como una method reference `client::fetchPrograms` en Java.
          load: client.fetchPrograms,
          builder: (context, programs) =>
              _ProgramList(client: client, programs: programs),
        ),
      ),
    );
  }
}

class _ProgramList extends StatelessWidget {
  const _ProgramList({required this.client, required this.programs});

  final CatalogClient client;
  final List<ProgramSummary> programs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // ListView.separated (como ListView.builder, más un separador entre
    // elementos) construye solo los elementos visibles, a medida que se
    // scrollea, como un RecyclerView.
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        ForjaSpace.s12,
        ForjaSpace.s4,
        ForjaSpace.s8,
      ),
      // +1: el primer elemento es el título de la pantalla, que scrollea
      // junto con la lista.
      itemCount: programs.length + 1,
      separatorBuilder: (_, index) =>
          SizedBox(height: index == 0 ? ForjaSpace.s8 : ForjaSpace.s6),
      itemBuilder: (context, index) {
        if (index == 0) {
          // La única palabra hero de la pantalla.
          return Text('SENDAS', style: textTheme.displayLarge);
        }
        final program = programs[index - 1];
        return _ProgramCard(
          program: program,
          onTap: () => Navigator.of(context).push(
            // Una ruta nueva arriba de la pila: la pantalla anterior queda
            // abajo, y el botón "atrás" la vuelve a mostrar (pop).
            MaterialPageRoute<void>(
              builder: (_) => ProgramScreen(
                client: client,
                slug: program.slug,
                name: program.name,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.onTap});

  final ProgramSummary program;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sessions = program.sessionCount;

    // Card toma borde, radio y color del cardTheme de Forja. clipBehavior
    // recorta el efecto del toque (InkWell) a las esquinas redondeadas.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ForjaSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(program.name.toUpperCase(), style: textTheme.titleLarge),
              const SizedBox(height: ForjaSpace.s2),
              ForjaPill('$sessions ${sessions == 1 ? 'fragua' : 'fraguas'}'),
              // `if` dentro de una lista de widgets (collection if): el
              // elemento solo existe si hay descripción.
              if (program.description case final description?) ...[
                const SizedBox(height: ForjaSpace.s4),
                Text(description),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
