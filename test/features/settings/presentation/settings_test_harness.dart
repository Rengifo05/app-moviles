import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

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

const AuthUser testUser = AuthUser(
  uid: myUid,
  email: 'ana@example.com',
  displayName: 'Ana Rojas',
);

const Failure networkFailure = Failure.network();

/// Valor observable: emite el actual al suscribirse y cada cambio después.
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

/// Repositorio de ubicación falso. Con `Ok`, el consentimiento observado
/// cambia (como haría la caché local tras la escritura); con `Err`, no.
final class FakeLocationRepository implements LocationRepository {
  new({
    SharingState state = SharingState.sharing,
    LocationPrecision precision = LocationPrecision.exact,
  }) : consent = Observable(
         SharingConsent(
           familyId: familyId,
           uid: myUid,
           state: state,
           precision: precision,
         ),
       );

  final Observable<SharingConsent> consent;
  final List<SharingConsent> updates = [];
  VoidResult updateResult = const Ok(null);

  /// Si no es null, la escritura espera a que se complete (para ver el
  /// estado "en curso").
  Completer<void>? gate;

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) => consent.stream;

  @override
  Future<VoidResult> updateConsent(SharingConsent next) async {
    updates.add(next);
    await gate?.future;
    final result = updateResult;
    if (result.isOk) consent.value = next;
    return result;
  }

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) =>
      Stream.value(const []);

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) async => const Ok(null);
}

final class FakeDeviceLocation implements DeviceLocationService {
  new({
    this.current = DeviceLocationPermission.whileInUse,
    this.afterRequest = DeviceLocationPermission.whileInUse,
  });

  DeviceLocationPermission current;
  DeviceLocationPermission afterRequest;
  int requests = 0;
  int settingsOpened = 0;
  bool settingsResult = true;

  @override
  Future<DeviceLocationPermission> permission() async => current;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    requests++;
    return current = afterRequest;
  }

  @override
  Future<Result<DeviceFix>> currentFix() async =>
      const Err(Failure.unavailable('location-unavailable'));

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return settingsResult;
  }
}

final class FakeFamilyRepository implements FamilyRepository {
  VoidResult leaveResult = const Ok(null);
  final List<String> left = [];

  @override
  Future<VoidResult> leaveFamily(String familyId) async {
    left.add(familyId);
    return leaveResult;
  }

  @override
  Stream<List<FamilyGroup>> watchMyFamilies() => Stream.value(const []);

  @override
  Stream<List<FamilyMember>> watchMembers(String familyId) =>
      Stream.value(const []);

  @override
  Future<Result<FamilyGroup>> createFamily(String name) =>
      throw UnimplementedError();

  @override
  Future<Result<CreatedInvitation>> createInvitation(String familyId) =>
      throw UnimplementedError();

  @override
  Future<Result<String>> acceptInvitation(String code) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> removeMember(String familyId, String uid) =>
      throw UnimplementedError();
}

final class FakeAuthRepository implements AuthRepository {
  new([this._user = testUser]);

  final AuthUser? _user;
  VoidResult signOutResult = const Ok(null);
  VoidResult deleteResult = const Ok(null);
  int signOutCalls = 0;
  int deleteCalls = 0;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> watchUser() => Stream.value(_user);

  @override
  Future<VoidResult> signOut() async {
    signOutCalls++;
    return signOutResult;
  }

  @override
  Future<VoidResult> deleteAccount() async {
    deleteCalls++;
    return deleteResult;
  }

  VoidResult signOutEverywhereResult = const Ok(null);
  int signOutEverywhereCalls = 0;

  @override
  Future<VoidResult> signOutEverywhere() async {
    signOutEverywhereCalls++;
    return signOutEverywhereResult;
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<Result<AuthUser>> signUp(SignUpRequest request) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> sendPasswordReset(String email) =>
      throw UnimplementedError();
}

final class FakePreferencesRepository implements PreferencesRepository {
  new([
    AppPreferences initial = const AppPreferences(
      onboardingCompleted: true,
      activeFamilyId: familyId,
    ),
  ]) : prefs = Observable(initial);

  final Observable<AppPreferences> prefs;
  bool failWrites = false;

  @override
  Stream<AppPreferences> watch() => prefs.stream;

  @override
  Future<AppPreferences> read() async => prefs.value;

  @override
  Future<void> update(AppPreferences Function(AppPreferences) change) async {
    if (failWrites) throw StateError('escritura fallida');
    prefs.value = change(prefs.value);
  }

  @override
  Future<void> clear() async => prefs.value = const AppPreferences();
}

FamilyMember member(String uid, String name, [MemberRole? role]) =>
    FamilyMember(
      uid: uid,
      familyId: familyId,
      displayName: name,
      role: role ?? MemberRole.member,
      joinedAt: DateTime.utc(2025),
    );

final List<FamilyMember> sampleMembers = [
  member(myUid, 'Ana Rojas', MemberRole.owner),
  member('luis', 'Luis Rojas', MemberRole.admin),
  member('marta', 'Marta'),
];

/// Dobles agrupados para las pruebas de Ajustes.
final class SettingsFakes {
  new({
    FakeLocationRepository? location,
    FakeDeviceLocation? device,
    FakeAuthRepository? auth,
    FakePreferencesRepository? preferences,
    FakeFamilyRepository? families,
  }) : location = location ?? FakeLocationRepository(),
       device = device ?? FakeDeviceLocation(),
       auth = auth ?? FakeAuthRepository(),
       preferences = preferences ?? FakePreferencesRepository(),
       families = families ?? FakeFamilyRepository();

  final FakeLocationRepository location;
  final FakeDeviceLocation device;
  final FakeAuthRepository auth;
  final FakePreferencesRepository preferences;
  final FakeFamilyRepository families;
  final MemoryLogSink logs = MemoryLogSink();

  List<Override> overrides({
    List<FamilyMember>? members,
    SyncStatus sync = SyncStatus.live,
    String? activeFamilyId = familyId,
    bool pushAvailable = false,
    int? pendingOutbox,
  }) => [
    appConfigProvider.overrideWithValue(testConfig),
    clockProvider.overrideWithValue(FakeClock(testNow)),
    loggerProvider.overrideWithValue(
      SafeLogger(sink: logs, clock: FakeClock(testNow)),
    ),
    activeFamilyIdProvider.overrideWithValue(activeFamilyId),
    authRepositoryProvider.overrideWithValue(auth),
    familyRepositoryProvider.overrideWithValue(families),
    myFamiliesProvider.overrideWith(
      (ref) => Stream.value([
        FamilyGroup(
          id: familyId,
          name: 'Familia Rojas',
          myRole: MemberRole.owner,
          joinedAt: DateTime.utc(2025),
        ),
      ]),
    ),
    familyMembersProvider.overrideWith(
      (ref, id) => Stream.value(members ?? sampleMembers),
    ),
    syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
    locationRepositoryProvider.overrideWithValue(location),
    deviceLocationServiceProvider.overrideWithValue(device),
    preferencesRepositoryProvider.overrideWithValue(preferences),
    pushNotificationsAvailableProvider.overrideWithValue(pushAvailable),
    if (pendingOutbox != null)
      pendingOutboxCountProvider.overrideWith(
        (ref) => Stream.value(pendingOutbox),
      ),
  ];
}

/// Monta [home] en [initialLocation] con rutas mínimas para comprobar la
/// navegación.
Widget settingsTestApp({
  required List<Override> overrides,
  required Widget home,
  String initialLocation = AppRoutes.settings,
  ThemeData? theme,
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => initialLocation == AppRoutes.settings
            ? home
            : const Scaffold(body: Text('ruta: ajustes')),
        routes: [
          GoRoute(
            path: 'privacy',
            builder: (_, _) => initialLocation == AppRoutes.privacy
                ? home
                : const Scaffold(body: Text('ruta: privacidad')),
          ),
          GoRoute(
            path: 'account',
            builder: (_, _) => initialLocation == AppRoutes.account
                ? home
                : const Scaffold(body: Text('ruta: cuenta')),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.map,
        builder: (_, _) => const Scaffold(body: Text('ruta: mapa')),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
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

/// Deja avanzar flujos y animaciones sin `pumpAndSettle` (puede haber
/// indicadores indeterminados).
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Textos localizados en español para las aserciones.
Future<AppLocalizations> spanish() =>
    AppLocalizations.delegate.load(const Locale('es'));
