import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';
import 'package:nexo_familia/features/notifications/presentation/push_prompt_card.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import '../push_fakes.dart';

void main() {
  late FakePushService service;
  late FakeDeviceRegistry registry;

  setUp(() {
    service = FakePushService(current: PushPermission.notDetermined);
    registry = FakeDeviceRegistry();
  });

  Future<AppLocalizations> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushServiceProvider.overrideWithValue(service),
          deviceRegistryProvider.overrideWithValue(registry),
        ],
        child: MaterialApp(
          theme: NxTheme.light(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PushPromptCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(PushPromptCard)));
  }

  testWidgets('explica para qué sirve antes de pedir el permiso', (
    tester,
  ) async {
    final l10n = await pump(tester);
    expect(find.text(l10n.pushPromptMessage), findsOneWidget);
    expect(service.requests, 0);

    await tester.tap(find.text(l10n.pushPromptAction));
    await tester.pumpAndSettle();

    expect(service.requests, 1);
    expect(registry.registered, ['token-a']);
    // Concedido: la tarjeta ya no ocupa espacio.
    expect(find.text(l10n.pushPromptMessage), findsNothing);
  });

  testWidgets('si se deniega lo dice y no registra nada', (tester) async {
    service.afterRequest = PushPermission.denied;
    final l10n = await pump(tester);
    await tester.tap(find.text(l10n.pushPromptAction));
    await tester.pumpAndSettle();

    expect(registry.registered, isEmpty);
    expect(find.text(l10n.pushDeniedMessage), findsOneWidget);
    expect(find.text(l10n.pushPromptAction), findsNothing);
  });

  testWidgets('con el permiso concedido no muestra nada', (tester) async {
    service.current = PushPermission.granted;
    final l10n = await pump(tester);
    expect(find.text(l10n.pushPromptMessage), findsNothing);
    expect(find.text(l10n.pushDeniedMessage), findsNothing);
  });

  testWidgets('sin servicio de avisos no muestra nada', (tester) async {
    service.available = false;
    final l10n = await pump(tester);
    expect(find.text(l10n.pushPromptMessage), findsNothing);
    expect(find.text(l10n.pushDeniedMessage), findsNothing);
  });

  testWidgets('cumple las guías de accesibilidad', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
