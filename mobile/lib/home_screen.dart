import 'package:flutter/material.dart';
import 'package:naguan_app/health_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _client = HealthClient(baseUrl: 'http://10.0.2.2:8080');

  String _message = 'Sin consultar';
  bool _loading = false;

  Future<void> _check() async {
    setState(() => _loading = true);

    String message;
    try {
      final status = await _client.fetchStatus();
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
    return Scaffold(
      appBar: AppBar(title: const Text('NAGUAN')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_message),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _check,
              child: Text(_loading ? 'Consultando...' : 'Probar'),
            ),
          ],
        ),
      ),
    );
  }
}