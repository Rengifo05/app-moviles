import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) =>
      throw UnimplementedError('preferencesRepositoryProvider: ver bootstrap'),
);

final preferencesProvider = StreamProvider<AppPreferences>(
  (ref) => ref.watch(preferencesRepositoryProvider).watch(),
);

/// Versión visible en "Acerca de". Fija hasta que la versión salga de la
/// compilación (`package_info_plus`).
const String appVersionLabel = '0.1.0';

/// Si este teléfono puede recibir avisos SOS con la app cerrada (ADR-005).
/// Sin servicio de avisos (modo demostración, emuladores) Ajustes lo dice en
/// lugar de fingir que hay avisos activos.
final pushNotificationsAvailableProvider = Provider<bool>(
  (ref) => ref.watch(pushServiceProvider).isAvailable,
);

/// Operaciones de la bandeja de salida aún sin enviar (check-ins, eventos de
/// zona…). Al cerrar sesión se descartan (ADR-004, punto 8), así que la
/// pantalla de cuenta avisa antes. La raíz de composición lo conecta con la
/// bandeja; mientras no lo haga, nunca emite y no se muestra ningún aviso.
final pendingOutboxCountProvider = StreamProvider<int>(
  (ref) => const Stream<int>.empty(),
);
