import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/session_screen.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Una Senda (programa) con su lista de Fraguas (sesiones).
///
/// Recibe [name] además de [slug]: la pantalla anterior ya lo conoce, así
/// que el título se muestra al instante mientras se cargan las sesiones.
class ProgramScreen extends StatelessWidget {
  const ProgramScreen({
    super.key,
    required this.client,
    required this.slug,
    required this.name,
  });

  final CatalogClient client;
  final String slug;
  final String name;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // Un AppBar vacío: Flutter agrega solo el botón "atrás" porque hay
      // una ruta debajo en la pila del Navigator.
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
            child: Text(name.toUpperCase(), style: textTheme.displayMedium),
          ),
          // Expanded le da a la lista todo el alto que sobra. Sin él, un
          // ListView dentro de un Column no sabe cuánto medir y falla
          // ("unbounded height").
          Expanded(
            child: LoadView<Program>(
              // Una closure: hace falta pasar el slug, así que no alcanza
              // con el tear-off.
              load: () => client.fetchProgram(slug),
              builder: (context, program) =>
                  _SessionList(client: client, program: program),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.client, required this.program});

  final CatalogClient client;
  final Program program;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: ForjaSpace.s8),
      itemCount: program.sessions.length,
      // Divider toma color y grosor del dividerTheme (`line`, 1px): las
      // "reglas finas" del sistema de diseño.
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = program.sessions[index];
        final label = 'FRAGUA ${session.position.toString().padLeft(2, '0')}';
        return _SessionRow(
          label: label,
          title: session.title,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SessionScreen(
                client: client,
                id: session.id,
                label: '${program.name.toUpperCase()} · $label',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.label,
    required this.title,
    required this.onTap,
  });

  final String label;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ForjaSpace.s4,
          vertical: ForjaSpace.s4,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: textTheme.labelSmall),
                  const SizedBox(height: ForjaSpace.s1),
                  Text(title, style: textTheme.headlineSmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
