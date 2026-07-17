// Task 1.1 RED — direct-import test of the lifted dashboard_day_counts.dart
// Verifies that DashboardDayCounts and dashboardDayCounts are importable
// directly from the application layer (not via the presentation re-export).
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/application/dashboard_day_counts.dart';

Appointment _appt({
  required DateTime startsAt,
  required int durationMin,
  AppointmentStatus status = AppointmentStatus.confirmed,
}) {
  return Appointment(
    id: 't_${startsAt.millisecondsSinceEpoch}',
    trainerId: 't',
    athleteId: 'a',
    athleteDisplayName: 'Alumno',
    startsAt: startsAt,
    durationMin: durationMin,
    status: status,
  );
}

void main() {
  group('dashboard_day_counts — application layer direct import', () {
    test('DashboardDayCounts is constructable from application import', () {
      const counts = DashboardDayCounts(pending: 3, done: 2, cancelled: 1);
      expect(counts.pending, 3);
      expect(counts.done, 2);
      expect(counts.cancelled, 1);
    });

    // QA-HOME-001: startsAt and now are Argentina wall-clock (fake-UTC —
    // DateTime.utc with ART calendar/hour fields, as the booking UI writes
    // them). DateTime.utc(y,m,d,H,M) here means "H:M ART on that ART day".
    test('classifies an in-progress session as pending', () {
      final now = DateTime.utc(2026, 6, 16, 10, 5); // 10:05 ART
      final appt = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0), // 10:00–11:00 ART
        durationMin: 60,
      );
      final counts = dashboardDayCounts([appt], now);
      expect(counts.pending, 1); // ends 11:00 > now 10:05
      expect(counts.done, 0);
    });

    test('classifies an ended session as done', () {
      final now = DateTime.utc(2026, 6, 16, 11, 30); // 11:30 ART
      final appt = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60,
      );
      final counts = dashboardDayCounts([appt], now);
      expect(counts.done, 1); // ended 11:00 <= now 11:30
      expect(counts.pending, 0);
    });

    // QA-HOME-001 regression: a session that hasn't started yet must be pending,
    // NOT done. With the old real-UTC `now` (3h ahead of the wall-clock
    // startsAt), a session 2h in the future was miscounted as already done.
    test('a not-yet-started session later today counts as pending', () {
      final now = DateTime.utc(2026, 6, 16, 10, 0); // 10:00 ART
      final appt = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 12, 0), // 12:00 ART, in 2h
        durationMin: 60,
      );
      final counts = dashboardDayCounts([appt], now);
      expect(counts.pending, 1);
      expect(counts.done, 0);
    });

    // QA-HOME-001 regression: 00:00–02:59 ART sessions belong to their own ART
    // day. The old toArgentina() double-shift moved them a day back, dropping
    // them from "today".
    test('an early-morning (00:00–02:59 ART) session buckets to today', () {
      final now = DateTime.utc(2026, 6, 16, 8, 0); // 08:00 ART Jun 16
      final earlyToday = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 1, 0), // 01:00 ART Jun 16
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );
      final yesterday = _appt(
        startsAt: DateTime.utc(2026, 6, 15, 23, 0), // 23:00 ART Jun 15
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );
      final counts = dashboardDayCounts([earlyToday, yesterday], now);
      expect(counts.cancelled, 1); // only the 01:00 Jun 16 session is "today"
    });
  });
}
