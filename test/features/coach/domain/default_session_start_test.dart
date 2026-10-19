import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/default_session_start.dart';

/// #1490: "Nueva sesión" arrancaba en 9:00 de HOY aunque ya hubiera pasado,
/// y REGISTRAR SESIÓN rebotaba con "No podés registrar una sesión en el
/// pasado.".
void main() {
  DefaultSessionStart calc(DateTime now, {DateTime? date}) =>
      defaultSessionStart(
        now: now,
        date: date ?? DateTime(now.year, now.month, now.day),
      );

  group('hoy', () {
    test('antes de las 9:00 → se queda en 9:00', () {
      final r = calc(DateTime(2026, 10, 19, 7, 40));
      expect(r.date, DateTime(2026, 10, 19));
      expect((r.hour, r.minute), (9, 0));
    });

    test('9:51 (el caso del reporte) → 10:00', () {
      final r = calc(DateTime(2026, 10, 19, 9, 51));
      expect(r.date, DateTime(2026, 10, 19));
      expect((r.hour, r.minute), (10, 0));
    });

    test('justo 9:00 ya no es futuro → 9:30', () {
      final r = calc(DateTime(2026, 10, 19, 9, 0));
      expect((r.hour, r.minute), (9, 30));
    });

    test('justo en una media hora redonda → la siguiente', () {
      final enPunto = calc(DateTime(2026, 10, 19, 14, 0));
      final yMedia = calc(DateTime(2026, 10, 19, 14, 30));
      expect((enPunto.hour, enPunto.minute), (14, 30));
      expect((yMedia.hour, yMedia.minute), (15, 0));
    });

    test('segundos sueltos cuentan como pasado: 14:29:59 → 14:30', () {
      final r = calc(DateTime(2026, 10, 19, 14, 29, 59));
      expect((r.hour, r.minute), (14, 30));
    });

    test('23:10 → 23:30, todavía hoy', () {
      final r = calc(DateTime(2026, 10, 19, 23, 10));
      expect(r.date, DateTime(2026, 10, 19));
      expect((r.hour, r.minute), (23, 30));
    });

    test('23:30 o más → no queda hora hoy: mañana 9:00', () {
      for (final m in [30, 45, 59]) {
        final r = calc(DateTime(2026, 10, 19, 23, m));
        expect(r.date, DateTime(2026, 10, 20), reason: '23:$m');
        expect((r.hour, r.minute), (9, 0), reason: '23:$m');
      }
    });

    test('pasar a mañana cruza mes y año', () {
      expect(calc(DateTime(2026, 10, 31, 23, 50)).date, DateTime(2026, 11, 1));
      expect(calc(DateTime(2026, 12, 31, 23, 50)).date, DateTime(2027, 1, 1));
    });

    test('el resultado SIEMPRE es posterior a ahora (barrido del día)', () {
      // Barrido minuto a minuto: la garantía es la misma que chequea el
      // submit (startsAt.isAfter(nowWall)).
      for (var min = 0; min < 24 * 60; min++) {
        final now = DateTime(2026, 10, 19, min ~/ 60, min % 60, 30);
        final r = calc(now);
        final startsAt =
            DateTime(r.date.year, r.date.month, r.date.day, r.hour, r.minute);
        expect(startsAt.isAfter(now), isTrue, reason: '$now → $startsAt');
      }
    });
  });

  group('otro día', () {
    test('otro día elegido, aunque hoy sean las 23:50 → 9:00 de ese día', () {
      final r =
          calc(DateTime(2026, 10, 19, 23, 50), date: DateTime(2026, 10, 25));
      expect(r.date, DateTime(2026, 10, 25));
      expect((r.hour, r.minute), (9, 0));
    });
  });

  test('ignora la zona: sólo mira la hora de pared (UTC o local)', () {
    final local = calc(DateTime(2026, 10, 19, 9, 51));
    final utc = defaultSessionStart(
      now: DateTime.utc(2026, 10, 19, 9, 51),
      date: DateTime(2026, 10, 19),
    );
    expect((utc.hour, utc.minute), (local.hour, local.minute));
    expect(utc.date, local.date);
  });
}
