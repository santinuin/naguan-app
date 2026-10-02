import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

final forjaHierro = buildForjaTheme(ForjaPalette.hierro);
final forjaHueso = buildForjaTheme(ForjaPalette.hueso);

/// Arma el [ThemeData] de Material a partir de una paleta de Forja.
ThemeData buildForjaTheme(ForjaPalette p) {
  final text = _textTheme(p);

  return ThemeData(
    brightness: p.brightness,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.accentSoft,
      onPrimaryContainer: p.ink,
      secondary: p.signal,
      onSecondary: p.onAccent,
      // El sistema de diseño no define un color de error; signal es el de
      // advertencia, y siempre va acompañado de texto.
      error: p.signal,
      onError: p.onAccent,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      outline: p.stroke,
      outlineVariant: p.line,
      // Material 3 tiñe las superficies elevadas con primary. Lo apagamos:
      // un panel se define por su borde, no por su relleno.
      surfaceTint: Colors.transparent,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ForjaRadius.panel),
        side: BorderSide(color: p.stroke, width: ForjaBorder.heavy),
      ),
    ),
    // Hojas inferiores (el editor de un ejercicio): un panel más, con el
    // borde grueso y sin el tinte de color que Material 3 pone por defecto.
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.inkMuted,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ForjaRadius.panel),
        ),
        side: BorderSide(color: p.stroke, width: ForjaBorder.heavy),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        // Un color por estado: deshabilitado, presionado o normal.
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.line;
          if (states.contains(WidgetState.pressed)) return p.accentPressed;
          return p.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return p.inkMuted;
          return p.onAccent;
        }),
        // Sin ripple: el feedback es el cambio a accentPressed.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(text.titleLarge),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: ForjaSpace.s6,
            vertical: ForjaSpace.s4,
          ),
        ),
        // radius-none: bloque duro.
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: ForjaBorder.hair),
    // Barras de progreso y spinners: el acento marca el avance sobre `line`.
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.accent,
      linearTrackColor: p.line,
      circularTrackColor: Colors.transparent,
    ),
    // Botones de texto (acciones secundarias como SALIR): etiqueta técnica
    // en Space Mono, con el rosa como texto (accentText).
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accentText,
        textStyle: text.labelSmall?.copyWith(fontSize: 14),
      ),
    ),
    // Campos de texto: borde grueso en stroke y esquinas rectas. El borde
    // cambia según el estado (normal, con foco, con error); cada estado es
    // un InputBorder distinto.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      labelStyle: text.labelSmall,
      floatingLabelStyle: text.labelSmall?.copyWith(color: p.accentText),
      hintStyle: text.bodyLarge?.copyWith(color: p.inkMuted),
      errorStyle: text.bodyLarge?.copyWith(color: p.signal, fontSize: 14),
      contentPadding: const EdgeInsets.all(ForjaSpace.s4),
      border: _inputBorder(p.stroke),
      enabledBorder: _inputBorder(p.stroke),
      focusedBorder: _inputBorder(p.accent),
      errorBorder: _inputBorder(p.signal),
      focusedErrorBorder: _inputBorder(p.signal),
    ),
    extensions: [
      Forja(
        palette: p,
        stat: TextStyle(
          fontFamily: ForjaFonts.mono,
          fontSize: 48,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: p.ink,
        ),
        bodyStrong: text.bodyLarge!.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}

OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.zero,
  borderSide: BorderSide(color: color, width: ForjaBorder.heavy),
);

/// Estilos de texto de `tokens.json` mapeados a los roles de Material.
///
/// `height` en Flutter es un multiplicador del tamaño, por eso se escribe
/// como interlineado / tamaño (58 / 64 = 58px de línea).
TextTheme _textTheme(ForjaPalette p) {
  return TextTheme(
    // hero: una palabra por pantalla.
    displayLarge: TextStyle(
      fontFamily: ForjaFonts.display,
      fontSize: 64,
      height: 58 / 64,
      letterSpacing: -1,
      color: p.ink,
    ),
    // display: nombre del ejercicio en curso.
    displayMedium: TextStyle(
      fontFamily: ForjaFonts.display,
      fontSize: 40,
      height: 38 / 40,
      letterSpacing: -0.5,
      color: p.ink,
    ),
    // title: títulos de sección, de tarjeta y del AppBar.
    titleLarge: TextStyle(
      fontFamily: ForjaFonts.display,
      fontSize: 24,
      height: 26 / 24,
      letterSpacing: 0,
      color: p.ink,
    ),
    // heading: subtítulos en frase normal.
    headlineSmall: TextStyle(
      fontFamily: ForjaFonts.sans,
      fontSize: 20,
      height: 24 / 20,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
      color: p.ink,
    ),
    // body: instrucciones y descripciones.
    bodyLarge: TextStyle(
      fontFamily: ForjaFonts.sans,
      fontSize: 16,
      height: 24 / 16,
      letterSpacing: 0,
      color: p.ink,
    ),
    // bodyMedium es el estilo por defecto de un Text sin estilo: lo
    // igualamos a body.
    bodyMedium: TextStyle(
      fontFamily: ForjaFonts.sans,
      fontSize: 16,
      height: 24 / 16,
      letterSpacing: 0,
      color: p.ink,
    ),
    // label: etiquetas técnicas en MAYÚSCULAS.
    labelSmall: TextStyle(
      fontFamily: ForjaFonts.mono,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: p.inkMuted,
    ),
  );
}

/// Lo del sistema de diseño que no tiene lugar en [ThemeData]: la paleta
/// completa y los estilos `stat` y `body-strong`.
///
/// Se lee con `context.forja` (ver [ForjaContext]).
@immutable
class Forja extends ThemeExtension<Forja> {
  const Forja({
    required this.palette,
    required this.stat,
    required this.bodyStrong,
  });

  final ForjaPalette palette;

  /// Repeticiones, series y cronómetro.
  final TextStyle stat;

  /// Énfasis dentro de una instrucción, filas de serie.
  final TextStyle bodyStrong;

  @override
  Forja copyWith({
    ForjaPalette? palette,
    TextStyle? stat,
    TextStyle? bodyStrong,
  }) {
    return Forja(
      palette: palette ?? this.palette,
      stat: stat ?? this.stat,
      bodyStrong: bodyStrong ?? this.bodyStrong,
    );
  }

  /// Interpola entre temas cuando la app cambia de Hierro a Hueso con
  /// animación. Los estilos se interpolan; la paleta cambia de golpe a la
  /// mitad, porque interpolar color por color no aporta en este estilo.
  @override
  Forja lerp(Forja? other, double t) {
    if (other == null) return this;
    return Forja(
      palette: t < 0.5 ? palette : other.palette,
      stat: TextStyle.lerp(stat, other.stat, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
    );
  }
}

/// Atajo: `context.forja.palette.signal`, `context.forja.stat`.
extension ForjaContext on BuildContext {
  Forja get forja => Theme.of(this).extension<Forja>()!;
}
