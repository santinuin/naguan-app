import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/theme/font_licenses.dart';

void main() {
  // Los tests corren sin runApp: hace falta el binding para leer assets.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('registra la licencia OFL de cada fuente', () async {
    registerFontLicenses();

    // LicenseRegistry.licenses junta todo lo registrado. toList espera a que
    // el Stream termine.
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();

    expect(packages, containsAll(['Archivo', 'Archivo Black', 'Space Mono']));
    final text = entries
        .expand((e) => e.paragraphs)
        .map((p) => p.text)
        .join('\n');
    expect(text, contains('SIL Open Font License'));
  });
}
