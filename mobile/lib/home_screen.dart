import 'package:flutter/material.dart';
import 'package:naguan_app/health_client.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.client});

  final HealthClient client;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _message = 'Sin consultar';
  bool _loading = false;

  Future<void> _check() async {
    setState(() => _loading = true);

    String message;
    try {
      final status = await widget.client.fetchStatus();
      message = 'Backend: $status';
    } catch (e) {
      message = 'Error: $e';
    }

    if (!mounted) return;
    setState(() {
      _message = message;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('NAGUAN')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('BACKEND · /HEALTH', style: textTheme.labelSmall),
            const SizedBox(height: ForjaSpace.s2),
            Text(_message),
            const SizedBox(height: ForjaSpace.s6),
            FilledButton(
              onPressed: _loading ? null : _check,
              child: Text(_loading ? 'CONSULTANDO' : 'PROBAR'),
            ),
          ],
        ),
      ),
    );
  }
}
