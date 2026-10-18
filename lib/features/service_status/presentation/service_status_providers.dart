import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/service_status/domain/service_status.dart';

/// Por defecto no hay banderas remotas (todo activo). La raíz de
/// composición conecta el repositorio real.
final serviceStatusRepositoryProvider = Provider<ServiceStatusRepository>(
  (ref) => const _NoRemoteFlags(),
);

/// Número de compilación instalado (para [ServiceFlags.minBuild]). Lo lee la
/// raíz de composición; `null` si no se conoce.
final appBuildNumberProvider = Provider<int?>((ref) => null);

/// Banderas vigentes. Solo se escuchan con sesión (las reglas lo exigen);
/// sin sesión, los valores por defecto.
final serviceFlagsProvider = StreamProvider<ServiceFlags>((ref) {
  final uid = ref.watch(currentUserProvider.select((u) => u.value?.uid));
  if (uid == null) return Stream.value(ServiceFlags.defaults);
  return ref.watch(serviceStatusRepositoryProvider).watchFlags();
});

/// Valor actual sin esperar: mientras carga, los valores por defecto.
final currentServiceFlagsProvider = Provider<ServiceFlags>(
  (ref) => ref.watch(serviceFlagsProvider).value ?? ServiceFlags.defaults,
);

final class _NoRemoteFlags implements ServiceStatusRepository {
  const new();

  @override
  Stream<ServiceFlags> watchFlags() => Stream.value(ServiceFlags.defaults);
}
