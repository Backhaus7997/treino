/// Formatea segundos totales como MM:SS (máx 99:59). Diseño §9.4.
///
/// Vive acá y no adentro de una pantalla porque lo comparten el player y la
/// fila de ejercicios por tiempo. Es el formato del TELÉFONO: el reloj muestra
/// `45` y `1:30` en vez de `00:45` y `01:30` porque en una pantalla de 40mm cada
/// carácter cuenta. Esa divergencia es deliberada y está anotada en
/// `conformance/duration_timer.json`, que deja el TEXTO fuera del contrato y
/// pone bajo contrato el número de segundos, que sí tiene que coincidir.
String formatMMSS(int totalSeconds) {
  final m = (totalSeconds ~/ 60).clamp(0, 99).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
