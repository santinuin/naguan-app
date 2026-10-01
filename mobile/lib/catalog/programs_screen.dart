import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Lista de Sendas (programas) del catálogo.
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key, required this.client});

  final CatalogClient client;

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  /// El Future se crea UNA vez, en initState, y se guarda en el State.
  ///
  /// Si se creara dentro de build(), cada rebuild (rotar la pantalla, un
  /// cambio de tema, cualquier setState) dispararía un request nuevo y el
  /// FutureBuilder volvería a "cargando". build() tiene que poder llamarse
  /// muchas veces sin efectos secundarios.
  late Future<List<ProgramSummary>> _programs;

  @override
  void initState() {
    super.initState();
    _programs = widget.client.fetchPrograms();
  }

  void _retry() {
    // Un Future nuevo dentro de setState: el FutureBuilder lo detecta, vuelve
    // a "cargando" y espera al nuevo.
    setState(() {
      _programs = widget.client.fetchPrograms();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // SafeArea deja margen para la barra de estado y los bordes de la
      // pantalla (notch, gestos), que el Scaffold sin AppBar no reserva.
      body: SafeArea(
        child: FutureBuilder<List<ProgramSummary>>(
          future: _programs,
          // builder se llama de nuevo cada vez que el Future cambia de
          // estado; snapshot dice en cuál está.
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorView(onRetry: _retry);
            }
            return _ProgramList(programs: snapshot.requireData);
          },
        ),
      ),
    );
  }
}

class _ProgramList extends StatelessWidget {
  const _ProgramList({required this.programs});

  final List<ProgramSummary> programs;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // ListView.separated (como ListView.builder, más un separador entre
    // elementos) construye solo los elementos visibles, a medida que se
    // scrollea, como un RecyclerView. Con 5 programas no importa, pero es el
    // patrón para cualquier lista.
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
        return _ProgramCard(program: programs[index - 1]);
      },
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program});

  final ProgramSummary program;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sessions = program.sessionCount;

    // Card toma borde, radio y color del cardTheme de Forja: acá no se
    // repite ningún estilo.
    return Card(
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
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('SIN SEÑAL', style: textTheme.titleLarge),
            const SizedBox(height: ForjaSpace.s2),
            const Text(
              'No se pudo traer las sendas. Revisá la conexión.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: ForjaSpace.s6),
            FilledButton(onPressed: onRetry, child: const Text('REINTENTAR')),
          ],
        ),
      ),
    );
  }
}
