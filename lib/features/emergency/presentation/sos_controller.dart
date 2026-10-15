import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_countdown.dart';
import 'package:nexo_familia/features/emergency/presentation/emergency_providers.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_view_logic.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/domain/location_use_cases.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';

/// Aviso puntual en el estado inicial tras una acción de la persona.
enum SosNotice {
  /// Canceló durante la cuenta atrás: no se creó nada.
  cancelled,

  /// Descartó una alerta que aún no se había enviado.
  discarded,
}

/// Estado de la pantalla SOS.
@immutable
sealed class SosFlowState {
  const new();
}

/// Lista para pedir ayuda (mantener pulsado).
final class SosReady extends SosFlowState {
  const new({this.notice});

  final SosNotice? notice;
}

/// Cuenta atrás cancelable.
final class SosCountingDown extends SosFlowState {
  const new({required this.secondsLeft, required this.fraction});

  final int secondsLeft;

  /// De 1 (recién empezada) a 0.
  final double fraction;
}

/// Terminó la cuenta atrás: se obtiene la ubicación (si se comparte) y se
/// guarda la alerta.
final class SosPreparing extends SosFlowState {
  const new();
}

/// No se pudo guardar la alerta en el dispositivo (raro: fallo de la base de
/// datos local). Se puede reintentar con el mismo id.
final class SosNotSaved extends SosFlowState {
  const new(this.failure);

  final Failure failure;
}

/// Alerta propia en curso, con lo último que se sabe de ella.
final class SosTracking extends SosFlowState {
  const new(this.alert);

  final EmergencyAlert alert;
}

final NotifierProvider<SosController, SosFlowState> sosControllerProvider =
    NotifierProvider.autoDispose<SosController, SosFlowState>(
      SosController.new,
    );

/// Orquesta el flujo SOS: mantener pulsado → cuenta atrás cancelable →
/// ubicación (si se comparte, ≤ 5 s) → alerta en la bandeja de salida →
/// seguimiento honesto de su estado.
///
/// Una vez terminada la cuenta atrás, la alerta se crea **aunque se cierre
/// la pantalla**: todo lo necesario se lee antes de esperar. Cerrar la
/// pantalla durante la cuenta atrás equivale a cancelar.
final class SosController extends Notifier<SosFlowState> {
  /// Cada cuánto se consulta la cuenta atrás (la cifra cambia por segundos;
  /// el anillo avanza con más suavidad).
  static const Duration tick = Duration(milliseconds: 200);

  /// Tiempo máximo para obtener la ubicación: nunca retrasa la alerta más.
  static const Duration locationBudget = SosRules.cancelWindow;

  SosCountdown? _countdown;
  Timer? _ticker;
  String? _familyId;
  String? _uid;

  /// Alerta preparada (mismo id en cada reintento de guardado).
  EmergencyAlert? _draft;

  /// Terminadas o descartadas desde esta pantalla: no se vuelven a abrir.
  final Set<String> _closed = {};

  @override
  SosFlowState build() {
    _familyId = ref.watch(activeFamilyIdProvider);
    _uid = ref.watch(currentUserProvider.select((user) => user.value?.uid));
    _countdown = null;
    _draft = null;
    ref.onDispose(_stopTicker);
    final familyId = _familyId;
    if (familyId == null) return const SosReady();
    final alerts = emergencyAlertsProvider(familyId);
    ref.listen(alerts, (_, next) {
      if (next.value case final list?) _onAlerts(list);
    });
    // Si ya hay una alerta propia abierta, se muestra en lugar del botón.
    final open = switch (ref.read(alerts).value) {
      final list? => myOpenAlert(list, _uid, ignore: _closed),
      null => null,
    };
    return open == null ? const SosReady() : SosTracking(open);
  }

  void _onAlerts(List<EmergencyAlert> alerts) {
    switch (state) {
      case SosTracking(:final alert):
        final fresh = alerts.where((a) => a.id == alert.id).firstOrNull;
        // Si desaparece un momento (enviada y aún sin reflejar), se conserva
        // lo último conocido: nunca se afirma más de lo verificado.
        if (fresh != null) state = SosTracking(mergeKnown(fresh, alert));
      case SosReady():
        if (myOpenAlert(alerts, _uid, ignore: _closed) case final open?) {
          state = SosTracking(open);
        }
      case SosCountingDown() || SosPreparing() || SosNotSaved():
        break;
    }
  }

  /// Tras mantener pulsado el botón: empieza la cuenta atrás.
  void startCountdown() {
    if (state is! SosReady || _familyId == null || _uid == null) return;
    final countdown = _countdown = SosCountdown(ref.read(clockProvider))
      ..start();
    state = SosCountingDown(
      secondsLeft: countdown.remainingSeconds,
      fraction: countdown.fractionRemaining,
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(tick, (_) => _onTick());
  }

  void _onTick() {
    final countdown = _countdown;
    if (countdown == null || !ref.mounted) {
      _stopTicker();
      return;
    }
    if (countdown.poll()) {
      _stopTicker();
      unawaited(_raise());
      return;
    }
    if (countdown.phase != SosCountdownPhase.counting) {
      _stopTicker();
      return;
    }
    state = SosCountingDown(
      secondsLeft: countdown.remainingSeconds,
      fraction: countdown.fractionRemaining,
    );
  }

  /// "Cancelar" durante la cuenta atrás. Devuelve `false` si ya era tarde
  /// (la alerta se está creando).
  bool cancel() {
    final countdown = _countdown;
    if (countdown == null || !countdown.cancel()) return false;
    _stopTicker();
    _countdown = null;
    state = const SosReady(notice: SosNotice.cancelled);
    ref.read(loggerProvider).info('sos.cancelled', fields: _fields);
    return true;
  }

  Future<void> _raise() async {
    final familyId = _familyId;
    final uid = _uid;
    if (familyId == null || uid == null) {
      state = const SosReady();
      return;
    }
    state = const SosPreparing();
    // Se lee lo necesario antes de esperar: si la pantalla se cierra, la
    // alerta sigue adelante.
    final clock = ref.read(clockProvider);
    final ids = ref.read(idGeneratorProvider);
    final repository = ref.read(emergencyRepositoryProvider);
    final logger = ref.read(loggerProvider);
    final resolve = ref.read(resolveShareableLocationProvider);
    final consent = ref.read(myConsentProvider(familyId).future);
    final id = ids.newId();
    final createdAt = clock.now();

    final fix = await _locate(consent, resolve);
    final draft = _draft = EmergencyAlert(
      id: id,
      familyId: familyId,
      uid: uid,
      createdAt: createdAt,
      delivery: SosDelivery.queued,
      location: fix?.point,
      locationAccuracyMeters: fix?.accuracyMeters,
    );
    await _save(repository, logger, draft);
  }

  /// Reintenta guardar la alerta preparada (mismo id: idempotente).
  Future<void> retrySave() async {
    final draft = _draft;
    if (state is! SosNotSaved || draft == null) return;
    state = const SosPreparing();
    await _save(
      ref.read(emergencyRepositoryProvider),
      ref.read(loggerProvider),
      draft,
    );
  }

  Future<void> _save(
    EmergencyRepository repository,
    SafeLogger logger,
    EmergencyAlert draft,
  ) async {
    final result = await repository.raise(draft);
    switch (result) {
      case Ok(:final value):
        logger.info('sos.raised', fields: {..._fields, 'opId': value.id});
        if (ref.mounted) state = SosTracking(value);
      case Err(:final failure):
        logger.error('sos.not_saved', fields: _fields, failure: failure);
        if (ref.mounted) state = SosNotSaved(failure);
    }
  }

  /// Ubicación compartible (respeta el consentimiento y nunca pide
  /// permisos) o `null`; nunca tarda más de [locationBudget].
  static Future<DeviceFix?> _locate(
    Future<SharingConsent> consent,
    ResolveShareableLocation resolve,
  ) async {
    Future<DeviceFix?> attempt() => consent.then(resolve.call);
    try {
      return await attempt().timeout(locationBudget);
    } on Object {
      // Sin consentimiento conocido, sin permiso o sin señal: la alerta va
      // sin ubicación. Un SOS nunca falla por la ubicación.
      return null;
    }
  }

  /// Reintenta ya el envío de la alerta en curso (en cola o fallida).
  Future<VoidResult> retry() async {
    final current = state;
    if (current is! SosTracking) return const Ok(null);
    return await ref.read(emergencyRepositoryProvider).retry(current.alert.id);
  }

  /// "Terminar alerta" (registrada) o "Cancelar envío" (aún sin confirmar).
  /// Solo se da por hecho con `Ok`.
  Future<VoidResult> end() async {
    final current = state;
    if (current is! SosTracking) return const Ok(null);
    final alert = current.alert;
    final repository = ref.read(emergencyRepositoryProvider);
    final clock = ref.read(clockProvider);
    final result = await repository.resolve(alert.familyId, alert.id);
    if (!ref.mounted || result is Err) return result;
    _closed.add(alert.id);
    final latest = state;
    if (latest is! SosTracking || latest.alert.id != alert.id) return result;
    state = latest.alert.delivery == SosDelivery.sent
        // El servidor confirmó la escritura; la caché traerá su hora exacta.
        ? SosTracking(latest.alert.copyWith(resolvedAt: clock.now()))
        : const SosReady(notice: SosNotice.discarded);
    return result;
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  static const Map<String, Object?> _fields = {'feature': 'emergency'};
}
