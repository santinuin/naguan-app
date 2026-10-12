// Genera los pitidos de la cuenta regresiva: assets/sounds/pi.wav (el corto
// del 3, 2, 1) y assets/sounds/piii.wav (el largo del arranque).
//
// Un WAV sin comprimir es casi nada más que las muestras del sonido una
// detrás de otra, con una cabecera de 44 bytes que dice cómo leerlas. Acá se
// arma a mano, byte a byte, con ByteData (el ByteBuffer de Java): no hace
// falta ninguna librería, y se ve qué hay adentro de un archivo de audio.
//
// Uso (desde mobile/):  dart run tool/make_beeps.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Muestras por segundo: la calidad de CD. Alcanza y sobra para un pitido.
const sampleRate = 44100;

void main() {
  // El corto, en La 5 (880 Hz). El largo, una quinta arriba (1320 Hz): el
  // cambio de altura dice "ya" aunque no se distinga bien la duración (como
  // la largada de una carrera). Los parlantes de un teléfono reproducen mal
  // los graves: por debajo de ~500 Hz se escucharía flojo.
  _write('assets/sounds/pi.wav', _tone(hz: 880, ms: 160));
  _write('assets/sounds/piii.wav', _tone(hz: 1320, ms: 900));
}

/// Una onda seno de [hz] durante [ms], en muestras de 16 bits con signo.
Int16List _tone({required double hz, required int ms}) {
  final count = sampleRate * ms ~/ 1000;
  // Fundido de 8 ms al entrar y al salir. Cortar una onda a mitad de camino
  // es un salto brusco de la membrana del parlante, que se oye como un
  // "clic"; con la rampa, el sonido entra y sale limpio.
  final fade = sampleRate * 8 ~/ 1000;
  final samples = Int16List(count);
  for (var i = 0; i < count; i++) {
    final t = i / sampleRate;
    // La fundamental más un poco de la segunda armónica: un seno puro suena
    // "fino" en un parlante chico; la armónica le da cuerpo y se oye mejor
    // por encima de la música.
    final wave = 0.8 * sin(2 * pi * hz * t) + 0.2 * sin(2 * pi * 2 * hz * t);
    final envelope = min(1.0, min(i, count - 1 - i) / fade);
    // 16 bits con signo: de -32768 a 32767. Se deja margen (0,9) para no
    // saturar.
    samples[i] = (wave * envelope * 0.9 * 32767).round();
  }
  return samples;
}

void _write(String path, Int16List samples) {
  const channels = 1, bitsPerSample = 16;
  const blockAlign = channels * bitsPerSample ~/ 8; // bytes por muestra
  final dataSize = samples.length * blockAlign;

  // La cabecera RIFF/WAVE: tres "chunks" (RIFF, fmt, data). Los números van
  // en little-endian (el byte menos significativo primero), como pide el
  // formato; ByteData usa big-endian si no se le dice lo contrario.
  final header = ByteData(44);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little); // lo que sigue
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // tamaño de este chunk
  header.setUint16(20, 1, Endian.little); // 1 = PCM, sin comprimir
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * blockAlign, Endian.little); // bytes/s
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  // Las muestras: un Int16List ya es memoria contigua de 16 bits. Se copian
  // a ByteData en little-endian explícito, para no depender del procesador.
  final data = ByteData(dataSize);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }

  final out = File(path);
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
  stdout.writeln('$path (${out.lengthSync() ~/ 1024} KiB)');
}
