// Genera la textura de grano del fondo: assets/textures/grain.png.
//
// El sistema de diseño pide "un grano sutil sobre bg" (PNG de ruido
// monocromo de 256×256, repetido en mosaico) que le quite lo digital y le dé
// aspecto de impreso. Este grano imita el desgaste de una serigrafía: además
// de motas finas parejas, tiene manchas grandes donde las motas se amontonan
// (como la tinta que no agarró bien en el papel).
//
// La imagen es blanca con transparencia: solo importa el canal alfa. La app
// la tiñe con el color `ink` de cada tema y le baja la opacidad (ver
// lib/theme/forja_background.dart).
//
// Uso (desde mobile/):  dart run tool/make_grain.dart
//
// tool/ es la convención de Dart para los scripts de desarrollo de un
// paquete: no forman parte de la app (no los importa lib/) y se corren con
// `dart run`. La semilla es fija: siempre sale la misma imagen.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// Lado de la textura, en píxeles.
const size = 256;

/// Celdas de la grilla de las manchas por lado: 6 celdas de ~43 px dan
/// manchas de ese orden, visibles pero no gigantes.
const cells = 6;

const seed = 7;

// La densidad del grano. Para ajustarlo, cambiar estos números y volver a
// correr el script (y mirar el resultado en la app).

/// Probabilidad de que un píxel sea una mota en una zona limpia...
const speckBase = 0.025;

/// ...y cuánto sube en lo más denso de una mancha (el desgaste).
const speckInBlotch = 0.12;

/// Opacidad máxima del grano fino parejo que cubre todo.
const fineMax = 0.15;

void main() {
  final random = Random(seed);

  // 1. Manchas: "value noise" periódico. Una grilla gruesa de valores al
  //    azar, interpolada suave entre sus puntos. La grilla da la vuelta: la
  //    celda siguiente a la última es la primera (el % cells de lattice), así
  //    que el borde derecho de la textura continúa en el izquierdo y el de
  //    abajo en el de arriba. Al repetirla en mosaico, no se ven costuras.
  //
  //    Con una sola grilla, las manchas caen con cierta regularidad (se
  //    adivina la cuadrícula). Se suma una segunda capa ("octava") con una
  //    grilla del doble de fina y la mitad de peso: rompe la regularidad y
  //    agrega detalle. Es la idea del "ruido fractal" de los gráficos.
  final coarse = _ValueNoise(cells, random);
  final detail = _ValueNoise(cells * 2, random);
  double blotchAt(int x, int y) => coarse.at(x, y) + 0.5 * detail.at(x, y);

  // Se calculan todas y se normalizan a 0..1: la interpolación nunca llega
  // a los extremos de la grilla, y así las manchas usan todo el rango.
  final blotch = [
    for (var y = 0; y < size; y++)
      for (var x = 0; x < size; x++) blotchAt(x, y),
  ];
  final lo = blotch.reduce(min), hi = blotch.reduce(max);

  final image = img.Image(width: size, height: size, numChannels: 4);
  var alphaSum = 0.0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final b = (blotch[y * size + x] - lo) / (hi - lo);
      // 2. Motas: cada píxel es una mota con una probabilidad que sube en
      //    las manchas (al cuadrado: zonas limpias y zonas gastadas).
      final speck = random.nextDouble() < speckBase + speckInBlotch * b * b;
      // 3. Grano fino parejo de fondo, muy suave.
      final fine = random.nextDouble() * fineMax;
      final alpha = min(1.0, (speck ? 0.85 : 0.0) + fine);
      alphaSum += alpha;
      image.setPixelRgba(x, y, 255, 255, 255, (alpha * 255).round());
    }
  }

  final out = File('assets/textures/grain.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(image));
  // stdout y no print: el linter (avoid_print) pide no usar print, que en
  // una app termina en los logs de producción. En un script es la salida.
  stdout.writeln(
    '${out.path} (${out.lengthSync() ~/ 1024} KiB), '
    'alfa promedio ${(alphaSum / (size * size)).toStringAsFixed(2)}',
  );
}

/// Ruido de valores periódico: una grilla de [cells]×[cells] valores al azar,
/// interpolada suave. La grilla da la vuelta (el `% cells`): la celda que
/// sigue a la última es la primera, así que la textura empalma consigo
/// misma.
class _ValueNoise {
  _ValueNoise(this.cells, Random random)
    : _lattice = List.generate(
        cells,
        (_) => List.generate(cells, (_) => random.nextDouble()),
      );

  final int cells;
  final List<List<double>> _lattice;

  double _lat(int x, int y) => _lattice[y % cells][x % cells];

  // smoothstep: una curva en S entre 0 y 1. Interpolar con ella (y no en
  // línea recta) evita que se vean los bordes de las celdas como pliegues.
  static double _smooth(double t) => t * t * (3 - 2 * t);
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// El valor en el píxel (x, y) de la textura.
  double at(int x, int y) {
    final gx = x * cells / size, gy = y * cells / size;
    final x0 = gx.floor(), y0 = gy.floor();
    final tx = _smooth(gx - x0), ty = _smooth(gy - y0);
    // Interpolación bilineal entre las cuatro esquinas de la celda.
    final top = _lerp(_lat(x0, y0), _lat(x0 + 1, y0), tx);
    final bottom = _lerp(_lat(x0, y0 + 1), _lat(x0 + 1, y0 + 1), tx);
    return _lerp(top, bottom, ty);
  }
}
