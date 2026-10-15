import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/create_family_screen.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_screen.dart';
import 'package:nexo_familia/features/family/presentation/family_setup_screen.dart';
import 'package:nexo_familia/features/family/presentation/invite_screen.dart';
import 'package:nexo_familia/features/family/presentation/join_family_screen.dart';
import 'package:nexo_familia/features/family/presentation/member_detail_screen.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';
import 'package:riverpod/misc.dart';

import '../../../helpers/fakes.dart';

/// Hora fija de las pruebas (UTC).
final DateTime testNow = DateTime.utc(2026, 10, 15, 15, 30);

const testConfig = AppConfig(
  appName: 'Nexo Prueba',
  environment: AppEnvironment.dev,
  backend: BackendMode.demo,
  useFirebaseEmulators: false,
  emergencyNumber: '123',
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

  Future<void> close() => _changes.close();
}

/// Respuesta programada para una operación: inmediata o retenida hasta que
/// la prueba la complete (para ver el estado de carga).
final class Scripted<T> {
  new(this.result);

  Result<T> result;
  Completer<void>? gate;

  Future<Result<T>> run() async {
    if (gate case final gate?) await gate.future;
    return result;
  }

  void hold() => gate = Completer<void>();

  void release() => gate?.complete();
}

final class FakeFamilyRepository implements FamilyRepository {
  new({
    List<FamilyGroup> families = const [],
    Map<String, List<FamilyMember>>? members,
  }) : families = ValueStream(families),
       _members = {
         for (final entry in (members ?? const {}).entries)
           entry.key: ValueStream(entry.value),
       };

  final ValueStream<List<FamilyGroup>> families;
  final Map<String, ValueStream<List<FamilyMember>>> _members;

  /// Familias cuyo flujo de integrantes nunca emite (estado de carga).
  final Set<String> neverLoads = {};

  /// Familias cuyo flujo de integrantes falla.
  final Map<String, Failure> failingMembers = {};

  final createCalls = <String>[];
  final acceptCalls = <String>[];
  final inviteCalls = <String>[];
  final leaveCalls = <String>[];
  final removeCalls = <(String, String)>[];

  final create = Scripted<FamilyGroup>(
    Ok(
      FamilyGroup(
        id: 'fam-new',
        name: 'Familia Nueva',
        myRole: MemberRole.owner,
        joinedAt: testNow,
      ),
    ),
  );
  final accept = Scripted<String>(const Ok('fam-joined'));
  final invite = Scripted<CreatedInvitation>(
    Ok(
      CreatedInvitation(
        invitationId: 'inv-1',
        code: 'ABCDEFGHJK',
        expiresAt: testNow.add(const Duration(hours: 48)),
        maxUses: 1,
      ),
    ),
  );
  final leave = Scripted<void>(const Ok(null));
  final remove = Scripted<void>(const Ok(null));

  ValueStream<List<FamilyMember>> membersOf(String familyId) =>
      _members.putIfAbsent(familyId, () => ValueStream(const []));

  @override
  Stream<List<FamilyGroup>> watchMyFamilies() => families.stream();

  @override
  Stream<List<FamilyMember>> watchMembers(String familyId) {
    if (neverLoads.contains(familyId)) {
      return Stream.fromFuture(Completer<List<FamilyMember>>().future);
    }
    if (failingMembers[familyId] case final failure?) {
      return Stream.error(failure);
    }
    return membersOf(familyId).stream();
  }

  @override
  Future<Result<FamilyGroup>> createFamily(String name) {
    createCalls.add(name);
    return create.run();
  }

  @override
  Future<Result<CreatedInvitation>> createInvitation(String familyId) {
    inviteCalls.add(familyId);
    return invite.run();
  }

  @override
  Future<Result<String>> acceptInvitation(String code) {
    acceptCalls.add(code);
    return accept.run();
  }

  @override
  Future<VoidResult> leaveFamily(String familyId) {
    leaveCalls.add(familyId);
    return leave.run();
  }

  @override
  Future<VoidResult> removeMember(String familyId, String uid) {
    removeCalls.add((familyId, uid));
    return remove.run();
  }
}

final class FakePreferencesRepository implements PreferencesRepository {
  new([
    AppPreferences initial = const AppPreferences(onboardingCompleted: true),
  ]) : prefs = ValueStream(initial);

  final ValueStream<AppPreferences> prefs;
  Error? failWith;

  @override
  Stream<AppPreferences> watch() => prefs.stream();

  @override
  Future<AppPreferences> read() async => prefs.value;

  @override
  Future<void> update(AppPreferences Function(AppPreferences) change) async {
    if (failWith case final error?) throw error;
    prefs.value = change(prefs.value);
  }

  @override
  Future<void> clear() async => prefs.value = const AppPreferences();
}

final class FakeAuthRepository implements AuthRepository {
  new(this.currentUser);

  @override
  final AuthUser? currentUser;
  VoidResult signOutResult = const Ok(null);
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> watchUser() => Stream.value(currentUser);

  @override
  Future<VoidResult> signOut() async {
    signOutCalls++;
    return signOutResult;
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

  @override
  Future<VoidResult> deleteAccount() => throw UnimplementedError();
}

final class FakeLocationRepository implements LocationRepository {
  new([List<MemberLocation> locations = const []])
    : locations = ValueStream(locations);

  final ValueStream<List<MemberLocation>> locations;
  Failure? failure;

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) =>
      failure == null ? locations.stream() : Stream.error(failure!);

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> updateConsent(SharingConsent consent) =>
      throw UnimplementedError();

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) => throw UnimplementedError();
}

// --- Datos sintéticos -------------------------------------------------------

const familyId = 'fam-1';
const me = AuthUser(uid: 'ana', email: 'ana@example.com', displayName: 'Ana');

FamilyGroup familyGroup({
  String id = familyId,
  String name = 'Familia Gómez',
  MemberRole role = MemberRole.owner,
}) => FamilyGroup(
  id: id,
  name: name,
  myRole: role,
  joinedAt: DateTime.utc(2026, 3, 2, 14),
);

FamilyMember familyMember(
  String uid,
  String name,
  MemberRole role, {
  String family = familyId,
}) => FamilyMember(
  uid: uid,
  familyId: family,
  displayName: name,
  role: role,
  joinedAt: DateTime.utc(2026, 3, 2, 14),
);

List<FamilyMember> sampleMembers() => [
  familyMember('ana', 'Ana', MemberRole.owner),
  familyMember('marta', 'Marta Ruiz', MemberRole.admin),
  familyMember('luis', 'Luis', MemberRole.member),
  familyMember('sofia', 'Sofía', MemberRole.member),
];

/// Ubicación sintética (coordenadas genéricas, no de personas reales).
MemberLocation sampleLocation(
  String uid, {
  required Duration age,
  bool approximate = false,
}) => MemberLocation(
  uid: uid,
  point: GeoPoint(4.6, -74.08),
  accuracyMeters: 25,
  capturedAt: testNow.subtract(age),
  receivedAt: testNow.subtract(age),
  isApproximate: approximate,
);

// --- Montaje ----------------------------------------------------------------

/// Dependencias de una prueba de pantalla.
final class FamilyTestEnv {
  new({
    FakeFamilyRepository? families,
    FakePreferencesRepository? preferences,
    FakeAuthRepository? auth,
    FakeLocationRepository? locations,
    this.activeFamilyId = familyId,
    this.syncStatus = SyncStatus.live,
    AuthUser? user = me,
  }) : families =
           families ??
           FakeFamilyRepository(
             families: [familyGroup()],
             members: {familyId: sampleMembers()},
           ),
       preferences = preferences ?? FakePreferencesRepository(),
       auth = auth ?? FakeAuthRepository(user),
       locations = locations ?? FakeLocationRepository(),
       clock = FakeClock(testNow),
       logSink = MemoryLogSink();

  final FakeFamilyRepository families;
  final FakePreferencesRepository preferences;
  final FakeAuthRepository auth;
  final FakeLocationRepository locations;
  final FakeClock clock;
  final MemoryLogSink logSink;
  final String? activeFamilyId;
  final SyncStatus syncStatus;

  List<Override> get overrides => [
    appConfigProvider.overrideWithValue(testConfig),
    clockProvider.overrideWithValue(clock),
    loggerProvider.overrideWithValue(SafeLogger(sink: logSink, clock: clock)),
    familyRepositoryProvider.overrideWithValue(families),
    preferencesRepositoryProvider.overrideWithValue(preferences),
    authRepositoryProvider.overrideWithValue(auth),
    locationRepositoryProvider.overrideWithValue(locations),
    activeFamilyIdProvider.overrideWithValue(activeFamilyId),
    syncStatusProvider.overrideWith((ref) => Stream.value(syncStatus)),
  ];
}

/// Destino de navegación fuera de la funcionalidad (Inicio, Privacidad…).
class StubScreen extends StatelessWidget {
  const new(this.path, {super.key});

  final String path;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:$path')));
}

GoRouter buildFamilyTestRouter(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: AppRoutes.familySetup,
      builder: (_, _) => const FamilySetupScreen(),
      routes: [
        GoRoute(path: 'create', builder: (_, _) => const CreateFamilyScreen()),
        GoRoute(path: 'join', builder: (_, _) => const JoinFamilyScreen()),
      ],
    ),
    GoRoute(
      path: AppRoutes.family,
      builder: (_, _) => const FamilyScreen(),
      routes: [
        GoRoute(path: 'invite', builder: (_, _) => const InviteScreen()),
        GoRoute(
          path: 'members/:uid',
          builder: (_, state) =>
              MemberDetailScreen(uid: state.pathParameters['uid']!),
        ),
      ],
    ),
    for (final path in [AppRoutes.home, AppRoutes.privacy, AppRoutes.signIn])
      GoRoute(path: path, builder: (_, _) => StubScreen(path)),
  ],
);

/// Monta la app de prueba en [initialLocation] con tema, idioma y escala de
/// texto configurables. Usa una pantalla de 390 × 844 (iPhone 13/14).
Future<GoRouter> pumpFamilyApp(
  WidgetTester tester,
  FamilyTestEnv env, {
  required String initialLocation,
  ThemeData? theme,
  double textScale = 1,
  Locale locale = const Locale('es'),
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844) * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = buildFamilyTestRouter(initialLocation);
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
  if (settle) await pumpFrames(tester);
  return router;
}

/// Avanza varios fotogramas sin `pumpAndSettle` (los indicadores de
/// progreso indeterminados nunca se asientan).
Future<void> pumpFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Registra lo que la app copia al portapapeles.
List<String> captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

AppLocalizations get esL10n => lookupAppLocalizations(const Locale('es'));

/// Desplaza la página hasta que [finder] quede en pantalla y lo toca. Las
/// listas construyen elementos fuera de la vista (zona de caché), así que no
/// basta con que el elemento exista.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}
