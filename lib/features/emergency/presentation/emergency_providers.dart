import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/emergency_dialer.dart';
import 'package:riverpod/misc.dart';

final emergencyRepositoryProvider = Provider<EmergencyRepository>(
  (ref) =>
      throw UnimplementedError('emergencyRepositoryProvider: ver bootstrap'),
);

final StreamProviderFamily<List<EmergencyAlert>, String>
emergencyAlertsProvider = StreamProvider.family<List<EmergencyAlert>, String>(
  (ref, familyId) =>
      ref.watch(emergencyRepositoryProvider).watchAlerts(familyId),
);

/// Marcador del teléfono para "Llamar al 123". La raíz de composición lo
/// sobrescribe con `UrlLauncherEmergencyDialer`.
///
/// A diferencia de los repositorios, por defecto **no lanza**: si faltara el
/// cableado, el SOS sigue funcionando y la pantalla muestra el número para
/// marcarlo a mano.
final emergencyDialerProvider = Provider<EmergencyDialer>(
  (ref) => const _UnavailableDialer(),
);

final class _UnavailableDialer implements EmergencyDialer {
  const new();

  @override
  Future<bool> dial(String number) async => false;
}
