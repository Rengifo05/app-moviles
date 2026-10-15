import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/id_generator.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

/// Códigos de fallo de los check-ins (la interfaz los traduce).
abstract final class CheckInFailureCodes {
  /// El mensaje supera `CheckInRules.maxMessageLength` (tras recortarlo).
  static const messageTooLong = 'check-in-message-too-long';

  /// No hay familia activa a la que enviarlo.
  static const noFamily = 'check-in-no-family';

  /// No se pudo guardar en la bandeja local (base de datos del teléfono).
  static const notSaved = 'check-in-not-saved';

  /// Reintentar o descartar un check-in que ya no está en la bandeja (se
  /// envió mientras tanto o se descartó).
  static const notFound = 'check-in-not-found';

  /// Descartar un check-in que se está enviando en este momento: podría
  /// llegar igual, así que no se da por descartado.
  static const sending = 'check-in-sending';
}

/// Crea un check-in ("Estoy bien" / "Necesito ayuda") y lo entrega al
/// repositorio, que lo guarda y lo envía en cuanto pueda.
///
/// La ubicación se adjunta **solo** si se pasa [DeviceFix]. Quien llama la
/// obtiene con `ResolveShareableLocation`, que ya respeta el consentimiento
/// y la precisión elegida por la persona para esa familia: este caso de uso
/// nunca la busca por su cuenta.
///
/// Fallos: [CheckInFailureCodes.messageTooLong] y
/// [CheckInFailureCodes.noFamily] (validación), sin sesión
/// (`unauthenticated`) y los del repositorio.
final class SubmitCheckIn {
  new(this._repository, this._ids, this._clock);

  final CheckInRepository _repository;
  final IdGenerator _ids;
  final Clock _clock;

  Future<Result<CheckIn>> call({
    required String familyId,
    required String uid,
    required CheckInKind kind,
    String? message,
    DeviceFix? location,
  }) async {
    if (uid.isEmpty) return const Err(Failure.unauthenticated());
    if (familyId.isEmpty) {
      return const Err(Failure.validation(CheckInFailureCodes.noFamily));
    }
    if (CheckInRules.message(message) case final code?) {
      return Err(Failure.validation(code));
    }
    // Las reglas del servidor miden el texto tal cual: se recorta antes.
    final trimmed = message?.trim();
    return await _repository.submit(
      CheckIn(
        id: _ids.newId(),
        familyId: familyId,
        uid: uid,
        kind: kind,
        createdAt: _clock.now(),
        delivery: DeliveryState.pending,
        message: trimmed == null || trimmed.isEmpty ? null : trimmed,
        location: location?.point,
      ),
    );
  }
}
