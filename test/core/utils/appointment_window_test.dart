// QA-COA-007 / QA-HOME-009: the rolling appointment window must NOT lose the
// previous December during January. The old clamp
// `now.month - 1 < 1 ? 1 : now.month - 1` started the window on January 1st of
// the current year; the fix relies on Dart's DateTime month normalization
// (month 0 → December of the prior year), so no clamp is needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/appointment_window.dart';

void main() {
  group('rollingAppointmentWindow', () {
    test('January rolls back to December of the PREVIOUS year (regression)',
        () {
      final w = rollingAppointmentWindow(DateTime.utc(2027, 1, 5));
      expect(w.from, DateTime.utc(2026, 12, 1));
      expect(w.to, DateTime.utc(2028, 1, 1));
    });

    test('mid-year: from = first day of the previous month', () {
      final w = rollingAppointmentWindow(DateTime.utc(2027, 6, 15));
      expect(w.from, DateTime.utc(2027, 5, 1));
      expect(w.to, DateTime.utc(2028, 6, 1));
    });

    test('February rolls back to January of the same year', () {
      final w = rollingAppointmentWindow(DateTime.utc(2027, 2, 10));
      expect(w.from, DateTime.utc(2027, 1, 1));
      expect(w.to, DateTime.utc(2028, 2, 1));
    });

    test('December: from = November, to = next December', () {
      final w = rollingAppointmentWindow(DateTime.utc(2027, 12, 31));
      expect(w.from, DateTime.utc(2027, 11, 1));
      expect(w.to, DateTime.utc(2028, 12, 1));
    });

    test('bounds are UTC and to is after from', () {
      final w = rollingAppointmentWindow(DateTime.utc(2027, 3, 20));
      expect(w.from.isUtc, isTrue);
      expect(w.to.isUtc, isTrue);
      expect(w.to.isAfter(w.from), isTrue);
    });

    test('repro: a Dec 28 appointment is inside the January window', () {
      // System date in January; a late-December appointment must be included.
      final w = rollingAppointmentWindow(DateTime.utc(2027, 1, 5));
      final decAppointment = DateTime.utc(2026, 12, 28, 10);
      expect(!decAppointment.isBefore(w.from), isTrue); // >= from
      expect(decAppointment.isBefore(w.to), isTrue); // < to
    });
  });
}
