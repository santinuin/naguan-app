import 'package:flutter/material.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// La marca escrita: FORJA DEL / NAGUAN, en dos líneas del mismo ancho.
///
/// El sistema de diseño la pide en Archivo Black, en MAYÚSCULAS y cortada
/// en FORJA DEL / NAGUAN (nunca dentro de una palabra). Acá las dos líneas
/// se estiran al ancho disponible: como NAGUAN tiene menos letras, queda
/// más grande que FORJA DEL sin calcular tamaños a mano. FORJA DEL va en
/// rosa como texto (accentText) y NAGUAN, el título, en tinta.
///
/// FittedBox con BoxFit.fitWidth escala su hijo (agrandando o achicando)
/// hasta que ocupe exactamente el ancho que le dan. Así la marca nunca se
/// corta ni desborda, en ninguna pantalla ni con la letra del sistema
/// agrandada (accesibilidad).
class ForjaWordmark extends StatelessWidget {
  const ForjaWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final display = Theme.of(context).textTheme.displayLarge!;
    final palette = context.forja.palette;

    Widget line(String text, Color color) => FittedBox(
      fit: BoxFit.fitWidth,
      child: Text(
        text,
        // height 1: el interlineado del hero (58/64) suma aire arriba y
        // abajo que, escalado, separaría demasiado las dos líneas.
        style: display.copyWith(color: color, height: 1),
        maxLines: 1,
      ),
    );

    // Para los lectores de pantalla, la marca es un nombre y no dos
    // palabras sueltas: un solo label, y se excluyen los dos Text.
    return Semantics(
      label: 'Forja del Naguan',
      header: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            line('FORJA DEL', palette.accentText),
            const SizedBox(height: ForjaSpace.s1),
            line('NAGUAN', palette.ink),
          ],
        ),
      ),
    );
  }
}
