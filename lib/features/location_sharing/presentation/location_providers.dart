import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
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

final StreamProviderFamily<SharingConsent, String> myConsentProvider =
    StreamProvider.family<SharingConsent, String>(
      (ref, familyId) =>
          ref.watch(locationRepositoryProvider).watchMyConsent(familyId),
    );
