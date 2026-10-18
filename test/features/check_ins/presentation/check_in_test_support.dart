import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_providers.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_screen.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/service_status/domain/service_status.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (UTC).
final DateTime testNow = DateTime.utc(2026, 10, 15, 15, 30);

const String familyId = 'fam-1';
const AuthUser me = AuthUser(uid: 'ana', email: 'ana@example.com');

/// Coordenada sintética (no corresponde a ninguna persona).
final GeoPoint syntheticPoint = GeoPoint(4.6283, -74.0652);

AppLocalizations get esL10n => lookupAppLocalizations(const Locale('es'));

CheckIn sampleCheckIn({
  String id = 'prev-1',
  CheckInKind kind = CheckInKind.ok,
  DeliveryState delivery = DeliveryState.pending,
  String? message,
  Duration age = const Duration(minutes: 12),
}) => CheckIn(
  id: id,
  familyId: familyId,
  uid: me.uid,
  kind: kind,
  createdAt: testNow.subtract(age),
  delivery: delivery,
  message: message,
);

CheckIn _withDelivery(CheckIn c, DeliveryState delivery) => CheckIn(
  id: c.id,
  familyId: c.familyId,
  uid: c.uid,
  kind: c.kind,
  createdAt: c.createdAt,
  delivery: delivery,
  message: c.message,
  location: c.location,
);

/// Doble del repositorio: una bandeja en memoria que la prueba controla
/// (entregar, hacer fallar…).
final class FakeCheckInRepository implements CheckInRepository {
  new([List<CheckIn> pending = const []]) : _items = [...pending];

  List<CheckIn> _items;
  final _changes = StreamController<List<CheckIn>>.broadcast();

  final List<CheckIn> submitted = [];
  final List<String> retried = [];
  final List<String> discarded = [];

  /// Si es falso, lo enviado nunca aparece en la lista (p. ej. porque se
  /// entregó antes de que la lista lo reflejara).
  bool enqueueOnSubmit = true;

  Failure? submitFailure;
  Failure? retryFailure;
  Completer<void>? submitGate;

  List<CheckIn> get items => List.unmodifiable(_items);

  void _emit(List<CheckIn> next) {
    _items = next;
    _changes.add(List.unmodifiable(next));
  }

  /// El servidor confirmó: sale de la bandeja.
  void deliver(String id) => _emit([
    for (final c in _items)
      if (c.id != id) c,
  ]);

  /// El servidor lo rechazó de forma permanente.
  void fail(String id) => _setDelivery(id, DeliveryState.failed);

  void _setDelivery(String id, DeliveryState delivery) => _emit([
    for (final c in _items)
      _withDelivery(c, c.id == id ? delivery : c.delivery),
  ]);

  @override
  Future<Result<CheckIn>> submit(CheckIn checkIn) async {
    submitted.add(checkIn);
    if (submitGate case final gate?) await gate.future;
    if (submitFailure case final failure?) return Err(failure);
    final saved = _withDelivery(checkIn, DeliveryState.pending);
    if (enqueueOnSubmit) _emit([..._items, saved]);
    return Ok(saved);
  }

  @override
  Stream<List<CheckIn>> watchPending(String familyId) =>
      Stream.multi((controller) {
        controller.add(List.unmodifiable(_items));
        final sub = _changes.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
      });

  Future<VoidResult> retry(String id) async {
    retried.add(id);
    if (retryFailure case final failure?) return Err(failure);
    _setDelivery(id, DeliveryState.pending);
    return const Ok(null);
  }

  Future<VoidResult> discard(String id) async {
    discarded.add(id);
    _emit([
      for (final c in _items)
        if (c.id != id) c,
    ]);
    return const Ok(null);
  }
}

/// GPS del dispositivo con una lectura fija.
final class FakeDeviceLocation implements DeviceLocationService {
  new({this.fix, this.granted = true});

  DeviceFix? fix;
  bool granted;
  int fixCalls = 0;

  @override
  Future<DeviceLocationPermission> permission() async => granted
      ? DeviceLocationPermission.whileInUse
      : DeviceLocationPermission.denied;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() => permission();

  @override
  Future<Result<DeviceFix>> currentFix() async {
    fixCalls++;
    return switch (fix) {
      final fix? => Ok(fix),
      null => const Err(Failure.unavailable('location-unavailable')),
    };
  }

  @override
  Future<bool> openSystemSettings() async => false;
}

final class CheckInTestEnv {
  new({
    FakeCheckInRepository? repository,
    FakeDeviceLocation? device,
    this.sharing = SharingState.sharing,
    this.precision = LocationPrecision.exact,
    this.syncStatus = SyncStatus.live,
    this.activeFamilyId = familyId,
    this.serviceFlags = ServiceFlags.defaults,
  }) : repository = repository ?? FakeCheckInRepository(),
       device =
           device ??
           FakeDeviceLocation(
             fix: DeviceFix(
               point: syntheticPoint,
               accuracyMeters: 15,
               capturedAt: testNow,
             ),
           ),
       clock = FakeClock(testNow);

  final FakeCheckInRepository repository;
  final FakeDeviceLocation device;
  final SharingState sharing;
  final LocationPrecision precision;
  final SyncStatus syncStatus;
  final String? activeFamilyId;
  final ServiceFlags serviceFlags;
  final FakeClock clock;

  SharingConsent get consent => SharingConsent(
    familyId: familyId,
    uid: me.uid,
    state: sharing,
    precision: precision,
  );

  List<Override> get overrides => [
    appConfigProvider.overrideWithValue(
      const AppConfig(
        appName: 'Nexo Familia',
        environment: AppEnvironment.dev,
        backend: BackendMode.demo,
        useFirebaseEmulators: false,
        emergencyNumber: '123',
      ),
    ),
    clockProvider.overrideWithValue(clock),
    idGeneratorProvider.overrideWithValue(SequentialIdGenerator()),
    loggerProvider.overrideWithValue(
      SafeLogger(sink: MemoryLogSink(), clock: clock),
    ),
    activeFamilyIdProvider.overrideWithValue(activeFamilyId),
    currentUserProvider.overrideWith((ref) => Stream.value(me)),
    syncStatusProvider.overrideWith((ref) => Stream.value(syncStatus)),
    checkInRepositoryProvider.overrideWithValue(repository),
    retryCheckInProvider.overrideWithValue(repository.retry),
    discardCheckInProvider.overrideWithValue(repository.discard),
    myConsentProvider.overrideWith((ref, id) => Stream.value(consent)),
    currentServiceFlagsProvider.overrideWithValue(serviceFlags),
    resolveShareableLocationProvider.overrideWithValue(
      ResolveShareableLocation(device),
    ),
  ];
}

/// Destino de navegación fuera de la funcionalidad.
class StubScreen extends StatelessWidget {
  const new(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:$path')));
}

/// Monta la pantalla de check-in con tema, idioma y escala de texto
/// configurables, en una pantalla de 390 × 844.
Future<void> pumpCheckInScreen(
  WidgetTester tester,
  CheckInTestEnv env, {
  ThemeData? theme,
  double textScale = 1,
  Locale locale = const Locale('es'),
}) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.checkIn,
    routes: [
      GoRoute(
        path: AppRoutes.checkIn,
        builder: (_, _) => const CheckInScreen(),
      ),
      for (final path in [AppRoutes.home, AppRoutes.sos, AppRoutes.familySetup])
        GoRoute(path: path, builder: (_, _) => StubScreen(path)),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: env.overrides,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme ?? NxTheme.light(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es'), Locale('en')],
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await pumpFrames(tester);
}

/// Avanza varios fotogramas sin `pumpAndSettle` (los indicadores de
/// progreso indeterminados nunca se asientan).
Future<void> pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Desplaza el contenido hasta que [finder] sea visible (lo que queda
/// fuera de la pantalla no se construye: las listas son perezosas).
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// Desplaza hasta que [finder] sea visible y lo toca.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await pumpFrames(tester);
}
