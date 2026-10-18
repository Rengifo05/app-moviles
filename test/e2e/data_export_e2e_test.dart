import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/settings/domain/data_export.dart';

import 'e2e_flows.dart';
import 'e2e_harness.dart';

/// Hoja de compartir de prueba: guarda el archivo en lugar de abrir la del
/// sistema.
final class _Sharer implements FileSharer {
  final List<DataExport> shared = [];

  @override
  Future<VoidResult> share(DataExport file) async {
    shared.add(file);
    return const Ok(null);
  }
}

void main() {
  testWidgets('descargar mis datos: el archivo trae lo propio y nada de '
      'otras personas', (tester) async {
    final sharer = _Sharer();
    final app = await E2EApp.start(tester, fileSharer: sharer);
    await app.completeOnboarding(tester);
    await app.signUp(tester, name: 'Ana', email: 'ana@example.com');
    await app.createFamily(tester, 'Familia Prueba');
    final store = app.composition.demoStore!;
    final familyId = store.serverList('families').single.split('/').last;

    // Un check-in propio desde la app.
    GoRouter.of(tester.element(find.byType(NavigationBar)))
        .push(AppRoutes.checkIn)
        .ignore();
    await app.waitFor(tester, find.text('Estoy bien'));
    await app.tapText(tester, 'Estoy bien');
    await app.tapText(tester, 'Enviar');
    await app.waitFor(tester, find.text('Enviado a tu familia'));

    // Datos sintéticos de otra persona en la misma familia.
    store.serverWrite('families/$familyId/events/ajeno', {
      'type': 'checkIn',
      'actorUid': 'otra-persona',
      'kind': 'needHelp',
      'message': 'Mensaje ajeno',
    });

    GoRouter.of(tester.element(find.text('Enviado a tu familia')))
        .go(AppRoutes.account);
    await app.waitFor(tester, find.text('Correo de la cuenta'));
    await tester.scrollUntilVisible(
      find.text('Descargar mis datos'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await app.tapText(tester, 'Descargar mis datos');
    await app.settle(tester);

    final file = sharer.shared.single;
    expect(file.fileName, startsWith('nexo-familia-mis-datos-'));
    final json = jsonDecode(file.contents) as Map<String, Object?>;
    expect(json['schema'], 'nexo-familia/export@1');
    final data = json['data']! as Map<String, Object?>;
    expect((data['account']! as Map)['email'], 'ana@example.com');
    final events = (data['events']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(events.where((e) => e['type'] == 'checkIn').map((e) => e['kind']), [
      'ok',
    ]);
    expect(file.contents, isNot(contains('Mensaje ajeno')));
    expect(file.contents, isNot(contains('otra-persona')));
    await app.stop(tester);
  });
}
