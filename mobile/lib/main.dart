import 'package:flutter/material.dart';
import 'package:workout_app/home_screen.dart';

void main() {
  runApp(const WorkoutApp());
}

class WorkoutApp extends StatelessWidget {
  const WorkoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Workout App',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
      home: const HomeScreen()
    );
  }
}
