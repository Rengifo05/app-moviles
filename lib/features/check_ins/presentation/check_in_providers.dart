import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:riverpod/misc.dart';

final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => throw UnimplementedError('checkInRepositoryProvider: ver bootstrap'),
);

final StreamProviderFamily<List<CheckIn>, String> pendingCheckInsProvider =
    StreamProvider.family<List<CheckIn>, String>(
      (ref, familyId) =>
          ref.watch(checkInRepositoryProvider).watchPending(familyId),
    );

/// Crea y guarda un check-in (adjunta la ubicación solo si se le pasa).
final submitCheckInProvider = Provider<SubmitCheckIn>(
  (ref) => SubmitCheckIn(
    ref.watch(checkInRepositoryProvider),
    ref.watch(idGeneratorProvider),
    ref.watch(clockProvider),
  ),
);

/// Acción sobre un check-in de la bandeja de salida, por su id.
typedef CheckInAction = Future<VoidResult> Function(String checkInId);

/// Vuelve a intentar ahora un check-in fallido. La raíz de composición lo
/// conecta con `CheckInRepositoryImpl.retry`.
final retryCheckInProvider = Provider<CheckInAction>(
  (ref) => throw UnimplementedError('retryCheckInProvider: ver bootstrap'),
);

/// Quita de la bandeja un check-in no enviado (ya no se enviará). La raíz
/// de composición lo conecta con `CheckInRepositoryImpl.discard`.
final discardCheckInProvider = Provider<CheckInAction>(
  (ref) => throw UnimplementedError('discardCheckInProvider: ver bootstrap'),
);
