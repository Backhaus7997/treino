import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/domain/wear_timer_sync.dart';

void main() {
  const arranque = 1700000000000;

  int restante({
    int seconds = 30,
    int startedAtEpochMs = arranque,
    required int nowEpochMs,
  }) =>
      wearRemainingSeconds(
        seconds: seconds,
        startedAtEpochMs: startedAtEpochMs,
        nowEpochMs: nowEpochMs,
      );

  test('descuenta la latencia del canal', () {
    // El caso normal: el mensaje tardó 400 ms en cruzar.
    expect(restante(nowEpochMs: arranque + 400), 30);
    // Y dos segundos después, quedan 28.
    expect(restante(nowEpochMs: arranque + 2000), 28);
  });

  test('sin descontar, los dos aparatos mostrarían números distintos', () {
    // Control del punto: si devolviera siempre `seconds`, este caso daría 30.
    expect(restante(nowEpochMs: arranque + 10000), 20);
  });

  test('un temporizador ya vencido devuelve 0', () {
    expect(restante(nowEpochMs: arranque + 31000), 0);
  });

  test('si el otro reloj cree estar en el FUTURO, se usa la duración entera',
      () {
    // Desfasaje de reloj: sin este guard el temporizador arrancaría con MÁS
    // tiempo del que pide el plan.
    expect(restante(nowEpochMs: arranque - 60000), 30);
  });

  test('un desfasaje absurdo no mata el temporizador', () {
    // "Arrancó hace 5 minutos" para un ejercicio de 30 s no es que cruzó tarde:
    // es un reloj mal puesto. Preferible correrlo por la latencia que hacerlo
    // nacer muerto.
    expect(restante(nowEpochMs: arranque + 300000), 30);
  });

  test('una duración inválida no arranca nada', () {
    expect(restante(seconds: 0, nowEpochMs: arranque), 0);
    expect(restante(seconds: -5, nowEpochMs: arranque), 0);
  });
}
