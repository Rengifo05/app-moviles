import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';
import 'package:riverpod/misc.dart';

final locationRepositoryProvider = Provider<LocationRepository>(
  (ref) =>
      throw UnimplementedError('locationRepositoryProvider: ver bootstrap'),
);

final deviceLocationServiceProvider = Provider<DeviceLocationService>(
  (ref) =>
      throw UnimplementedError('deviceLocationServiceProvider: ver bootstrap'),
);

/// Implementación del mapa (Google Maps o la lista accesible). ADR-002.
final mapBuilderProvider = Provider<NxMapBuilder?>((ref) => null);

final StreamProviderFamily<List<MemberLocation>, String>
familyLocationsProvider = StreamProvider.family<List<MemberLocation>, String>(
  (ref, familyId) =>
      ref.watch(locationRepositoryProvider).watchFamilyLocations(familyId),
);

/// Consentimiento propio en una familia. Se vuelve a suscribir cuando cambia
/// la cuenta: en un teléfono compartido, la persona que entra nunca ve (ni
/// usa para su SOS) la decisión de la anterior.
final StreamProviderFamily<SharingConsent, String> myConsentProvider =
    StreamProvider.family<SharingConsent, String>((ref, familyId) {
      ref.watch(currentUserProvider.select((user) => user.value?.uid));
      return ref.watch(locationRepositoryProvider).watchMyConsent(familyId);
    });

/// Publica ahora la ubicación propia en una familia (mapa; también lo
/// pueden usar check-in y SOS si necesitan publicarla).
final shareMyLocationNowProvider = Provider<ShareMyLocationNow>(
  (ref) => ShareMyLocationNow(
    ref.watch(locationRepositoryProvider),
    ref.watch(deviceLocationServiceProvider),
  ),
);

/// Ubicación que se puede adjuntar a un check-in o a un SOS respetando el
/// consentimiento (nunca pide permisos).
final resolveShareableLocationProvider = Provider<ResolveShareableLocation>(
  (ref) => ResolveShareableLocation(ref.watch(deviceLocationServiceProvider)),
);

/// Estado actual del permiso de ubicación del sistema. Quien lo cambia (una
/// solicitud o la vuelta desde los ajustes) lo invalida para releerlo.
final FutureProvider<DeviceLocationPermission>
deviceLocationPermissionProvider =
    FutureProvider.autoDispose<DeviceLocationPermission>(
      (ref) => ref.watch(deviceLocationServiceProvider).permission(),
    );
