import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_providers.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/home/presentation/home_screen.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (UTC; el entorno de pruebas usa UTC).
final DateTime testNow = DateTime.utc(2026, 3, 10, 14, 30);

const String familyId = 'f1';
const String myUid = 'ana';

AppConfig testConfig() => const AppConfig(
  appName: 'Nexo Familia',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
);

FamilyMember member(String uid, String name, [MemberRole? role]) =>
    FamilyMember(
      uid: uid,
      familyId: familyId,
      displayName: name,
      role: role ?? MemberRole.member,
      joinedAt: DateTime.utc(2025),
    );

/// Integrantes sintéticos.
final List<FamilyMember> sampleMembers = [
  member(myUid, 'Ana Rojas', MemberRole.owner),
  member('luis', 'Luis'),
  member('marta', 'Marta'),
  member('sofia', 'Sofía'),
];

/// Ubicación sintética (punto de ejemplo, no de una persona real).
MemberLocation locationOf(
  String uid, {
  required Duration age,
  bool approximate = false,
}) {
  final at = testNow.subtract(age);
  return MemberLocation(
    uid: uid,
    point: GeoPoint(4.6, -74.08),
    accuracyMeters: 20,
    capturedAt: at,
    receivedAt: at,
    isApproximate: approximate,
  );
}

/// Ana comparte (reciente), Luis reciente, Marta sin actualización, Sofía no
/// comparte.
final List<MemberLocation> sampleLocations = [
  locationOf(myUid, age: const Duration(minutes: 1)),
  locationOf('luis', age: const Duration(minutes: 3)),
  locationOf('marta', age: const Duration(hours: 2)),
];

EmergencyAlert alertOf({
  String id = 'sos-1',
  String uid = 'luis',
  Duration age = const Duration(minutes: 2),
  DateTime? resolvedAt,
}) => EmergencyAlert(
  id: id,
  familyId: familyId,
  uid: uid,
  createdAt: testNow.subtract(age),
  delivery: SosDelivery.sent,
  location: GeoPoint(4.6, -74.08),
  locationAccuracyMeters: 20,
  notifiedCount: 2,
  resolvedAt: resolvedAt,
);

CheckIn pendingCheckIn(
  String id, {
  DeliveryState delivery = DeliveryState.pending,
}) => CheckIn(
  id: id,
  familyId: familyId,
  uid: myUid,
  kind: CheckInKind.ok,
  createdAt: testNow.subtract(const Duration(minutes: 5)),
  delivery: delivery,
);

/// Repositorio de emergencias que registra si alguien intentó crear una
/// alerta (Inicio nunca debe hacerlo).
final class RecordingEmergencyRepository implements EmergencyRepository {
  final List<EmergencyAlert> raised = [];
  final List<String> acknowledged = [];

  @override
  Future<Result<EmergencyAlert>> raise(EmergencyAlert alert) async {
    raised.add(alert);
    return Ok(alert);
  }

  @override
  Stream<List<EmergencyAlert>> watchAlerts(String familyId) =>
      Stream.value(const []);

  @override
  Future<VoidResult> acknowledge(String familyId, String alertId) async {
    acknowledged.add(alertId);
    return const Ok(null);
  }

  @override
  Future<VoidResult> resolve(String familyId, String alertId) async =>
      const Ok(null);

  @override
  Future<VoidResult> retry(String alertId) async => const Ok(null);
}

/// Sobrescrituras de Inicio. Las ubicaciones o integrantes con `error` dan
/// un `Stream` que falla; con `never`, uno que no emite (cargando).
List<Override> homeOverrides({
  FakeClock? clock,
  String? activeFamilyId = familyId,
  String? displayName = 'Ana',
  List<FamilyMember>? members,
  Object? membersError,
  bool membersLoading = false,
  List<MemberLocation>? locations,
  Object? locationsError,
  List<EmergencyAlert> alerts = const [],
  List<CheckIn> pending = const [],
  SyncStatus sync = SyncStatus.live,
  SharingState sharing = SharingState.sharing,
  RecordingEmergencyRepository? emergency,
}) {
  final now = clock ?? FakeClock(testNow);
  return [
    appConfigProvider.overrideWithValue(testConfig()),
    clockProvider.overrideWithValue(now),
    activeFamilyIdProvider.overrideWithValue(activeFamilyId),
    currentUserProvider.overrideWith(
      (ref) => Stream.value(
        AuthUser(
          uid: myUid,
          email: 'ana@example.com',
          displayName: displayName,
        ),
      ),
    ),
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
      (ref, id) => membersError != null
          ? Stream.error(membersError)
          : membersLoading
          ? const Stream.empty()
          : Stream.value(members ?? sampleMembers),
    ),
    familyLocationsProvider.overrideWith(
      (ref, id) => locationsError != null
          ? Stream.error(locationsError)
          : Stream.value(locations ?? sampleLocations),
    ),
    myConsentProvider.overrideWith(
      (ref, id) => Stream.value(
        SharingConsent(
          familyId: id,
          uid: myUid,
          state: sharing,
          precision: LocationPrecision.exact,
        ),
      ),
    ),
    emergencyAlertsProvider.overrideWith((ref, id) => Stream.value(alerts)),
    emergencyRepositoryProvider.overrideWithValue(
      emergency ?? RecordingEmergencyRepository(),
    ),
    pendingCheckInsProvider.overrideWith((ref, id) => Stream.value(pending)),
    syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
  ];
}

/// Rutas de destino de Inicio, sustituidas por marcadores.
const List<String> stubRoutes = [
  AppRoutes.checkIn,
  AppRoutes.sos,
  AppRoutes.invite,
  AppRoutes.privacy,
  AppRoutes.familySetup,
  '/family/members/:uid',
];

/// App de prueba con enrutador: [start] es la pantalla inicial y cada ruta
/// de [stubRoutes] muestra `ruta:<ubicación>`.
Widget routedTestApp({
  required List<Override> overrides,
  required Widget start,
  String startPath = AppRoutes.home,
  ThemeData? theme,
  double textScale = 1,
}) {
  final router = GoRouter(
    initialLocation: startPath,
    routes: [
      GoRoute(path: startPath, builder: (_, _) => start),
      for (final path in stubRoutes)
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text('ruta:${state.uri.path}')),
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

Widget homeTestApp({
  required List<Override> overrides,
  ThemeData? theme,
  double textScale = 1,
}) => routedTestApp(
  overrides: overrides,
  start: const HomeScreen(),
  theme: theme,
  textScale: textScale,
);

/// Deja avanzar flujos sin `pumpAndSettle` (hay indicadores indeterminados).
Future<void> settle(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Frases que la app nunca debe mostrar: afirman algo que no puede saber.
final RegExp forbiddenClaims = RegExp(
  r'a salvo|segur[oa]s?\b|todos bien|está bien|recibid|ayuda en camino',
  caseSensitive: false,
);

/// Concatenación de los textos visibles.
String visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');
