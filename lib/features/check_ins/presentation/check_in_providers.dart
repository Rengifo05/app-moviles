import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:riverpod/misc.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => throw UnimplementedError('checkInRepositoryProvider: ver bootstrap'),
);

final StreamProviderFamily<List<CheckIn>, String> pendingCheckInsProvider =
    StreamProvider.family<List<CheckIn>, String>(
      (ref, familyId) =>
          ref.watch(checkInRepositoryProvider).watchPending(familyId),
    );
