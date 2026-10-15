import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Carga Roboto y Material Icons desde el SDK de Flutter para que las
/// pruebas golden muestren texto e íconos reales (por defecto, las pruebas
/// usan una fuente de bloques). Permite revisar las capturas visualmente.
Future<void> loadAppFonts() async {
  final fonts = _materialFontsDir();
  final roboto = FontLoader('Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(_load(p.join(fonts, 'Roboto-$weight.ttf')));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(_load(p.join(fonts, 'MaterialIcons-Regular.otf')));
  await icons.load();
}

Future<ByteData> _load(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

String _materialFontsDir() {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      // flutter_tester vive en <root>/bin/cache/artifacts/engine/<plataforma>/
      p.normalize(
        p.join(p.dirname(Platform.resolvedExecutable), '../../../../..'),
      );
  final dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
  if (!Directory(dir).existsSync()) {
    throw StateError('No se encontraron las fuentes del SDK en $dir');
  }
  return dir;
}
