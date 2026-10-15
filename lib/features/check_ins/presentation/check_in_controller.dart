import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/features/check_ins/presentation/check_in_providers.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';

/// Etapas del flujo de check-in. Solo [delivered] afirma algo del servidor,
/// y únicamente después de que la bandeja de salida lo confirmó.
enum CheckInPhase {
  /// Eligiendo opción, mensaje y ubicación.
  editing,

  /// Buscando la ubicación para adjuntarla (como mucho unos segundos).
  locating,

  /// Guardándolo en el teléfono.
  saving,

  /// Guardado; esperando la confirmación del servidor.
  sending,

  /// Guardado y sin confirmar tras [CheckInController.settleDelay], o sin
  /// conexión: se enviará cuando se pueda.
  queued,

  /// El servidor lo confirmó (salió de la bandeja de salida).
  delivered,

  /// El servidor lo rechazó; se puede reintentar o descartar.
  failed,
}

@immutable
final class CheckInFlowState {
  const new({
    this.kind,
    this.includeLocation = false,
    this.phase = CheckInPhase.editing,
    this.submitted,
    this.failure,
    this.locationOmitted = false,
    this.locationApproximate = false,
    this.seen = false,
    this.absenceTrusted = false,
  });

  final CheckInKind? kind;
  final bool includeLocation;
  final CheckInPhase phase;

  /// Check-in enviado que se está siguiendo (desde [CheckInPhase.sending]).
  final CheckIn? submitted;

  /// Último fallo de una acción (enviar, reintentar o descartar).
  final Failure? failure;

  /// Se pidió incluir la ubicación pero no se obtuvo: va sin ella.
  final bool locationOmitted;

  /// La ubicación adjunta es aproximada (precisión elegida por la persona).
  final bool locationApproximate;

  /// El check-in ya apareció en la lista de pendientes.
  final bool seen;

  /// Pasó [CheckInController.settleDelay] desde el envío: si no está en la
  /// lista de pendientes es porque salió de la bandeja, no porque la lista
  /// aún no lo refleje.
  final bool absenceTrusted;

  bool get isBusy =>
      phase == CheckInPhase.locating || phase == CheckInPhase.saving;

  bool get isEditing => phase == CheckInPhase.editing || isBusy;

  CheckInFlowState copyWith({
    CheckInKind? kind,
    bool? includeLocation,
    CheckInPhase? phase,
    bool? seen,
    bool? absenceTrusted,
  }) => CheckInFlowState(
    kind: kind ?? this.kind,
    includeLocation: includeLocation ?? this.includeLocation,
    phase: phase ?? this.phase,
    submitted: submitted,
    failure: failure,
    locationOmitted: locationOmitted,
    locationApproximate: locationApproximate,
    seen: seen ?? this.seen,
    absenceTrusted: absenceTrusted ?? this.absenceTrusted,
  );

  CheckInFlowState withFailure(Failure? failure) => CheckInFlowState(
    kind: kind,
    includeLocation: includeLocation,
    phase: phase,
    submitted: submitted,
    failure: failure,
    locationOmitted: locationOmitted,
    locationApproximate: locationApproximate,
    seen: seen,
    absenceTrusted: absenceTrusted,
  );

  /// Vuelve al formulario conservando la opción elegida.
  CheckInFlowState backToEditing({Failure? failure}) => CheckInFlowState(
    kind: kind,
    includeLocation: includeLocation,
    failure: failure,
  );
}

final NotifierProvider<CheckInController, CheckInFlowState>
checkInControllerProvider =
    NotifierProvider.autoDispose<CheckInController, CheckInFlowState>(
      CheckInController.new,
    );

/// Flujo de la pantalla de check-in: elige, guarda y sigue la entrega.
///
/// La entrega se deduce de `pendingCheckInsProvider` (la bandeja de
/// salida): un check-in enviado deja de estar pendiente solo cuando el
/// servidor confirmó la escritura. Para no confundir "aún no aparece" con
/// "ya salió", la ausencia solo cuenta como entrega si antes apareció o si
/// ya pasó [settleDelay].
final class CheckInController extends Notifier<CheckInFlowState> {
  /// Tiempo que se muestra "Enviando…" antes de pasar a "Guardado. Se
  /// enviará al recuperar la conexión" si el servidor no confirmó.
  static const settleDelay = Duration(seconds: 2);

  Timer? _settleTimer;

  @override
  CheckInFlowState build() {
    final familyId = ref.watch(activeFamilyIdProvider);
    // Mantiene la sesión suscrita para que `submit` tenga el uid al
    // momento; si cambia la cuenta, el flujo empieza de nuevo.
    ref.watch(currentUserProvider.select((user) => user.value?.uid));
    ref.onDispose(() => _settleTimer?.cancel());
    if (familyId != null) {
      ref.listen(pendingCheckInsProvider(familyId), (_, next) {
        if (next.value case final pending?) _onPending(pending);
      });
    }
    return const CheckInFlowState();
  }

  void selectKind(CheckInKind kind) {
    if (state.phase != CheckInPhase.editing) return;
    state = state.copyWith(kind: kind).withFailure(null);
  }

  void setIncludeLocation({required bool include}) {
    if (state.phase != CheckInPhase.editing) return;
    state = state.copyWith(includeLocation: include);
  }

  void clearFailure() {
    if (state.failure != null) state = state.withFailure(null);
  }

  Future<void> submit(String message) async {
    final start = state;
    final kind = start.kind;
    if (kind == null || start.phase != CheckInPhase.editing) return;
    final familyId = ref.read(activeFamilyIdProvider);
    final uid = ref.read(currentUserProvider).value?.uid;
    if (familyId == null) {
      state = start.withFailure(
        const Failure.validation(CheckInFailureCodes.noFamily),
      );
      return;
    }
    if (uid == null) {
      state = start.withFailure(const Failure.unauthenticated());
      return;
    }
    // Se valida antes de buscar la ubicación (no hace falta esperar).
    if (CheckInRules.message(message) case final code?) {
      state = start.withFailure(Failure.validation(code));
      return;
    }

    DeviceFix? fix;
    var omitted = false;
    var approximate = false;
    if (start.includeLocation) {
      final consent = ref.read(myConsentProvider(familyId)).value;
      // El consentimiento pudo cambiar desde que se mostró el interruptor.
      if (consent != null && consent.isSharing) {
        approximate = consent.precision == LocationPrecision.approximate;
        state = start.copyWith(phase: CheckInPhase.locating).withFailure(null);
        fix = await ref.read(resolveShareableLocationProvider)(consent);
        if (!ref.mounted) return;
      }
      omitted = fix == null;
    }

    state = start.copyWith(phase: CheckInPhase.saving).withFailure(null);
    final result = await ref.read(submitCheckInProvider)(
      familyId: familyId,
      uid: uid,
      kind: kind,
      message: message,
      location: fix,
    );
    if (!ref.mounted) return;
    switch (result) {
      case Err(:final failure):
        state = start.withFailure(failure);
      case Ok(value: final checkIn):
        final offline =
            ref.read(syncStatusProvider).value == SyncStatus.offline;
        state = CheckInFlowState(
          kind: kind,
          includeLocation: start.includeLocation,
          phase: offline ? CheckInPhase.queued : CheckInPhase.sending,
          submitted: checkIn,
          locationOmitted: omitted,
          locationApproximate: approximate && fix != null,
        );
        _startSettleTimer();
    }
  }

  /// Reintenta ahora un check-in fallido (el seguido o uno de la lista).
  Future<void> retry(String checkInId) async {
    final result = await ref.read(retryCheckInProvider)(checkInId);
    if (!ref.mounted) return;
    if (result case Err(:final failure)) {
      state = state.withFailure(failure);
      return;
    }
    if (state.submitted?.id == checkInId) {
      state = state
          .copyWith(phase: CheckInPhase.sending, absenceTrusted: false)
          .withFailure(null);
      _startSettleTimer();
    } else {
      clearFailure();
    }
  }

  /// Descarta un check-in no enviado. Si era el seguido, vuelve al
  /// formulario con la misma opción para poder enviarlo de nuevo.
  Future<void> discard(String checkInId) async {
    final before = state;
    final tracked = before.submitted?.id == checkInId;
    if (tracked) {
      // Antes de que la lista refleje su salida: no es una entrega.
      _settleTimer?.cancel();
      state = before.backToEditing();
    }
    final result = await ref.read(discardCheckInProvider)(checkInId);
    if (!ref.mounted) return;
    if (result case Err(:final failure)) {
      state = (tracked ? before : state).withFailure(failure);
      if (tracked) _startSettleTimer();
    } else if (!tracked) {
      clearFailure();
    }
  }

  void _startSettleTimer() {
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, _onSettled);
  }

  void _onSettled() {
    if (!ref.mounted || state.submitted == null) return;
    state = state.copyWith(absenceTrusted: true);
    if (state.phase == CheckInPhase.sending) {
      state = state.copyWith(phase: CheckInPhase.queued);
    }
    final familyId = state.submitted!.familyId;
    if (ref.read(pendingCheckInsProvider(familyId)).value case final pending?) {
      _onPending(pending);
    }
  }

  void _onPending(List<CheckIn> pending) {
    final tracked = state.submitted;
    if (tracked == null) return;
    switch (state.phase) {
      case CheckInPhase.sending || CheckInPhase.queued || CheckInPhase.failed:
        break;
      case CheckInPhase.editing ||
          CheckInPhase.locating ||
          CheckInPhase.saving ||
          CheckInPhase.delivered:
        return;
    }
    final current = pending.where((c) => c.id == tracked.id).firstOrNull;
    if (current == null) {
      if (state.seen || state.absenceTrusted) {
        _settleTimer?.cancel();
        state = state.copyWith(phase: CheckInPhase.delivered);
      }
      return;
    }
    final phase = switch (current.delivery) {
      DeliveryState.failed => CheckInPhase.failed,
      DeliveryState.pending || DeliveryState.delivered =>
        state.phase != CheckInPhase.failed
            ? state.phase
            : state.absenceTrusted
            ? CheckInPhase.queued
            : CheckInPhase.sending,
    };
    state = state.copyWith(phase: phase, seen: true);
  }
}
