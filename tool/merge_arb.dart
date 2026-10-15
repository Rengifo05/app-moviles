// Fusiona los fragmentos de textos de lib/l10n/fragments/<grupo>.<idioma>.json
// en lib/l10n/arb/app_<idioma>.arb (que es lo que lee gen-l10n).
//
// Permite que cada funcionalidad tenga su propio archivo de textos sin
// conflictos: el resultado es determinista (claves ordenadas por fragmento y
// por nombre) y se puede ejecutar en paralelo sin perder cambios.
//
// Uso: dart run tool/merge_arb.dart [--check]
// Con --check falla si los .arb no coinciden con los fragmentos (CI).
import 'dart:convert';
import 'dart:io';

const fragmentsDir = 'lib/l10n/fragments';
const arbDir = 'lib/l10n/arb';
const locales = ['es', 'en'];
const template = 'es';

void main(List<String> args) {
  final check = args.contains('--check');
  final fragments =
      Directory(fragmentsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final merged = {
    for (final l in locales) l: <String, Object?>{'@@locale': l},
  };
  final owner = <String, String>{};
  for (final file in fragments) {
    final name = file.uri.pathSegments.last; // grupo.idioma.json
    final parts = name.split('.');
    if (parts.length != 3) {
      _fail('Nombre de fragmento inválido: $name (usa grupo.idioma.json)');
    }
    final locale = parts[1];
    if (!locales.contains(locale)) _fail('Idioma no soportado en $name');
    final content = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final keys = content.keys.toList()..sort();
    for (final key in keys) {
      final previous = owner['$locale:$key'];
      if (previous != null) {
        _fail('Clave duplicada "$key" en $name y $previous');
      }
      owner['$locale:$key'] = name;
      merged[locale]![key] = content[key];
    }
  }

  // Toda clave del español (plantilla) debe existir en los demás idiomas.
  final templateKeys = merged[template]!.keys.where((k) => !k.startsWith('@'));
  for (final locale in locales.where((l) => l != template)) {
    final missing = templateKeys.where((k) => !merged[locale]!.containsKey(k));
    if (missing.isNotEmpty) {
      _fail('Faltan traducciones en "$locale": ${missing.join(', ')}');
    }
  }

  const encoder = JsonEncoder.withIndent('  ');
  var stale = false;
  for (final locale in locales) {
    final out = File('$arbDir/app_$locale.arb');
    final text = '${encoder.convert(merged[locale])}\n';
    if (check) {
      if (!out.existsSync() || out.readAsStringSync() != text) stale = true;
    } else {
      out.writeAsStringSync(text);
    }
  }
  if (check && stale) {
    _fail(
      'Los .arb no coinciden con los fragmentos: ejecuta '
      '`dart run tool/merge_arb.dart`.',
    );
  }
}

Never _fail(String message) {
  stderr.writeln('merge_arb: $message');
  exit(1);
}
