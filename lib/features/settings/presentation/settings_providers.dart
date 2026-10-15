import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Si las notificaciones push están configuradas en esta compilación
/// (ADR-005). Por defecto `false`: mientras no exista el servicio de avisos,
/// Ajustes lo dice en lugar de fingir que hay avisos activos. La raíz de
/// composición lo sobrescribe cuando haya un `PushService` real.
final pushNotificationsAvailableProvider = Provider<bool>((ref) => false);

/// Operaciones de la bandeja de salida aún sin enviar (check-ins, eventos de
/// zona…). Al cerrar sesión se descartan (ADR-004, punto 8), así que la
/// pantalla de cuenta avisa antes. La raíz de composición lo conecta con la
/// bandeja; mientras no lo haga, nunca emite y no se muestra ningún aviso.
final pendingOutboxCountProvider = StreamProvider<int>(
  (ref) => const Stream<int>.empty(),
);
