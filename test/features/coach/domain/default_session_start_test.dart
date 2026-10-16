import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/default_session_start.dart';

void main() {
  DateTime wall(int d, int h, [int m = 0]) => DateTime.utc(2026, 10, d, h, m);

  group('defaultSessionStart (#1490)', () {
    test('hoy antes de las 9:00 conserva el default de las 9:00', () {
      final r = defaultSessionStart(day: wall(16, 0), nowWall: wall(16, 7, 30));
      expect(r.date, DateTime.utc(2026, 10, 16));
      expect((r.hour, r.minute), (9, 0));
    });

    test('hoy justo a las 9:00 (no es futuro) propone las 10:00', () {
      final r = defaultSessionStart(day: wall(16, 0), nowWall: wall(16, 9));
      expect(r.date, DateTime.utc(2026, 10, 16));
      expect((r.hour, r.minute), (10, 0));
    });

    test('el caso del QA: 9:51 propone las 10:00 de hoy', () {
      final r = defaultSessionStart(day: wall(16, 0), nowWall: wall(16, 9, 51));
      expect(r.date, DateTime.utc(2026, 10, 16));
      expect((r.hour, r.minute), (10, 0));
    });

    test('a las 22:30 propone las 23:00 de hoy', () {
      final r =
          defaultSessionStart(day: wall(16, 0), nowWall: wall(16, 22, 30));
      expect(r.date, DateTime.utc(2026, 10, 16));
      expect((r.hour, r.minute), (23, 0));
    });

    test('a las 23:10 la próxima hora ya es mañana: mañana a las 9:00', () {
      final r =
          defaultSessionStart(day: wall(16, 0), nowWall: wall(16, 23, 10));
      expect(r.date, DateTime.utc(2026, 10, 17));
      expect((r.hour, r.minute), (9, 0));
    });

    test('cruce de mes: 31/10 23:10 propone 1/11 a las 9:00', () {
      final r = defaultSessionStart(
        day: wall(31, 0),
        nowWall: wall(31, 23, 10),
      );
      expect(r.date, DateTime.utc(2026, 11, 1));
      expect((r.hour, r.minute), (9, 0));
    });

    test('un día futuro conserva las 9:00 aunque hoy ya sea tarde', () {
      final r =
          defaultSessionStart(day: wall(20, 0), nowWall: wall(16, 23, 50));
      expect(r.date, DateTime.utc(2026, 10, 20));
      expect((r.hour, r.minute), (9, 0));
    });

    test('ignora la hora de [day]: sólo cuenta el día de calendario', () {
      final r = defaultSessionStart(day: wall(16, 18), nowWall: wall(16, 10));
      expect(r.date, DateTime.utc(2026, 10, 16));
      expect((r.hour, r.minute), (11, 0));
    });

    test('NUNCA propone algo que no sea posterior a ahora', () {
      for (var h = 0; h < 24; h++) {
        for (final m in [0, 1, 30, 59]) {
          final now = wall(16, h, m);
          final r = defaultSessionStart(day: wall(16, 0), nowWall: now);
          final proposed = DateTime.utc(
            r.date.year,
            r.date.month,
            r.date.day,
            r.hour,
            r.minute,
          );
          expect(
            proposed.isAfter(now),
            isTrue,
            reason: 'a las $h:$m propuso $proposed',
          );
        }
      }
    });
  });
}
