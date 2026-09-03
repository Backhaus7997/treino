import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/profile/domain/racha_freshness.dart';

// [#552 → semanas 2026-09-02] Unit del decay puro. El frame es ART y la
// ventana ahora se mide en SEMANAS lunes-domingo: un sello de la semana en
// curso o de la anterior mantiene el valor; 2+ semanas lo colapsa a 0.
// Sin sello → 0, no passthrough: un valor viejo son DÍAS y mostrarlo como
// semanas sería inflar el número en un board público (AGENTS.md §11.1).

void main() {
  // Ancla fija: viernes 2026-07-24 12:00 ART == 15:00Z. Independiente del TZ
  // de la máquina (CI en UTC, dev en ART). Su lunes es el 2026-07-20.
  final now = DateTime.utc(2026, 7, 24, 15);

  DateTime artNoon(int y, int m, int d) => DateTime.utc(y, m, d, 15);

  test('sello de esta semana → valor intacto', () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 22), // miércoles, misma semana
        now: now,
      ),
      3,
    );
  });

  test('sello del lunes de esta semana → valor intacto (borde inclusivo)', () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 20),
        now: now,
      ),
      3,
    );
  });

  test('sello de la semana pasada → intacto: la semana en curso no corta', () {
    // Domingo 19/07, último día de la semana anterior. El atleta todavía no
    // entrenó esta semana, pero `computeWeeklyStreak` no la da por perdida.
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 19),
        now: now,
      ),
      3,
    );
  });

  test('sello de hace 2 semanas → 0 (hubo una semana cerrada sin entrenar)',
      () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 3,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 10), // viernes, 2 semanas atrás
        now: now,
      ),
      0,
    );
  });

  test('sello de hace 10 semanas → 0', () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 5,
        rachaSemanasUpdatedAt: artNoon(2026, 5, 15),
        now: now,
      ),
      0,
    );
  });

  test('sin sello (doc que nunca escribió el campo nuevo) → 0, NO passthrough',
      () {
    // El cambio de default respecto de la versión por días es deliberado: un
    // valor sin sello viene de la era en DÍAS y mostrarlo como semanas pondría
    // un 23 donde corresponde un 3.
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 23,
        rachaSemanasUpdatedAt: null,
        now: now,
      ),
      0,
    );
    expect(
      effectiveRachaSemanas(
        rachaSemanas: null,
        rachaSemanasUpdatedAt: null,
        now: now,
      ),
      0,
    );
  });

  test('sello "futuro" (skew de reloj device vs serverTimestamp) → fresco', () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 2,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 27), // lunes siguiente
        now: now,
      ),
      2,
    );
  });

  test('borde ART: domingo 23:30 ART sigue en la semana que cierra', () {
    // 23:30 ART del domingo 19/07 == 02:30Z del lunes 20/07 — en frame UTC
    // parecería la semana en curso; en ART todavía es la anterior. Cae en la
    // semana de gracia igual, así que el valor sobrevive; el assert de sanity
    // es el que fija que el bucketeo se hace en ART.
    final lateSundayArt = DateTime.utc(2026, 7, 20, 2, 30);
    expect(toArgentina(lateSundayArt).weekday, DateTime.sunday,
        reason: 'sanity del fixture');
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 4,
        rachaSemanasUpdatedAt: lateSundayArt,
        now: now,
      ),
      4,
    );
  });

  test('racha 0 con sello fresco → 0 (0 es un valor honesto, no se inventa)',
      () {
    expect(
      effectiveRachaSemanas(
        rachaSemanas: 0,
        rachaSemanasUpdatedAt: artNoon(2026, 7, 24),
        now: now,
      ),
      0,
    );
  });
}
