import 'package:flutter/material.dart';
import 'package:naguan_app/home_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

void main() {
  runApp(const NaguanApp());
}

class NaguanApp extends StatelessWidget {
  const NaguanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORJA DEL NAGUAN',
      theme: forjaHueso,
      darkTheme: forjaHierro,
      // Hierro es el tema principal. Con ThemeMode.system seguiría al
      // sistema operativo.
      themeMode: ThemeMode.dark,
      home: const HomeScreen(),
    );
  }
}
