/// Fuente de tiempo inyectable. Devuelve siempre UTC para que la lógica de
/// dominio (antigüedad de ubicaciones, reintentos, expiraciones) sea
/// determinista en pruebas e independiente de la zona horaria.
abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const new();

  @override
  DateTime now() => DateTime.now().toUtc();
}
