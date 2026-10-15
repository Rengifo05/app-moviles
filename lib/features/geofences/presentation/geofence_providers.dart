import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:riverpod/misc.dart';

final geofenceRepositoryProvider = Provider<GeofenceRepository>(
  (ref) =>
      throw UnimplementedError('geofenceRepositoryProvider: ver bootstrap'),
);

final StreamProviderFamily<List<Geofence>, String> geofencesProvider =
    StreamProvider.family<List<Geofence>, String>(
      (ref, familyId) =>
          ref.watch(geofenceRepositoryProvider).watchGeofences(familyId),
    );
