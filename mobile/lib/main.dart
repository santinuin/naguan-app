import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/programs_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

/// URL base de la API (versión 1). En el emulador Android, la PC host es
/// 10.0.2.2. Los clientes agregan la ruta (`/programs`...) sobre esta base.
const apiBaseUrl = 'http://10.0.2.2:8080/v1';

void main() {
  final catalogClient = CatalogClient(baseUrl: apiBaseUrl);
  runApp(NaguanApp(catalogClient: catalogClient));
}

class NaguanApp extends StatelessWidget {
  const NaguanApp({super.key, required this.catalogClient});

  final CatalogClient catalogClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORJA DEL NAGUAN',
      theme: forjaHueso,
      darkTheme: forjaHierro,
      // Hierro es el tema principal. Con ThemeMode.system seguiría al
      // sistema operativo.
      themeMode: ThemeMode.dark,
      home: ProgramsScreen(client: catalogClient),
    );
  }
}
