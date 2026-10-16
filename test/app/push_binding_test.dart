import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/app/push_binding.dart';
import 'package:nexo_familia/app/router.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

import '../features/notifications/push_fakes.dart';
import '../features/settings/presentation/settings_test_harness.dart'
    show FakePreferencesRepository;

const _user = AuthUser(uid: 'ana', email: 'ana@example.com');

final class _Session extends Notifier<SessionState> {
  @override
  SessionState build() => const SignedOut();

  // Solo para la prueba: cambia la sesión observada.
  // ignore: use_setters_to_change_properties
  void set(SessionState next) => state = next;
}

final _sessionState = NotifierProvider<_Session, SessionState>(_Session.new);

void main() {
  late FakePushService service;
  late FakeDeviceRegistry registry;
  late FakePreferencesRepository preferences;
  late GoRouter router;

  setUp(() {
    service = FakePushService();
    registry = FakeDeviceRegistry();
    preferences = FakePreferencesRepository();
    router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Text('ruta: inicio')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('ruta: ajustes')),
        ),
      ],
    );
  });

  tearDown(() => router.dispose());

  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => ref.watch(_sessionState)),
          pushServiceProvider.overrideWithValue(service),
          deviceRegistryProvider.overrideWithValue(registry),
          preferencesRepositoryProvider.overrideWithValue(preferences),
          routerProvider.overrideWithValue(router),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(pushBindingProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(Consumer)));
  }

  testWidgets('registra el teléfono al iniciar sesión y no antes', (
    tester,
  ) async {
    final container = await pump(tester);
    expect(registry.registered, isEmpty);

    container.read(_sessionState.notifier).set(const SessionReady(_user, 'f1'));
    await tester.pumpAndSettle();
    expect(registry.registered, ['token-a']);
  });

  testWidgets('tras un cierre de sesión remoto, la siguiente sesión vuelve a '
      'registrar', (tester) async {
    final container = await pump(tester);
    final session = container.read(_sessionState.notifier)
      ..set(const NeedsFamily(_user));
    await tester.pumpAndSettle();
    session.set(const SignedOut());
    await tester.pumpAndSettle();
    session.set(const SessionReady(_user, 'f1'));
    await tester.pumpAndSettle();
    expect(registry.registered, ['token-a', 'token-a']);
  });

  testWidgets('un token renovado cambia el registro', (tester) async {
    final container = await pump(tester);
    container.read(_sessionState.notifier).set(const SessionReady(_user, 'f1'));
    await tester.pumpAndSettle();
    service.refreshes.add('token-b');
    await tester.pumpAndSettle();
    expect(registry.registered, ['token-a', 'token-b']);
    expect(registry.unregistered, ['token-a']);
  });

  testWidgets('tocar un aviso SOS activa esa familia y abre Inicio', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('ruta: ajustes'), findsOneWidget);
    service.opens.add(const PushOpen(familyId: 'f2', alertId: 'a1'));
    await tester.pumpAndSettle();
    expect(preferences.prefs.value.activeFamilyId, 'f2');
    expect(find.text('ruta: inicio'), findsOneWidget);
  });

  testWidgets('sin servicio de avisos no hace nada', (tester) async {
    service.available = false;
    final container = await pump(tester);
    container.read(_sessionState.notifier).set(const SessionReady(_user, 'f1'));
    await tester.pumpAndSettle();
    service.opens.add(const PushOpen(familyId: 'f2', alertId: 'a1'));
    await tester.pumpAndSettle();
    expect(registry.registered, isEmpty);
    expect(preferences.prefs.value.activeFamilyId, 'f1');
  });
}
