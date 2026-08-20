/// Cuántos segundos le quedan a un temporizador que arrancó en OTRO aparato.
///
/// ## Por qué no alcanza con mandar la duración
///
/// El mensaje tarda en cruzar. Si el receptor arrancara su temporizador con los
/// segundos completos, los dos aparatos mostrarían números distintos: el que lo
/// inició ya consumió la latencia del canal y el otro empieza de cero. En un
/// ejercicio de 30 segundos eso se ve.
///
/// Por eso viaja además [startedAtEpochMs] y acá se descuenta lo transcurrido.
///
/// ## Por qué hay un guard de sanidad
///
/// El instante viaja en reloj de pared, y dos aparatos pueden tenerlo corrido
/// —zona horaria mal puesta, NTP que todavía no ajustó—. Un desfasaje grande
/// haría arrancar el temporizador ya vencido, o con más tiempo del que pidió el
/// plan. Cuando lo transcurrido no tiene sentido, se ignora y se usa la
/// duración completa: preferible un temporizador corrido por la latencia que
/// uno que nace muerto.
///
/// Devuelve 0 cuando el temporizador ya venció de verdad — quien llama decide
/// si eso significa no arrancar nada.
int wearRemainingSeconds({
  required int seconds,
  required int startedAtEpochMs,
  required int nowEpochMs,
}) {
  if (seconds <= 0) return 0;

  final transcurridoMs = nowEpochMs - startedAtEpochMs;

  // Negativo = el otro aparato cree estar en el futuro. Positivo y mayor que la
  // duración = o venció, o el reloj está corrido. El primero se resuelve
  // ignorándolo; el segundo hay que distinguirlo.
  if (transcurridoMs < 0) return seconds;

  final transcurrido = transcurridoMs ~/ 1000;

  // Más del doble de la duración no es "venció hace un rato": es un reloj mal
  // puesto. Un temporizador de 30 s que dice llevar 5 minutos no cruzó tarde.
  if (transcurrido > seconds * 2) return seconds;

  final restante = seconds - transcurrido;
  return restante > 0 ? restante : 0;
}
