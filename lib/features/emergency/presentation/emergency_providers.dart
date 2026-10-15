import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
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
