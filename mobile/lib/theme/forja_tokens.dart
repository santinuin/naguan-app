import 'package:flutter/material.dart';

/// Paleta de un tema del sistema de diseño (Hierro u Hueso).
///
/// Los nombres siguen los tokens de `tokens.json`; cada campo documenta su
/// uso. Hay una instancia `const` por tema.
@immutable
class ForjaPalette {
  const ForjaPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.line,
    required this.stroke,
    required this.ink,
    required this.inkMuted,
    required this.accent,
    required this.accentPressed,
    required this.accentText,
    required this.accentSoft,
    required this.onAccent,
    required this.signal,
  });

  final Brightness brightness;

  /// Fondo de pantalla (~70% de cada pantalla).
  final Color bg;

  /// Paneles y tarjetas; siempre con borde, porque es muy parecido a [bg].
  final Color surface;

  /// Divisores finos (1px). Nunca como único borde de un control.
  final Color line;

  /// Bordes gruesos (3px) de paneles, inputs y botones secundarios.
  final Color stroke;

  /// Texto principal.
  final Color ink;

  /// Texto secundario: descansos, notas, metadatos.
  final Color inkMuted;

  /// Rosa óxido: CTA, progreso, bloque activo. Máximo un bloque grande por
  /// pantalla.
  final Color accent;

  /// Estado presionado del CTA.
  final Color accentPressed;

  /// Rosa usado como texto o ícono sobre [bg].
  final Color accentText;

  /// Fondo de fila seleccionada o del día actual.
  final Color accentSoft;

  /// Texto sobre [accent], [accentPressed] y [signal]. Siempre tinta.
  final Color onAccent;

  /// Amarillo señal: récord, fin de descanso. Siempre con texto.
  final Color signal;

  /// Tema oscuro, el principal.
  static const hierro = ForjaPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF141213),
    surface: Color(0xFF1E1B1C),
    line: Color(0xFF3A3435),
    stroke: Color(0xFFE0708C),
    ink: Color(0xFFEDE4DF),
    inkMuted: Color(0xFF9C918E),
    accent: Color(0xFFE0708C),
    accentPressed: Color(0xFFC95E7A),
    accentText: Color(0xFFE0708C),
    accentSoft: Color(0xFF3D2229),
    onAccent: Color(0xFF141213),
    signal: Color(0xFFF2D16B),
  );

  /// Tema claro: el mismo sistema invertido.
  static const hueso = ForjaPalette(
    brightness: Brightness.light,
    bg: Color(0xFFECE3DC),
    surface: Color(0xFFE2D7CF),
    line: Color(0xFFC4B5AA),
    stroke: Color(0xFF141213),
    ink: Color(0xFF141213),
    inkMuted: Color(0xFF5E5553),
    accent: Color(0xFFE0708C),
    accentPressed: Color(0xFFC95E7A),
    accentText: Color(0xFFA63A57),
    accentSoft: Color(0xFFF2C4CF),
    onAccent: Color(0xFF141213),
    signal: Color(0xFFF2D16B),
  );
}

/// Espaciados (grilla de 4).
abstract final class ForjaSpace {
  /// Ícono–texto dentro de una pill.
  static const double s1 = 4;

  /// Gap entre chips; padding vertical de pills.
  static const double s2 = 8;

  /// Margen lateral de pantalla y padding de paneles.
  static const double s4 = 16;

  /// Entre paneles apilados.
  static const double s6 = 24;

  /// Entre secciones.
  static const double s8 = 32;

  /// Aire sobre el título hero.
  static const double s12 = 48;
}

/// Radios de esquina. Los botones primarios no tienen (radius-none).
abstract final class ForjaRadius {
  static const double panel = 16;
  static const double pill = 999;
}

/// Grosores de borde.
abstract final class ForjaBorder {
  static const double hair = 1;
  static const double heavy = 3;
}

/// Nombres de familia declarados en `pubspec.yaml`.
abstract final class ForjaFonts {
  static const display = 'ArchivoBlack';
  static const sans = 'Archivo';
  static const mono = 'SpaceMono';
}
