import 'package:flutter/material.dart';
import 'package:naguan_app/auth/auth_gate.dart';
import 'package:naguan_app/auth/auth_service.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/programs_screen.dart';
import 'package:naguan_app/config.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// main es async: hay que inicializar Supabase (que lee la sesión guardada en
// el teléfono) antes de mostrar la primera pantalla.
Future<void> main() async {
  // Antes de usar plugins nativos (Supabase guarda la sesión con uno)
  // tiene que existir el "binding" entre Flutter y la plataforma; runApp lo
  // crea solo, pero acá lo necesitamos antes.
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );

  // El cableado de dependencias, a mano (como el main del backend Go).
  final auth = SupabaseAuthService(Supabase.instance.client.auth);
  final catalogClient = CatalogClient(
    baseUrl: apiBaseUrl,
    // Una closure que lee el getter: el cliente la llama en cada request y
    // siempre obtiene el token vigente.
    accessToken: () => auth.accessToken,
  );

  runApp(NaguanApp(auth: auth, catalogClient: catalogClient));
}

class NaguanApp extends StatelessWidget {
  const NaguanApp({super.key, required this.auth, required this.catalogClient});

  final AuthService auth;
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
      home: AuthGate(
        auth: auth,
        signedIn: (_) =>
            ProgramsScreen(client: catalogClient, onSignOut: auth.signOut),
      ),
    );
  }
}
