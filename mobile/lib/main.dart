import 'package:flutter/material.dart';
import 'package:naguan_app/health_client.dart';
import 'package:naguan_app/home_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

void main() {
  // En el emulador Android, la PC host es 10.0.2.2.
  final healthClient = HealthClient(baseUrl: 'http://10.0.2.2:8080');
  runApp(NaguanApp(healthClient: healthClient));
}

class NaguanApp extends StatelessWidget {
  const NaguanApp({super.key, required this.healthClient});

  final HealthClient healthClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORJA DEL NAGUAN',
      theme: forjaHueso,
      darkTheme: forjaHierro,
      // Hierro es el tema principal. Con ThemeMode.system seguiría al
      // sistema operativo.
      themeMode: ThemeMode.dark,
      home: HomeScreen(client: healthClient),
    );
  }
}
