import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (la de `FakeClock`).
final DateTime testNow = DateTime.utc(2026, 1, 1, 12);

const String familyId = 'f1';
const String myUid = 'ana';

const testConfig = AppConfig(
  appName: 'Nexo Familia',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
);

/// Valor observable para los dobles: emite el actual al suscribirse y cada
/// cambio después.
final class Observable<T> {
  new(this._value);

  T _value;
  final StreamController<T> _changes = StreamController.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    _changes.add(next);
  }

  Stream<T> get stream => Stream.multi((controller) {
    controller.add(_value);
    final sub = _changes.stream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
}

final class FakeLocationRepository implements LocationRepository {
  new({
    List<MemberLocation> locations = const [],
    SharingState state = SharingState.sharing,
    LocationPrecision precision = LocationPrecision.exact,
  }) : locations = Observable(locations),
       consent = Observable(
         SharingConsent(
           familyId: familyId,
           uid: myUid,
           state: state,
           precision: precision,
         ),
       );

  final Observable<List<MemberLocation>> locations;
  final Observable<SharingConsent> consent;
  final List<MemberLocation> published = [];
  VoidResult publishResult = const Ok(null);

  /// Si no es null, el envío espera a que se complete (para ver "enviando").
  Completer<void>? publishGate;

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) =>
      locations.stream;

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) => consent.stream;

  @override
  Future<VoidResult> updateConsent(SharingConsent consent) async =>
      const Ok(null);

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) async {
    await publishGate?.future;
    published.add(location);
    return publishResult;
  }
}

final class FakeDeviceLocation implements DeviceLocationService {
  new({
    this.current = DeviceLocationPermission.whileInUse,
    this.afterRequest = DeviceLocationPermission.whileInUse,
  });

  DeviceLocationPermission current;
  DeviceLocationPermission afterRequest;
  Result<DeviceFix>? fix;
  bool settingsResult = true;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<DeviceLocationPermission> permission() async => current;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<Result<DeviceFix>> currentFix() async =>
      fix ??
      Ok(
        DeviceFix(
          point: GeoPoint(4.6123, -74.0712),
          accuracyMeters: 10,
          capturedAt: testNow,
        ),
      );

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return settingsResult;
  }
}

FamilyMember member(String uid, String name, [MemberRole? role]) =>
    FamilyMember(
      uid: uid,
      familyId: familyId,
      displayName: name,
      role: role ?? MemberRole.member,
      joinedAt: DateTime.utc(2025),
    );

/// Ubicación sintética de [uid] tomada hace [age].
MemberLocation locationOf(
  String uid,
  Duration age, {
  bool approximate = false,
}) => MemberLocation(
  uid: uid,
  point: approximate ? GeoPoint(4.62, -74.07) : GeoPoint(4.6015, -74.0662),
  accuracyMeters: approximate ? 1000 : 12,
  capturedAt: testNow.subtract(age),
  receivedAt: testNow.subtract(age),
  isApproximate: approximate,
);

Geofence zone(String id, String name, {double radius = 200}) => Geofence(
  id: id,
  familyId: familyId,
  name: name,
  center: GeoPoint(4.6, -74.07),
  radiusMeters: radius,
  createdBy: myUid,
  version: 1,
  updatedAt: testNow,
);

/// Familia de ejemplo: Ana (yo), Luis (reciente), Marta (sin actualización
/// reciente) y Sofía (aproximada).
final List<FamilyMember> sampleMembers = [
  member(myUid, 'Ana Rojas', MemberRole.owner),
  member('luis', 'Luis'),
  member('marta', 'Marta'),
  member('sofia', 'Sofía'),
];

List<MemberLocation> sampleLocations() => [
  locationOf('luis', const Duration(minutes: 3)),
  locationOf('marta', const Duration(hours: 3)),
  locationOf('sofia', const Duration(minutes: 10), approximate: true),
];

/// Sobrescrituras para mostrar las pantallas de ubicación con dobles.
List<Override> locationOverrides({
  required FakeLocationRepository repository,
  required FakeDeviceLocation device,
  List<FamilyMember>? members,
  List<Geofence> zones = const [],
  MemberRole myRole = MemberRole.owner,
  SyncStatus sync = SyncStatus.live,
  String? activeFamilyId = familyId,
  Stream<List<Geofence>>? zonesStream,
}) => [
  appConfigProvider.overrideWithValue(testConfig),
  clockProvider.overrideWithValue(FakeClock(testNow)),
  activeFamilyIdProvider.overrideWithValue(activeFamilyId),
  currentUserProvider.overrideWith(
    (ref) => Stream.value(
      const AuthUser(uid: myUid, email: 'ana@example.com', displayName: 'Ana'),
    ),
  ),
  myFamiliesProvider.overrideWith(
    (ref) => Stream.value([
      FamilyGroup(
        id: familyId,
        name: 'Familia Rojas',
        myRole: myRole,
        joinedAt: DateTime.utc(2025),
      ),
    ]),
  ),
  familyMembersProvider.overrideWith(
    (ref, id) => Stream.value(members ?? sampleMembers),
  ),
  geofencesProvider.overrideWith(
    (ref, id) => zonesStream ?? Stream.value(zones),
  ),
  syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
  locationRepositoryProvider.overrideWithValue(repository),
  deviceLocationServiceProvider.overrideWithValue(device),
];

/// Monta [home] en `/map` con rutas mínimas para comprobar la navegación.
Widget locationTestApp({
  required List<Override> overrides,
  required Widget home,
  ThemeData? theme,
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.map,
    routes: [
      GoRoute(
        path: AppRoutes.map,
        builder: (_, _) => home,
        routes: [
          GoRoute(
            path: 'zones/new',
            builder: (_, _) => const Scaffold(body: Text('ruta: nueva zona')),
          ),
          GoRoute(
            path: 'zones/:id',
            builder: (_, state) => Scaffold(
              body: Text('ruta: zona ${state.pathParameters['id']}'),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (_, _) => const Scaffold(body: Text('ruta: privacidad')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    // Sin reintentos automáticos: las pruebas son deterministas.
    retry: (_, _) => null,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: theme ?? NxTheme.light(),
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

/// Deja avanzar flujos y animaciones sin `pumpAndSettle` (hay indicadores
/// indeterminados).
Future<void> settle(WidgetTester tester, {int frames = 6}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const Failure networkFailure = Failure.network();
