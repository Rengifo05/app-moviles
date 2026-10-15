import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// "hace un momento", "hace 3 min", "hace 2 h", "hace 4 días".
///
/// Una fecha futura (reloj del dispositivo adelantado) se muestra como
/// "hace un momento" en lugar de un valor negativo.
String relativeTime(AppLocalizations l10n, DateTime then, DateTime now) {
  final age = now.difference(then);
  if (age < const Duration(minutes: 1)) return l10n.relativeJustNow;
  if (age < const Duration(hours: 1)) {
    return l10n.relativeMinutes(age.inMinutes);
  }
  if (age < const Duration(days: 1)) return l10n.relativeHours(age.inHours);
  return l10n.relativeDays(age.inDays);
}
