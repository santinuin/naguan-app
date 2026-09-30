import 'package:flutter/material.dart';
import 'package:naguan_app/home_screen.dart';

void main() {
  runApp(const NaguanApp());
}

class NaguanApp extends StatelessWidget {
  const NaguanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FORJA DEL NAGUAN',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
      home: const HomeScreen()
    );
  }
}
