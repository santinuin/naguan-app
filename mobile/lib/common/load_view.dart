import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Carga un dato asíncrono y muestra sus tres estados: cargando, error (con
/// reintento) y el dato listo, que dibuja [builder].
///
/// Es genérico en [T], igual que una clase genérica de Java: la misma lógica sirve
/// para una lista de programas, un programa o una sesión. Las pantallas que
/// lo usan quedan como StatelessWidget, porque el estado (el Future en curso)
/// vive acá adentro.
class LoadView<T> extends StatefulWidget {
  const LoadView({super.key, required this.load, required this.builder});

  /// Función que inicia la carga. Se pasa la función y no el Future, para
  /// que LoadView decida cuándo llamarla: una vez al montarse y otra en cada
  /// reintento.
  final Future<T> Function() load;

  final Widget Function(BuildContext context, T data) builder;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> {
  /// Se crea en initState, nunca en build(): ver docs/flutter-como-funciona.md.
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  void _retry() {
    setState(() {
      _future = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorView(onRetry: _retry);
        }
        return widget.builder(context, snapshot.requireData);
      },
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
              'No se pudo traer los datos. Revisá la conexión.',
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
