import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/service_status/data/service_status_repository_impl.dart';
import 'package:nexo_familia/features/service_status/domain/service_status.dart';
import 'package:nexo_familia/features/service_status/presentation/service_notice_banner.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import '../../helpers/fakes.dart';

/// Escucha que falla (p. ej., `permission-denied`).
final class _FailingStore implements RemoteStore {
  @override
  Stream<RemoteDoc?> watchDoc(String path) => Stream.error(StateError('x'));

  @override
  Stream<List<RemoteDoc>> watchCollection(String path, {RemoteQuery? query}) =>
      throw UnimplementedError();

  @override
  Future<Result<RemoteDoc?>> getDoc(String path) => throw UnimplementedError();

  @override
  Future<VoidResult> commit(List<RemoteWrite> writes) =>
      throw UnimplementedError();
}

void main() {
  group('ServiceStatusRepositoryImpl', () {
    late InMemoryRemoteStore store;

    setUp(() => store = InMemoryRemoteStore(clock: FakeClock()));
    tearDown(() => store.dispose());

    test('sin documento, todo activo', () async {
      final flags = await ServiceStatusRepositoryImpl(store).watchFlags().first;
      expect(flags, ServiceFlags.defaults);
    });

    test('lee las banderas y sigue sus cambios', () async {
      final seen = <ServiceFlags>[];
      final sub = ServiceStatusRepositoryImpl(store)
          .watchFlags()
          .listen(seen.add);
      await pumpEventQueue();
      store.serverWrite('config/app', {
        'checkInsEnabled': false,
        'notice': 'pushDegraded',
        'minBuild': 7,
      });
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.last.checkInsEnabled, isFalse);
      expect(seen.last.geofenceEditingEnabled, isTrue);
      expect(seen.last.notice, ServiceNotice.pushDegraded);
      expect(seen.last.minBuild, 7);
    });

    test('un documento mal escrito nunca apaga nada', () {
      expect(
        ServiceStatusRepositoryImpl.parse({
          'checkInsEnabled': 'false',
          'geofenceEditingEnabled': 0,
          'notice': 'texto libre del servidor',
          'minBuild': -3,
        }),
        ServiceFlags.defaults,
      );
    });

    test('si la escucha falla, valores por defecto', () async {
      expect(
        await ServiceStatusRepositoryImpl(_FailingStore()).watchFlags().first,
        ServiceFlags.defaults,
      );
    });
  });

  test('recomienda actualizar solo si la compilación es anterior', () {
    const flags = ServiceFlags(minBuild: 5);
    expect(flags.updateRecommended(4), isTrue);
    expect(flags.updateRecommended(5), isFalse);
    expect(flags.updateRecommended(null), isFalse);
    expect(ServiceFlags.defaults.updateRecommended(1), isFalse);
  });

  group('ServiceNoticeBanner', () {
    Future<AppLocalizations> pump(
      WidgetTester tester,
      ServiceFlags flags, {
      int? build,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appConfigProvider.overrideWithValue(
              const AppConfig(
                appName: 'Nexo Familia',
                environment: AppEnvironment.dev,
                backend: BackendMode.demo,
                useFirebaseEmulators: false,
                emergencyNumber: '123',
              ),
            ),
            currentServiceFlagsProvider.overrideWithValue(flags),
            appBuildNumberProvider.overrideWithValue(build),
          ],
          child: MaterialApp(
            theme: NxTheme.light(),
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ServiceNoticeBanner()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return AppLocalizations.of(
        tester.element(find.byType(ServiceNoticeBanner)),
      );
    }

    testWidgets('sin avisos no muestra nada', (tester) async {
      await pump(tester, ServiceFlags.defaults, build: 1);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('el aviso de push recuerda el número de emergencias', (
      tester,
    ) async {
      final l10n = await pump(
        tester,
        const ServiceFlags(notice: ServiceNotice.pushDegraded),
      );
      expect(find.text(l10n.serviceNoticePushDegraded('123')), findsOne);
      expect(find.textContaining('123'), findsOne);
    });

    testWidgets('recomienda actualizar una compilación antigua', (
      tester,
    ) async {
      final l10n = await pump(
        tester,
        const ServiceFlags(notice: ServiceNotice.serviceDegraded, minBuild: 9),
        build: 3,
      );
      expect(find.text(l10n.serviceNoticeDegraded), findsOne);
      expect(find.text(l10n.serviceUpdateRecommended), findsOne);
    });
  });
}
