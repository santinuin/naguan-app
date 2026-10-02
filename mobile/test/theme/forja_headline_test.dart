import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/theme/forja_headline.dart';

void main() {
  // En los tests, la fuente por defecto ("FlutterTest") dibuja cada letra
  // como un cuadrado del tamaño de la fuente: "ABCDE" a 10 px mide 50 px.
  // Así los anchos se pueden calcular a mano.
  const style = TextStyle(fontSize: 10, fontFamily: 'FlutterTest');

  test('si la palabra más larga entra, no cambia nada', () {
    final fitted = fitLongestWord('AB ABCDE', style, maxWidth: 50);
    expect(fitted.fontSize, 10);
  });

  test('si no entra, achica la fuente hasta que entre', () {
    // ABCDEFGHIJ mide 100 px a 10 px: para 50 px hace falta la mitad.
    final fitted = fitLongestWord('UNO ABCDEFGHIJ DOS', style, maxWidth: 50);
    expect(fitted.fontSize, closeTo(5 * 0.98, 0.01));
  });

  test('mide con la escala de la letra del sistema', () {
    // Con el texto al 200%, ABCDE mide 100 px y ya no entra en 60.
    final fitted = fitLongestWord(
      'ABCDE',
      style,
      maxWidth: 60,
      textScaler: const TextScaler.linear(2),
    );
    expect(fitted.fontSize, lessThan(10));
  });
}
