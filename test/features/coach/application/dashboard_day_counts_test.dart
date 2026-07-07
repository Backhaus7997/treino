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

    test('dashboardDayCounts classifies pending session correctly', () {
      final now = DateTime.utc(2026, 6, 16, 10, 5);
      final appt = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60,
      );
      final counts = dashboardDayCounts([appt], now);
      expect(counts.pending, 1);
      expect(counts.done, 0);
    });

    test('dashboardDayCounts classifies done session correctly', () {
      final now = DateTime.utc(2026, 6, 16, 11, 30);
      final appt = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60,
      );
      final counts = dashboardDayCounts([appt], now);
      expect(counts.done, 1);
      expect(counts.pending, 0);
    });

    test('appointments are bucketed by the ART day, spanning UTC midnight', () {
      // now = 2026-06-17 02:00 UTC == 23:00 ART Jun 16 → ART "today" is Jun 16.
      final now = DateTime.utc(2026, 6, 17, 2, 0);
      // Both appointments are ART Jun 16 (today) but straddle UTC midnight.
      final noon = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 15, 0), // 12:00 ART Jun 16
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );
      final lateEvening = _appt(
        startsAt: DateTime.utc(2026, 6, 17, 1, 30), // 22:30 ART Jun 16
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );
      final counts = dashboardDayCounts([noon, lateEvening], now);
      // ART bucketing counts BOTH; the old UTC-day math would drop the noon one.
      expect(counts.cancelled, 2);
    });
  });
}
