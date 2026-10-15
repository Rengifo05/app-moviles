import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_screen.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (UTC).
final DateTime testNow = DateTime.utc(2026, 10, 15, 15, 30);

const String familyId = 'fam-1';

/// Centro sintético en el océano Atlántico sur (no es el lugar de nadie).
final GeoPoint syntheticCenter = GeoPoint(-40, -30);

/// Otro punto sintético cercano, para elegir en el mapa de prueba.
final GeoPoint syntheticPicked = GeoPoint(-40.002, -30.003);

AppLocalizations get esL10n => lookupAppLocalizations(const Locale('es'));

/// Zona sintética guardada.
Geofence sampleZone({
  String id = 'z1',
  String name = 'Casa',
  double radiusMeters = 300,
  int version = 2,
  Duration age = const Duration(days: 3),
}) => Geofence(
  id: id,
  familyId: familyId,
  name: name,
  center: syntheticCenter,
  radiusMeters: radiusMeters,
  createdBy: 'marta',
  version: version,
  updatedAt: testNow.subtract(age),
);

/// Flujo con un valor actual que se puede cambiar desde la prueba.
final class ValueStream<T> {
  new(this._value);

  T _value;
  final _changes = StreamController<T>.broadcast();

  T get value => _value;

  set value(T next) {
    _value = next;
    _changes.add(next);
  }

  Stream<T> stream() async* {
    yield _value;
    yield* _changes.stream;
  }
}

typedef CreateCall = ({
  String familyId,
  String name,
  GeoPoint center,
  double radiusMeters,
});

final class FakeGeofenceRepository implements GeofenceRepository {
  new([List<Geofence> zones = const []]) : zones = ValueStream(zones);

  final ValueStream<List<Geofence>> zones;

  final List<CreateCall> createCalls = [];
  final List<Geofence> updateCalls = [];
  final List<Geofence> deleteCalls = [];

  /// Respuestas programadas (por defecto, éxito).
  Result<Geofence>? createResult;
  Result<Geofence>? updateResult;
  VoidResult deleteResult = const Ok(null);

  /// Si no es nulo, las operaciones esperan a que se complete.
  Completer<void>? gate;

  @override
  Stream<List<Geofence>> watchGeofences(String familyId) => zones.stream();

  @override
  Future<Result<Geofence>> create({
    required String familyId,
    required String name,
    required GeoPoint center,
    required double radiusMeters,
  }) async {
    createCalls.add((
      familyId: familyId,
      name: name,
      center: center,
      radiusMeters: radiusMeters,
    ));
    await gate?.future;
    return createResult ??
        Ok(
          Geofence(
            id: 'new-zone',
            familyId: familyId,
            name: name,
            center: center,
            radiusMeters: radiusMeters,
            createdBy: 'ana',
            version: 1,
            updatedAt: testNow,
          ),
        );
  }

  @override
  Future<Result<Geofence>> update(Geofence updated) async {
    updateCalls.add(updated);
    await gate?.future;
    return updateResult ?? Ok(updated);
  }

  @override
  Future<VoidResult> delete(Geofence geofence) async {
    deleteCalls.add(geofence);
    await gate?.future;
    return deleteResult;
  }
}

/// Ubicación del teléfono simulada. Por defecto con permiso concedido y una
/// lectura de ±12 m.
final class FakeDeviceLocationService implements DeviceLocationService {
  new({
    this.permissionState = DeviceLocationPermission.whileInUse,
    this.onRequest = DeviceLocationPermission.whileInUse,
    Result<DeviceFix>? fix,
  }) : fix = fix ?? Ok(sampleFix());

  DeviceLocationPermission permissionState;

  /// Estado que adopta el permiso al pedirlo (si aún se puede pedir).
  DeviceLocationPermission onRequest;
  Result<DeviceFix> fix;

  /// Si no es nulo, `currentFix` espera a que se complete.
  Completer<void>? fixGate;
  bool settingsResult = false;
  int requests = 0;
  int fixes = 0;
  int settingsOpened = 0;

  @override
  Future<DeviceLocationPermission> permission() async => permissionState;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async {
    requests++;
    if (permissionState == DeviceLocationPermission.notDetermined ||
        permissionState == DeviceLocationPermission.denied) {
      permissionState = onRequest;
    }
    return permissionState;
  }

  @override
  Future<Result<DeviceFix>> currentFix() async {
    fixes++;
    await fixGate?.future;
    return fix;
  }

  @override
  Future<bool> openSystemSettings() async {
    settingsOpened++;
    return settingsResult;
  }
}

DeviceFix sampleFix({double accuracyMeters = 12}) => DeviceFix(
  point: syntheticCenter,
  accuracyMeters: accuracyMeters,
  capturedAt: testNow,
);

/// Mapa de prueba: un botón que "elige" [syntheticPicked] y un texto con
/// lo que recibió (cuántas zonas y si permite elegir).
Widget fakeMapBuilder(BuildContext context, NxMapData data) => ColoredBox(
  color: const Color(0xFFE0E0E0),
  child: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'map zones=${data.zones.length} '
          'radius=${data.zones.firstOrNull?.radiusMeters.round()} '
          'pick=${data.onPickPoint != null}',
        ),
        if (data.onPickPoint case final pick?)
          TextButton(
            key: const Key('fake-map-pick'),
            onPressed: () => pick(syntheticPicked),
            child: const Text('pick'),
          ),
      ],
    ),
  ),
);

/// Dependencias de una prueba de pantalla.
final class GeofenceTestEnv {
  new({
    FakeGeofenceRepository? repository,
    FakeDeviceLocationService? device,
    this.role = MemberRole.owner,
    this.activeFamilyId = familyId,
    this.syncStatus = SyncStatus.live,
    this.mapBuilder,
  }) : repository = repository ?? FakeGeofenceRepository([sampleZone()]),
       device = device ?? FakeDeviceLocationService(),
       clock = FakeClock(testNow),
       logSink = MemoryLogSink();

  final FakeGeofenceRepository repository;
  final FakeDeviceLocationService device;
  final MemberRole role;
  final String? activeFamilyId;
  final SyncStatus syncStatus;
  final NxMapBuilder? mapBuilder;
  final FakeClock clock;
  final MemoryLogSink logSink;

  List<Override> get overrides => [
    clockProvider.overrideWithValue(clock),
    loggerProvider.overrideWithValue(SafeLogger(sink: logSink, clock: clock)),
    geofenceRepositoryProvider.overrideWithValue(repository),
    deviceLocationServiceProvider.overrideWithValue(device),
    mapBuilderProvider.overrideWithValue(mapBuilder),
    activeFamilyIdProvider.overrideWithValue(activeFamilyId),
    activeFamilyProvider.overrideWithValue(
      AsyncData(
        activeFamilyId == null
            ? null
            : FamilyGroup(
                id: activeFamilyId!,
                name: 'Familia Gómez',
                myRole: role,
                joinedAt: DateTime.utc(2026, 3, 2, 14),
              ),
      ),
    ),
    syncStatusProvider.overrideWith((ref) => Stream.value(syncStatus)),
  ];
}

/// Destino de navegación fuera del editor (el mapa).
class StubScreen extends StatelessWidget {
  const new(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:$path')));
}

GoRouter buildGeofenceTestRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: AppRoutes.map,
      builder: (_, _) => const StubScreen(AppRoutes.map),
      routes: [
        GoRoute(
          path: 'zones/new',
          builder: (_, _) => const GeofenceEditorScreen(),
        ),
        GoRoute(
          path: 'zones/:id',
          builder: (_, state) =>
              GeofenceEditorScreen(geofenceId: state.pathParameters['id']),
        ),
      ],
    ),
  ],
);

/// Monta el editor en [location] con tema, idioma y escala de texto
/// configurables, en una pantalla de 390 × 844 (iPhone 13/14).
Future<GoRouter> pumpGeofenceApp(
  WidgetTester tester,
  GeofenceTestEnv env, {
  String location = AppRoutes.newZone,
  ThemeData? theme,
  double textScale = 1,
  Locale locale = const Locale('es'),
}) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = buildGeofenceTestRouter(location);
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
  return router;
}

/// Avanza varios fotogramas sin `pumpAndSettle` (los indicadores de
/// progreso indeterminados nunca se asientan).
Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Desplaza la página hasta que [finder] quede en pantalla y lo toca.
///
/// Antes de tocar deja terminar los desplazamientos animados (p. ej. el que
/// lleva el cursor de un campo a la vista): mientras duran, la lista ignora
/// los toques.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await pumpFrames(tester, frames: 3);
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await pumpFrames(tester, frames: 3);
  await tester.tap(finder);
  await pumpFrames(tester);
}
