import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Las fuentes empaquetadas y el archivo con su licencia (en assets/fonts/).
///
/// Un record `(String, List<String>)` por fuente: el archivo y los nombres
/// con que aparece en la página de licencias.
const _fonts = [
  ('OFL-Archivo.txt', ['Archivo']),
  ('OFL-ArchivoBlack.txt', ['Archivo Black']),
  ('OFL-SpaceMono.txt', ['Space Mono']),
];

/// Suma las licencias de las fuentes a las que muestra `showLicensePage`.
///
/// Las fuentes tienen licencia SIL Open Font License 1.1: se pueden
/// distribuir libremente, siempre que viajen con su aviso de copyright y el
/// texto de la licencia. Las licencias de los paquetes de pub.dev las junta
/// Flutter solo al compilar (el archivo NOTICES del APK); las fuentes no son
/// paquetes, son archivos que agregamos nosotros, así que se registran a
/// mano.
void registerFontLicenses() {
  // addLicense recibe una función que devuelve un Stream, y la llama recién
  // cuando alguien abre la página de licencias: los textos no se leen al
  // arrancar la app.
  //
  // `async*` hace de la función un generador asíncrono: cada `yield` emite un
  // elemento del Stream (como emitir en un Flux.create), y el `await` del
  // medio no bloquea nada.
  LicenseRegistry.addLicense(() async* {
    for (final (file, names) in _fonts) {
      // rootBundle: los assets empaquetados en el APK (declarados en
      // pubspec.yaml).
      final text = await rootBundle.loadString('assets/fonts/$file');
      // "WithLineBreaks": el texto ya trae sus saltos de línea y la página
      // los respeta, en vez de reacomodar los párrafos.
      yield LicenseEntryWithLineBreaks(names, text);
    }
  });
}
