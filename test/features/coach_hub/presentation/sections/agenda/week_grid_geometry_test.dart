// PR-A — la geometría de la grilla semanal es pura a propósito: se testea con
// `test()` plano, sin WidgetTester. Los casos peligrosos son el snapping sobre
// las 24:00, los cruzadores de medianoche y el guard endHour > startHour.
//
// ADR-7: `startsAt` es wall-clock UTC; `hour`/`minute` YA son hora de
// Argentina. Ningún test debe usar `.toLocal()`.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/week_grid_geometry.dart';

Appointment _appt({
  required int hour,
  required int minute,
  required int durationMin,
  int day = 1,
}) =>
    Appointment(
      id: 'tA_${day}_${hour}_$minute',
      trainerId: 'tA',
      athleteId: 'aB',
      athleteDisplayName: 'Juan',
      startsAt: DateTime.utc(2026, 6, day, hour, minute),
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
    );

void main() {
  // Grilla por defecto: 07:00–22:00, columnas de 149px (viewport 1440).
  const geo = WeekGridGeometry(startHour: 7, endHour: 22, colWidth: 149.0);

  group('WeekGridGeometry.yForMinute / minuteAtY', () {
    test('the first visible minute maps to y = 0', () {
      expect(geo.yForMinute(geo.startHour * 60), 0.0);
    });

    test('90 minutes below the top maps to 96px (64px per hour)', () {
      expect(geo.yForMinute(geo.startHour * 60 + 90), 96.0);
    });

    test('the last visible minute maps exactly to contentHeight', () {
      expect(geo.yForMinute(geo.endHour * 60), geo.contentHeight);
    });

    test('minuteAtY is the inverse of yForMinute (roundtrip)', () {
      for (var m = geo.startHour * 60; m <= geo.endHour * 60; m += 7) {
        expect(
          geo.minuteAtY(geo.yForMinute(m)).round(),
          m,
          reason: 'roundtrip failed at minute $m',
        );
      }
    });

    test('a widened range shifts the origin, not the scale', () {
      const wide = WeekGridGeometry(startHour: 6, endHour: 24, colWidth: 149.0);
      expect(wide.yForMinute(6 * 60), 0.0);
      // 07:00 is one hour below the top of a 06:00-based grid.
      expect(wide.yForMinute(7 * 60), kWeekHourHeight);
    });
  });

  group('WeekGridGeometry.contentHeight', () {
    test('07:00–22:00 is 15 hours × 64px', () {
      expect(geo.contentHeight, 15 * kWeekHourHeight);
      expect(geo.contentHeight, 960.0);
    });

    test('a full 00:00–24:00 day is 24 hours × 64px', () {
      const full = WeekGridGeometry(startHour: 0, endHour: 24, colWidth: 100.0);
      expect(full.contentHeight, 1536.0);
    });
  });

  group('WeekGridGeometry.snap', () {
    test('snaps to the nearest 15-minute step', () {
      expect(geo.snap(0), 0);
      expect(geo.snap(7), 0); // below the 7.5 midpoint
      expect(geo.snap(8), 15); // above the 7.5 midpoint
      expect(geo.snap(22), 15); // below the 22.5 midpoint
      expect(geo.snap(23), 30); // above the 22.5 midpoint
      expect(geo.snap(15), 15);
      expect(geo.snap(600), 600);
    });

    test('negative minutes clamp to 0', () {
      expect(geo.snap(-1), 0);
      expect(geo.snap(-20), 0);
      expect(geo.snap(-1000), 0);
    });

    test('minute 1435 clamps to 1425 instead of producing an invalid 24:00',
        () {
      // THE bug this clamp exists for: 1435 / 15 = 95.67 → rounds to 96 →
      // 1440 → TimeOfDay(hour: 24, minute: 0), which is invalid and blows up
      // NewSessionDialog. Note 1432 → 1425 does NOT exercise the clamp.
      expect(geo.snap(1435), kWeekMaxSnapMin);
      expect(geo.snap(1435), 1425);
      expect(geo.snap(1440), 1425);
      expect(geo.snap(9999), 1425);
    });

    test('1432 rounds down naturally, without hitting the clamp', () {
      expect(geo.snap(1432), 1425);
    });

    test('every snapped value is a valid TimeOfDay', () {
      for (var y = -50.0; y <= geo.contentHeight + 50; y += 3.5) {
        final m = geo.snap(geo.minuteAtY(y));
        expect(m % kWeekSnapMin, 0, reason: 'minute $m is not on the grid');
        expect(m ~/ 60, inInclusiveRange(0, 23), reason: 'invalid hour for $m');
        expect(m % 60, inInclusiveRange(0, 59));
      }
    });
  });

  group('weekHourRange', () {
    test('an empty week falls back to the 07:00–22:00 seed', () {
      final r = weekHourRange(const []);
      expect(r.startHour, 7);
      expect(r.endHour, 22);
    });

    test('an early session widens startHour', () {
      final r = weekHourRange([_appt(hour: 6, minute: 15, durationMin: 60)]);
      expect(r.startHour, 6);
      expect(r.endHour, 22);
    });

    test('a 22:30 + 90min session widens endHour to 24', () {
      final r = weekHourRange([_appt(hour: 22, minute: 30, durationMin: 90)]);
      expect(r.startHour, 7);
      expect(r.endHour, 24);
    });

    test('a 23:30 + 60min crosser clamps endHour from 25 down to 24', () {
      final r = weekHourRange([_appt(hour: 23, minute: 30, durationMin: 60)]);
      expect(r.endHour, 24);
    });

    test('the range is the UNION across all seven days, not per-day', () {
      // Monday early, Sunday late — one shared vertical scale, otherwise the
      // seven columns would not align.
      final r = weekHourRange([
        _appt(day: 1, hour: 6, minute: 0, durationMin: 60),
        _appt(day: 7, hour: 22, minute: 45, durationMin: 60),
      ]);
      expect(r.startHour, 6);
      expect(r.endHour, 24);
    });

    test('endHour is always strictly greater than startHour', () {
      final cases = <List<Appointment>>[
        const [],
        [_appt(hour: 0, minute: 0, durationMin: 30)],
        [_appt(hour: 23, minute: 59, durationMin: 1)],
        [_appt(hour: 23, minute: 0, durationMin: 10000)],
        [
          _appt(day: 1, hour: 0, minute: 0, durationMin: 15),
          _appt(day: 4, hour: 23, minute: 45, durationMin: 600),
        ],
      ];
      for (final c in cases) {
        final r = weekHourRange(c);
        expect(r.endHour, greaterThan(r.startHour));
        expect(r.startHour, inInclusiveRange(0, 23));
        expect(r.endHour, inInclusiveRange(1, 24));
      }
    });

    test('a bogus multi-day durationMin still clamps endHour to 24', () {
      // durationMin is an unvalidated int on the wire (firestore.rules has no
      // shape validation), so a garbage value must not blow up the geometry.
      final r = weekHourRange([_appt(hour: 9, minute: 0, durationMin: 10000)]);
      expect(r.endHour, 24);
    });
  });

  group('weekStartFor', () {
    // 2026-06-01 is a Monday (ISO weekday == 1).
    final monday = DateTime.utc(2026, 6, 1);

    test('the fixture week really does start on a Monday', () {
      expect(monday.weekday, DateTime.monday);
    });

    test('every day of the week resolves to the same Monday', () {
      for (var i = 0; i < 7; i++) {
        final anchor = DateTime.utc(2026, 6, 1 + i, 18, 42);
        expect(
          weekStartFor(anchor),
          monday,
          reason: 'failed for ${anchor.toIso8601String()}',
        );
      }
    });

    test('the result is always UTC midnight', () {
      final start = weekStartFor(DateTime.utc(2026, 6, 4, 23, 59));
      expect(start.isUtc, isTrue);
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.millisecond, 0);
      expect(start.microsecond, 0);
    });

    test('a non-UTC anchor still yields a UTC Monday', () {
      // Dart's operator== includes isUtc, so a local result would silently
      // fail every day-bucket comparison in the grid.
      final start = weekStartFor(DateTime(2026, 6, 4, 15, 30));
      expect(start.isUtc, isTrue);
      expect(start, monday);
    });

    test('crosses a month boundary backwards', () {
      // 2026-07-01 is a Wednesday → its Monday is 2026-06-29.
      expect(DateTime.utc(2026, 7, 1).weekday, DateTime.wednesday);
      expect(weekStartFor(DateTime.utc(2026, 7, 1)), DateTime.utc(2026, 6, 29));
    });

    test('crosses a year boundary backwards', () {
      // 2027-01-01 is a Friday → its Monday is 2026-12-28.
      expect(DateTime.utc(2027, 1, 1).weekday, DateTime.friday);
      expect(
        weekStartFor(DateTime.utc(2027, 1, 1)),
        DateTime.utc(2026, 12, 28),
      );
    });

    test('a Monday anchor is idempotent', () {
      expect(weekStartFor(monday), monday);
      expect(weekStartFor(weekStartFor(monday)), monday);
    });
  });
}
