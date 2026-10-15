// Verifica automáticamente los límites entre capas descritos en
// docs/architecture/01-arquitectura-propuesta.md. Si esta prueba falla, la
// corrección es mover el código a la capa correcta, no ampliar la excepción.
//
// Diseño (tras la revisión adversarial del incremento 1):
// * Mundo cerrado: todo archivo .dart de lib/ debe pertenecer a una capa
//   conocida; un archivo fuera de ellas es una violación (evita "puentes").
// * Listas de permitidos por capa, no de prohibidos.
// * Las directivas se leen con el AST de package:analyzer, incluidas las URIs
//   de las importaciones condicionales (`if (dart.library.io) '...'`).
// * Las rutas se normalizan a formato POSIX (funciona también en Windows).
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _package = 'nexo_familia';

enum Layer {
  entrypoint,
  app,
  core,
  designSystem,
  infrastructure,
  domain,
  data,
  presentation,
  l10n,
}

/// Capa de un archivo a partir de su ruta POSIX relativa al proyecto, o
/// `null` si está fuera de las ubicaciones permitidas.
Layer? layerOf(String path) {
  if (path == 'lib/main.dart') return Layer.entrypoint;
  if (path.startsWith('lib/app/')) return Layer.app;
  if (path.startsWith('lib/core/')) return Layer.core;
  if (path.startsWith('lib/design_system/')) return Layer.designSystem;
  if (path.startsWith('lib/infrastructure/')) return Layer.infrastructure;
  if (path.startsWith('lib/l10n/')) return Layer.l10n;
  final feature = RegExp('^lib/features/[a-z_]+/(domain|data|presentation)/')
      .firstMatch(path);
  return switch (feature?.group(1)) {
    'domain' => Layer.domain,
    'data' => Layer.data,
    'presentation' => Layer.presentation,
    _ => null,
  };
}

/// Una importación, exportación o parte: su URI resuelta a ruta POSIX
/// (`lib/...`) si es interna, o tal cual (`package:`/`dart:`) si es externa.
typedef Dependency = ({String target, bool isPart});

List<Dependency> dependenciesOf(String source, String filePath) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final result = <Dependency>[];
  void add(String? uri, {bool isPart = false}) {
    if (uri == null) return;
    result.add((target: resolveUri(uri, filePath), isPart: isPart));
  }

  for (final directive in unit.directives) {
    switch (directive) {
      case NamespaceDirective():
        add(directive.uri.stringValue);
        for (final configuration in directive.configurations) {
          add(configuration.uri.stringValue);
        }
      case PartDirective():
        add(directive.uri.stringValue, isPart: true);
      default:
        break;
    }
  }
  return result;
}

String resolveUri(String uri, String filePath) {
  const internalPrefix = 'package:$_package/';
  if (uri.startsWith(internalPrefix)) {
    return p.posix.normalize('lib/${uri.substring(internalPrefix.length)}');
  }
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
  return p.posix.normalize(p.posix.join(p.posix.dirname(filePath), uri));
}

bool _under(String target, String prefix) => target.startsWith(prefix);

bool _isFeatureLayer(String target, String layer) =>
    RegExp('^lib/features/[a-z_]+/$layer/').hasMatch(target);

const _pureDart = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:math',
  'dart:typed_data',
};

/// Motivo de la violación, o `null` si la dependencia está permitida.
String? violation(Layer layer, Dependency dep) {
  final t = dep.target;
  if (dep.isPart) {
    // Las partes (código generado) deben quedarse en la misma capa.
    return layerOf(t) == layer ? null : 'una parte debe estar en su capa';
  }
  switch (layer) {
    case Layer.entrypoint:
    case Layer.app:
    case Layer.l10n:
      // Raíz de composición y código generado por gen-l10n.
      return null;

    case Layer.domain:
      final ok =
          _pureDart.contains(t) ||
          _under(t, 'package:meta/') ||
          (_under(t, 'lib/core/') && !_under(t, 'lib/core/di/')) ||
          _isFeatureLayer(t, 'domain');
      return ok ? null : 'el dominio es Dart puro (core, meta y dominios)';

    case Layer.core:
      final ok =
          _pureDart.contains(t) ||
          t == 'dart:developer' ||
          _under(t, 'package:meta/') ||
          _under(t, 'package:uuid/') ||
          _under(t, 'package:riverpod/') ||
          _under(t, 'lib/core/');
      return ok ? null : 'core es Dart puro y no depende de capas superiores';

    case Layer.designSystem:
      final ok =
          _under(t, 'dart:') ||
          _under(t, 'package:flutter/') ||
          _under(t, 'package:meta/') ||
          _under(t, 'lib/design_system/') ||
          _under(t, 'lib/core/');
      return ok ? null : 'el sistema de diseño no conoce funcionalidades';

    case Layer.infrastructure:
      final forbidden =
          _under(t, 'lib/app/') ||
          _isFeatureLayer(t, 'data') ||
          _isFeatureLayer(t, 'presentation') ||
          _under(t, 'lib/l10n/');
      return forbidden
          ? 'infraestructura solo implementa contratos de dominio'
          : null;

    case Layer.data:
      final forbidden =
          _under(t, 'lib/app/') ||
          _isFeatureLayer(t, 'presentation') ||
          _under(t, 'lib/design_system/') ||
          _under(t, 'lib/l10n/') ||
          _under(t, 'package:flutter/');
      return forbidden ? 'data no conoce la interfaz ni la composición' : null;

    case Layer.presentation:
      final ok =
          _under(t, 'dart:') ||
          _under(t, 'package:flutter/') ||
          _under(t, 'package:flutter_riverpod/') ||
          _under(t, 'package:riverpod/') ||
          _under(t, 'package:go_router/') ||
          _under(t, 'package:meta/') ||
          _under(t, 'package:intl/') ||
          _under(t, 'lib/core/') ||
          _under(t, 'lib/design_system/') ||
          _under(t, 'lib/l10n/') ||
          _isFeatureLayer(t, 'domain') ||
          _isFeatureLayer(t, 'presentation');
      return ok ? null : 'presentation depende de dominio, core, diseño y l10n';
  }
}

/// Violaciones en `lib/` de [projectRoot].
List<String> findViolations(Directory projectRoot) {
  final lib = Directory(p.join(projectRoot.path, 'lib'));
  final violations = <String>[];
  final files =
      lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final path = p.posix.joinAll(
      p.split(p.relative(file.path, from: projectRoot.path)),
    );
    final layer = layerOf(path);
    if (layer == null) {
      violations.add('$path (ubicación no permitida por la arquitectura)');
      continue;
    }
    for (final dep in dependenciesOf(file.readAsStringSync(), path)) {
      final reason = violation(layer, dep);
      if (reason != null) violations.add('$path → ${dep.target} ($reason)');
    }
  }
  return violations;
}

void main() {
  test('las capas respetan sus límites de dependencias', () {
    final violations = findViolations(Directory.current);
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  group('el detector reconoce violaciones', () {
    // Proyecto falso en un directorio temporal: no toca el `lib/` real.
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('nx_arch_'));

    tearDown(() => tmp.deleteSync(recursive: true));

    void write(String relative, String content) {
      File(p.join(tmp.path, 'lib', relative))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    List<String> violations() => findViolations(tmp);

    test('dominio que importa Flutter, Firestore o flutter_localizations', () {
      write(
        'features/x/domain/a.dart',
        "import 'package:flutter/material.dart';",
      );
      write(
        'features/x/domain/b.dart',
        "import 'package:cloud_firestore/cloud_firestore.dart';",
      );
      write(
        'features/x/domain/c.dart',
        "import 'package:flutter_localizations/flutter_localizations.dart';",
      );
      expect(violations(), hasLength(3));
    });

    test('importación condicional con una rama prohibida', () {
      write('features/x/domain/stub.dart', '');
      write('features/x/domain/a.dart', '''
import 'stub.dart'
    if (dart.library.ui) 'package:flutter/foundation.dart';
''');
      expect(violations(), [contains('package:flutter/foundation.dart')]);
    });

    test('dominio que importa core/di, l10n o infraestructura', () {
      write(
        'features/x/domain/a.dart',
        "import 'package:nexo_familia/core/di/core_providers.dart';",
      );
      write(
        'features/x/domain/b.dart',
        "import 'package:nexo_familia/l10n/gen/app_localizations.dart';",
      );
      write(
        'features/x/domain/c.dart',
        "import '../../../infrastructure/remote/remote_store.dart';",
      );
      expect(violations(), hasLength(3));
    });

    test('archivos fuera de las capas (puentes y barriles)', () {
      write('shared/bridge.dart', "export 'package:flutter/foundation.dart';");
      write('features/x/x.dart', "export 'data/repo.dart';");
      expect(violations(), hasLength(2));
    });

    test('presentation que importa data (absoluta y relativa)', () {
      write(
        'features/x/presentation/a.dart',
        "import 'package:nexo_familia/features/x/data/repo.dart';",
      );
      write('features/x/presentation/b.dart', "import '../data/repo.dart';");
      expect(violations(), hasLength(2));
    });

    test('presentation que importa drift o infraestructura', () {
      write(
        'features/x/presentation/a.dart',
        "import 'package:drift/drift.dart';",
      );
      write(
        'features/x/presentation/b.dart',
        "import 'package:nexo_familia/infrastructure/maps/google_map.dart';",
      );
      expect(violations(), hasLength(2));
    });

    test('infraestructura que importa presentation o data', () {
      write(
        'infrastructure/a.dart',
        "import 'package:nexo_familia/features/x/presentation/screen.dart';",
      );
      write(
        'infrastructure/b.dart',
        "import 'package:nexo_familia/features/x/data/repo.dart';",
      );
      expect(violations(), hasLength(2));
    });

    test('sistema de diseño que importa una funcionalidad', () {
      write(
        'design_system/a.dart',
        "import 'package:nexo_familia/features/x/domain/entity.dart';",
      );
      expect(violations(), hasLength(1));
    });

    test('las importaciones comentadas no cuentan', () {
      write('features/x/domain/a.dart', '''
/*
import 'package:flutter/material.dart';
*/
// import 'package:drift/drift.dart';
''');
      expect(violations(), isEmpty);
    });

    test('dependencias legítimas no generan violaciones', () {
      write('core/result.dart', "import 'package:meta/meta.dart';");
      write(
        'features/x/domain/a.dart',
        "import 'package:nexo_familia/core/result.dart';\n"
            "import 'package:nexo_familia/features/y/domain/b.dart';",
      );
      write('features/y/domain/b.dart', "import 'dart:math';");
      write(
        'features/x/data/repo.dart',
        "import 'package:drift/drift.dart';\nimport '../domain/a.dart';",
      );
      write(
        'features/x/presentation/screen.dart',
        "import 'package:flutter/material.dart';\n"
            "import '../domain/a.dart';\n"
            "import 'package:nexo_familia/design_system/button.dart';",
      );
      write(
        'design_system/button.dart',
        "import 'package:flutter/material.dart';",
      );
      write(
        'infrastructure/db.dart',
        "import 'package:drift/drift.dart';\n"
            "import 'package:nexo_familia/features/x/domain/a.dart';\n"
            "part 'db.g.dart';",
      );
      write('infrastructure/db.g.dart', "part of 'db.dart';");
      write(
        'app/bootstrap.dart',
        "import 'package:nexo_familia/features/x/data/repo.dart';",
      );
      write('main.dart', "import 'app/bootstrap.dart';");
      expect(violations(), isEmpty);
    });
  });
}
