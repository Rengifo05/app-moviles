import 'package:nexo_familia/features/emergency/domain/emergency_dialer.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre el marcador del sistema con `tel:<número>` (url_launcher). No llama:
/// la persona confirma la llamada en su teléfono.
final class UrlLauncherEmergencyDialer implements EmergencyDialer {
  const new();

  @override
  Future<bool> dial(String number) async {
    try {
      return await launchUrl(Uri(scheme: 'tel', path: number));
    } on Object {
      // Sin app de teléfono (tableta, emulador) el plugin lanza: la interfaz
      // muestra el número para marcarlo a mano.
      return false;
    }
  }
}
