/// Conversión tolerante de valores que vienen del backend (Firestore,
/// Functions o el backend de demostración).
abstract final class RemoteJson {
  /// Acepta `DateTime` o milisegundos desde la época (UTC).
  static DateTime? date(Object? value) => switch (value) {
    final DateTime d => d.toUtc(),
    final int millis => DateTime.fromMillisecondsSinceEpoch(
      millis,
      isUtc: true,
    ),
    final double millis when millis.isFinite =>
      DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true),
    _ => null,
  };

  static String? string(Object? value) => value is String ? value : null;

  static int? integer(Object? value) => switch (value) {
    final int v => v,
    final double v when v.isFinite && v == v.roundToDouble() => v.round(),
    _ => null,
  };

  static double? number(Object? value) => switch (value) {
    final num v when v.isFinite => v.toDouble(),
    _ => null,
  };
}
