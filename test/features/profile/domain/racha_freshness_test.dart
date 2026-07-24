import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/profile/domain/racha_freshness.dart';

// [#552] Unit del decay puro. El frame es ART: un stamp de "hoy" o "ayer"
// (calendario argentino) mantiene el valor; 2+ días lo colapsa a 0; sin stamp
// (doc legacy) el valor pasa tal cual.

void main() {
  // Ancla fija: 2026-07-24 12:00 ART == 15:00Z. Independiente del TZ de la
  // máquina (CI en UTC, dev en ART).
  final now = DateTime.utc(2026, 7, 24, 15);

  DateTime artNoon(int y, int m, int d) => DateTime.utc(y, m, d, 15);

  test('stamp de hoy → valor intacto', () {
    expect(
      effectiveRacha(racha: 3, rachaUpdatedAt: artNoon(2026, 7, 24), now: now),
      3,
    );
  });

  test('stamp de ayer → valor intacto (día de gracia de computeStreak)', () {
    expect(
      effectiveRacha(racha: 3, rachaUpdatedAt: artNoon(2026, 7, 23), now: now),
      3,
    );
  });

  test('stamp de hace 2 días → 0 (la racha ya no está viva)', () {
    expect(
      effectiveRacha(racha: 3, rachaUpdatedAt: artNoon(2026, 7, 22), now: now),
      0,
    );
  });

  test('stamp de hace 10 días → 0', () {
    expect(
      effectiveRacha(racha: 5, rachaUpdatedAt: artNoon(2026, 7, 14), now: now),
      0,
    );
  });

  test('sin stamp (doc legacy pre-#552) → passthrough del valor crudo', () {
    expect(effectiveRacha(racha: 1, rachaUpdatedAt: null, now: now), 1);
    expect(effectiveRacha(racha: null, rachaUpdatedAt: null, now: now), 0);
  });

  test('stamp "futuro" (skew de reloj device vs serverTimestamp) → fresco', () {
    expect(
      effectiveRacha(racha: 2, rachaUpdatedAt: artNoon(2026, 7, 25), now: now),
      2,
    );
  });

  test('borde ART: stamp 23:30 ART de ayer sigue siendo ayer, no anteayer', () {
    // 23:30 ART del 23/07 == 02:30Z del 24/07 — en frame UTC parecería "hoy";
    // el decay debe bucketear en ART (mismo criterio que computeStreak).
    final lateNightArt = DateTime.utc(2026, 7, 24, 2, 30);
    expect(toArgentina(lateNightArt).day, 23, reason: 'sanity del fixture');
    expect(
      effectiveRacha(racha: 4, rachaUpdatedAt: lateNightArt, now: now),
      4,
    );
  });

  test('racha 0 con stamp fresco → 0 (0 es un valor honesto, no se inventa)',
      () {
    expect(
      effectiveRacha(racha: 0, rachaUpdatedAt: artNoon(2026, 7, 24), now: now),
      0,
    );
  });
}
