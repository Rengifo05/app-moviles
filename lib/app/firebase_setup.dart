import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:meta/meta.dart';

/// Configuración del proyecto de Firebase. Son identificadores públicos del
/// cliente (no secretos), pero dependen del proyecto, así que llegan por
/// `--dart-define-from-file` y no se versionan (ver config/env.example.json).
@immutable
final class FirebaseConfig {
  const new({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.emulatorHost,
    required this.functionsRegion,
  });

  factory fromEnvironment() => const FirebaseConfig(
    apiKey: String.fromEnvironment('NX_FIREBASE_API_KEY'),
    appId: String.fromEnvironment('NX_FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('NX_FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('NX_FIREBASE_PROJECT_ID'),
    // 10.0.2.2 desde el emulador de Android; 127.0.0.1 en iOS o escritorio.
    emulatorHost: String.fromEnvironment(
      'NX_EMULATOR_HOST',
      defaultValue: '127.0.0.1',
    ),
    functionsRegion: String.fromEnvironment(
      'NX_FUNCTIONS_REGION',
      defaultValue: 'southamerica-east1',
    ),
  );

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String emulatorHost;
  final String functionsRegion;

  List<String> validate({required bool useEmulators}) => [
    if (projectId.isEmpty) 'NX_FIREBASE_PROJECT_ID es obligatorio.',
    if (!useEmulators && apiKey.isEmpty) 'NX_FIREBASE_API_KEY es obligatorio.',
    if (!useEmulators && appId.isEmpty) 'NX_FIREBASE_APP_ID es obligatorio.',
    if (useEmulators && !projectId.startsWith('demo-'))
      'Con emuladores usa un proyecto demo-* (sin recursos reales).',
  ];
}

/// Instancias de Firebase listas para la composición.
final class FirebaseHandles {
  const new(this.firestore, this.auth, this.functions, {this.messaging});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  /// `null` con emuladores: FCM no tiene emulador y un proyecto `demo-*` no
  /// puede entregar avisos (ADR-005).
  final FirebaseMessaging? messaging;
}

/// Inicializa Firebase y, si se piden, conecta los emuladores locales.
Future<FirebaseHandles> initializeFirebase(
  FirebaseConfig config, {
  required bool useEmulators,
}) async {
  final errors = config.validate(useEmulators: useEmulators);
  if (errors.isNotEmpty) {
    throw StateError('Configuración de Firebase inválida: ${errors.join(' ')}');
  }
  final app = await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: config.apiKey.isEmpty ? 'demo-api-key' : config.apiKey,
      appId: config.appId.isEmpty ? '1:0:android:0' : config.appId,
      messagingSenderId: config.messagingSenderId.isEmpty
          ? '0'
          : config.messagingSenderId,
      projectId: config.projectId,
    ),
  );
  final firestore = FirebaseFirestore.instanceFor(app: app);
  final auth = FirebaseAuth.instanceFor(app: app);
  final functions = FirebaseFunctions.instanceFor(
    app: app,
    region: config.functionsRegion,
  );
  if (useEmulators) {
    firestore.useFirestoreEmulator(config.emulatorHost, 8085);
    await auth.useAuthEmulator(config.emulatorHost, 9099);
    functions.useFunctionsEmulator(config.emulatorHost, 5001);
  }
  // Caché de Firestore solo en memoria (ADR-004 §7): la UI lee de Drift, que
  // se purga al cerrar sesión o salir de una familia. Una caché en disco
  // conservaría datos de la familia que Firestore nunca borra por sí solo.
  firestore.settings = const Settings(persistenceEnabled: false);
  return FirebaseHandles(
    firestore,
    auth,
    functions,
    messaging: useEmulators ? null : FirebaseMessaging.instance,
  );
}
