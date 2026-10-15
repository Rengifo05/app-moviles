import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_logic.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
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

/// Crear, actualizar y eliminar zonas desde el editor.
final geofenceActionsProvider = Provider<GeofenceActions>(
  (ref) => GeofenceActions(
    repository: ref.watch(geofenceRepositoryProvider),
    logger: ref.watch(loggerProvider),
  ),
);

/// Ubicación actual del teléfono como centro de una zona.
final zoneCenterLocatorProvider = Provider<ZoneCenterLocator>(
  (ref) => ZoneCenterLocator(ref.watch(deviceLocationServiceProvider)),
);
