// Verifica automáticamente los límites entre capas descritos en
// docs/architecture/01-arquitectura-propuesta.md. Si esta prueba falla, la
// corrección es mover el código a la capa correcta, no ampliar la excepción.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Paquetes de infraestructura que solo la capa `data` y `app/` pueden usar.
const _infrastructure = [
  'package:cloud_firestore/',
  'package:cloud_functions/',
  'package:firebase_',
  'package:drift',
  'package:sqlite3',
  'package:geolocator',
  'package:native_geofence',
  'package:permission_handler',
  'package:google_maps_flutter',
  'package:flutter_secure_storage',
  'package:connectivity_plus',
];

/// Lo que el dominio no puede importar además de la infraestructura.
const _domainExtra = [
  'package:flutter/',
  'package:flutter_riverpod/',
  'package:riverpod/',
  'package:go_router/',
  'dart:ui',
  'dart:io',
];

final _importPattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Importaciones de un archivo. Las internas (`package:nexo_familia/...` o
/// relativas) se devuelven como rutas relativas a [projectRoot].
List<String> importsOf(File file, Directory projectRoot) {
  final source = file.readAsStringSync();
  return _importPattern.allMatches(source).map((m) {
    final uri = m.group(1)!;
    if (uri.startsWith('package:nexo_familia/')) {
      return 'lib/${uri.substring('package:nexo_familia/'.length)}';
    }
    if (uri.startsWith('package:') || uri.startsWith('dart:')) return uri;
    return _relative(
      File(file.parent.uri.resolve(uri).toFilePath()),
      projectRoot,
    );
  }).toList();
}

String _relative(File file, Directory projectRoot) =>
    file.absolute.path.replaceFirst('${projectRoot.absolute.path}/', '');

/// Violaciones de las reglas de capas en `lib/` de [projectRoot].
List<String> findViolations(Directory projectRoot) {
  final violations = <String>[];
  final files = Directory('${projectRoot.path}/lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'));

  for (final file in files) {
    final path = _relative(file, projectRoot);
    final layer = _layerOf(path);
    if (layer == null) continue;
    for (final import in importsOf(file, projectRoot)) {
      final reason = _violation(layer, import);
      if (reason != null) violations.add('$path → $import ($reason)');
    }
  }
  return violations;
}

enum _Layer { domain, presentation, data, coreLogic, designSystem }

_Layer? _layerOf(String path) {
  if (RegExp('^lib/features/[^/]+/domain/').hasMatch(path)) {
    return _Layer.domain;
  }
  if (RegExp('^lib/features/[^/]+/presentation/').hasMatch(path)) {
    return _Layer.presentation;
  }
  if (RegExp('^lib/features/[^/]+/data/').hasMatch(path)) return _Layer.data;
  if (path.startsWith('lib/design_system/')) return _Layer.designSystem;
  // `core/platform/` puede usar Flutter y plugins: es el adaptador de SO.
  if (path.startsWith('lib/core/') && !path.startsWith('lib/core/platform/')) {
    return _Layer.coreLogic;
  }
  return null;
}

bool _isInfrastructure(String import) => _infrastructure.any(import.startsWith);

String? _violation(_Layer layer, String import) {
  final isFeatureData = RegExp('^lib/features/[^/]+/data/').hasMatch(import);
  final isFeaturePresentation = RegExp('^lib/features/[^/]+/presentation/')
      .hasMatch(import);

  switch (layer) {
    case _Layer.domain:
      if (_isInfrastructure(import) || _domainExtra.any(import.startsWith)) {
        return 'el dominio debe ser Dart puro';
      }
      if (isFeatureData || isFeaturePresentation) {
        return 'el dominio no conoce data ni presentation';
      }
      if (import.startsWith('lib/app/') ||
          import.startsWith('lib/design_system/')) {
        return 'el dominio no conoce app ni design_system';
      }
    case _Layer.presentation:
      if (_isInfrastructure(import)) {
        return 'los widgets no acceden a Firebase, SQLite ni plugins';
      }
      if (isFeatureData) return 'presentation solo depende del dominio';
      if (import.startsWith('lib/app/')) {
        return 'presentation no depende de la raíz de composición';
      }
    case _Layer.data:
      if (isFeaturePresentation) return 'data no conoce la interfaz';
      if (import.startsWith('lib/app/')) {
        return 'data no depende de la raíz de composición';
      }
    case _Layer.designSystem:
      if (_isInfrastructure(import) ||
          import.startsWith('lib/features/') ||
          import.startsWith('lib/app/')) {
        return 'el sistema de diseño es independiente de las funciones';
      }
    case _Layer.coreLogic:
      if (_isInfrastructure(import) ||
          import.startsWith('package:flutter/') ||
          import.startsWith('package:flutter_riverpod/') ||
          import.startsWith('dart:ui')) {
        return 'core (fuera de core/platform) es Dart puro';
      }
      if (import.startsWith('lib/features/') ||
          import.startsWith('lib/app/') ||
          import.startsWith('lib/design_system/')) {
        return 'core no depende de capas superiores';
      }
  }
  return null;
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
      File('${tmp.path}/lib/features/probe/$relative')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    test('dominio que importa Flutter o Firestore', () {
      write('domain/a.dart', "import 'package:flutter/material.dart';");
      write(
        'domain/b.dart',
        "import 'package:cloud_firestore/cloud_firestore.dart';",
      );
      expect(findViolations(tmp), hasLength(2));
    });

    test('presentation que importa data (absoluta y relativa)', () {
      write(
        'presentation/a.dart',
        "import 'package:nexo_familia/features/probe/data/x.dart';",
      );
      write('presentation/b.dart', "import '../data/x.dart';");
      expect(findViolations(tmp), hasLength(2));
    });

    test('presentation que importa drift directamente', () {
      write('presentation/a.dart', "import 'package:drift/drift.dart';");
      expect(findViolations(tmp), hasLength(1));
    });

    test('dominio limpio no genera violaciones', () {
      write('domain/a.dart', "import 'package:meta/meta.dart';");
      write('domain/b.dart', "import 'package:nexo_familia/core/result.dart';");
      expect(findViolations(tmp), isEmpty);
    });
  });
}
