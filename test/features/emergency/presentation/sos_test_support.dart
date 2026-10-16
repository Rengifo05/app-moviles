import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/config/app_config.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/emergency_dialer.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (UTC; el entorno de pruebas usa UTC).
final DateTime testNow = DateTime.utc(2026, 3, 10, 14, 30);

const String familyId = 'f1';
const String myUid = 'ana';

AppConfig testConfig({String emergencyNumber = '123'}) => AppConfig(
  appName: 'Nexo Familia',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: emergencyNumber,
);

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

/// Repositorio en memoria que registra las llamadas.
final class FakeEmergencyRepository implements EmergencyRepository {
  new([List<EmergencyAlert> initial = const []])
    : alerts = Observable(List.of(initial));

  final Observable<List<EmergencyAlert>> alerts;
  final List<EmergencyAlert> raised = [];
  final List<String> acknowledged = [];
  final List<String> resolved = [];
  final List<String> retried = [];

  /// Si no es null, `raise` devuelve esto sin guardar nada.
  Result<EmergencyAlert>? raiseResult;
  VoidResult ackResult = const Ok(null);
  VoidResult resolveResult = const Ok(null);
  VoidResult retryResult = const Ok(null);

  @override
  Future<Result<EmergencyAlert>> raise(EmergencyAlert alert) async {
    raised.add(alert);
    if (raiseResult case final result?) return result;
    final queued = EmergencyAlert(
      id: alert.id,
      familyId: alert.familyId,
      uid: alert.uid,
      createdAt: alert.createdAt,
      delivery: SosDelivery.queued,
      location: alert.location,
      locationAccuracyMeters: alert.locationAccuracyMeters,
    );
    alerts.value = [
      queued,
      for (final a in alerts.value)
        if (a.id != alert.id) a,
    ];
    return Ok(queued);
  }

  @override
  Stream<List<EmergencyAlert>> watchAlerts(String familyId) => alerts.stream;

  @override
  Future<VoidResult> acknowledge(String familyId, String alertId) async {
    acknowledged.add(alertId);
    return ackResult;
  }

  @override
  Future<VoidResult> resolve(String familyId, String alertId) async {
    resolved.add(alertId);
    // Como el repositorio real: cancelar una sin confirmar la quita de la
    // bandeja (deja de verse).
    if (resolveResult.isOk) {
      alerts.value = [
        for (final a in alerts.value)
          if (a.id != alertId || a.delivery == SosDelivery.sent) a,
      ];
    }
    return resolveResult;
  }

  @override
  Future<VoidResult> retry(String alertId) async {
    retried.add(alertId);
    return retryResult;
  }

  /// Sustituye (o añade) una alerta, como si llegara de la caché.
  void put(EmergencyAlert alert) => alerts.value = [
    alert,
    for (final a in alerts.value)
      if (a.id != alert.id) a,
  ];
}

final class FakeDialer implements EmergencyDialer {
  bool opens = true;
  final List<String> numbers = [];

  @override
  Future<bool> dial(String number) async {
    numbers.add(number);
    return opens;
  }
}

/// GPS sintético (coordenadas de ejemplo, no de personas reales).
final class FakeDevice implements DeviceLocationService {
  DeviceLocationPermission current = DeviceLocationPermission.whileInUse;

  @override
  Future<DeviceLocationPermission> permission() async => current;

  @override
  Future<DeviceLocationPermission> requestWhileInUse() async => current;

  @override
  Future<Result<DeviceFix>> currentFix() async => Ok(
    DeviceFix(
      point: GeoPoint(4.6097, -74.0817),
      accuracyMeters: 15,
      capturedAt: testNow,
    ),
  );

  @override
  Future<bool> openSystemSettings() async => true;
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
  member('luis', 'Luis'),
  member('marta', 'Marta'),
];

/// Alerta de ejemplo (por defecto, mía y registrada hace 2 minutos).
EmergencyAlert alertOf({
  String id = 'sos-1',
  String uid = myUid,
  SosDelivery delivery = SosDelivery.sent,
  int? notifiedCount,
  List<EmergencyAck> acks = const [],
  DateTime? resolvedAt,
  String? failureCode,
  bool withLocation = true,
  Duration age = const Duration(minutes: 2),
}) => EmergencyAlert(
  id: id,
  familyId: familyId,
  uid: uid,
  createdAt: testNow.subtract(age),
  delivery: delivery,
  location: withLocation ? GeoPoint(4.6097, -74.0817) : null,
  locationAccuracyMeters: withLocation ? 15 : null,
  notifiedCount: notifiedCount,
  acks: acks,
  resolvedAt: resolvedAt,
  failureCode: failureCode,
);

/// Sobrescrituras de la pantalla SOS con dobles.
List<Override> sosOverrides({
  required FakeEmergencyRepository repository,
  required FakeClock clock,
  FakeDialer? dialer,
  FakeDevice? device,
  String emergencyNumber = '123',
  SharingState sharing = SharingState.sharing,
  LocationPrecision precision = LocationPrecision.exact,
  SyncStatus sync = SyncStatus.live,
  String? activeFamilyId = familyId,
  List<FamilyMember>? members,
}) => [
  appConfigProvider.overrideWithValue(
    testConfig(emergencyNumber: emergencyNumber),
  ),
  clockProvider.overrideWithValue(clock),
  idGeneratorProvider.overrideWithValue(SequentialIdGenerator()),
  loggerProvider.overrideWithValue(
    SafeLogger(sink: MemoryLogSink(), clock: clock),
  ),
  activeFamilyIdProvider.overrideWithValue(activeFamilyId),
  currentUserProvider.overrideWith(
    (ref) => Stream.value(
      const AuthUser(uid: myUid, email: 'ana@example.com', displayName: 'Ana'),
    ),
  ),
  familyMembersProvider.overrideWith(
    (ref, id) => Stream.value(members ?? sampleMembers),
  ),
  myConsentProvider.overrideWith(
    (ref, id) => Stream.value(
      SharingConsent(
        familyId: id,
        uid: myUid,
        state: sharing,
        precision: precision,
      ),
    ),
  ),
  resolveShareableLocationProvider.overrideWithValue(
    ResolveShareableLocation(device ?? FakeDevice()),
  ),
  syncStatusProvider.overrideWith((ref) => Stream.value(sync)),
  emergencyRepositoryProvider.overrideWithValue(repository),
  emergencyDialerProvider.overrideWithValue(dialer ?? FakeDialer()),
];

Widget sosTestApp({
  required List<Override> overrides,
  required Widget home,
  ThemeData? theme,
  double textScale = 1,
}) => ProviderScope(
  overrides: overrides,
  // Sin reintentos automáticos: las pruebas son deterministas.
  retry: (_, _) => null,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme ?? NxTheme.light(),
    locale: const Locale('es'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
  ),
);

/// Avanza a la vez el reloj de la app y el tiempo de las pruebas (los
/// temporizadores), en pasos cortos.
Future<void> elapse(
  WidgetTester tester,
  FakeClock clock,
  Duration duration, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var left = duration;
  while (left > Duration.zero) {
    final next = left < step ? left : step;
    clock.advance(next);
    await tester.pump(next);
    left -= next;
  }
}

/// Deja avanzar flujos sin `pumpAndSettle` (hay indicadores indeterminados).
Future<void> settle(WidgetTester tester, {int frames = 5}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Mantiene pulsado el botón SOS el tiempo indicado y lo suelta.
Future<void> holdSos(
  WidgetTester tester,
  FakeClock clock, {
  Duration duration = const Duration(milliseconds: 2400),
}) async {
  final gesture = await tester.startGesture(tester.getCenter(holdButtonLabel));
  await elapse(tester, clock, duration);
  await gesture.up();
  await tester.pump();
}

/// Etiqueta "SOS" dentro del botón de mantener pulsado (la barra superior
/// también dice "SOS").
Finder get holdButtonLabel =>
    find.descendant(of: find.byType(NxHoldButton), matching: find.text('SOS'));

/// Frases que la app nunca debe mostrar sin confirmación verificable.
final RegExp forbiddenClaims = RegExp(
  'recibid|ayuda en camino|a salvo|está segur|estás segur',
  caseSensitive: false,
);

/// Concatenación de los textos visibles.
String visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join('\n');
