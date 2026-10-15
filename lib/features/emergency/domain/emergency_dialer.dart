/// Abre el marcador del teléfono con un número ya escrito. La persona
/// decide si llama: la app nunca llama ni contacta a los servicios de
/// emergencia por su cuenta.
abstract interface class EmergencyDialer {
  /// `true` si se abrió el marcador; `false` si el dispositivo no puede
  /// (tableta sin telefonía, sin app de teléfono…). Nunca lanza.
  Future<bool> dial(String number);
}
