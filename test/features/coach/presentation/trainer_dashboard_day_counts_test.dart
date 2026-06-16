// Regression test for the "Resumen del día" classification bug:
// an in-progress confirmed session (started but not yet ended) must count as
// PENDING — not DONE. A session only becomes DONE once startsAt + durationMin
// has elapsed. See dashboardDayCounts in trainer_dashboard_tab.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';

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
  group('dashboardDayCounts — done/pending split by session end', () {
    test(
      'in-progress session (started 5 min ago, 60 min long) counts as pending, '
      'not done',
      () {
        final now = DateTime.utc(2026, 6, 16, 10, 5);
        final inProgress = _appt(
          startsAt: DateTime.utc(2026, 6, 16, 10, 0), // started 5 min ago
          durationMin: 60, // ends at 11:00 — still ongoing
        );

        final counts = dashboardDayCounts([inProgress], now);

        expect(counts.pending, 1, reason: 'ongoing session must stay pending');
        expect(counts.done, 0, reason: 'must not be counted as completed yet');
        expect(counts.cancelled, 0);
      },
    );

    test('session whose end has passed counts as done', () {
      final now = DateTime.utc(2026, 6, 16, 11, 30);
      final finished = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60, // ended at 11:00, before now (11:30)
      );

      final counts = dashboardDayCounts([finished], now);

      expect(counts.done, 1);
      expect(counts.pending, 0);
    });

    test('future session counts as pending', () {
      final now = DateTime.utc(2026, 6, 16, 9, 0);
      final future = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 18, 0),
        durationMin: 45,
      );

      final counts = dashboardDayCounts([future], now);

      expect(counts.pending, 1);
      expect(counts.done, 0);
    });

    test('cancelled session is counted as cancelled, never pending/done', () {
      final now = DateTime.utc(2026, 6, 16, 12, 0);
      final cancelled = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0),
        durationMin: 60,
        status: AppointmentStatus.cancelled,
      );

      final counts = dashboardDayCounts([cancelled], now);

      expect(counts.cancelled, 1);
      expect(counts.pending, 0);
      expect(counts.done, 0);
    });

    test('only today\'s appointments are classified', () {
      final now = DateTime.utc(2026, 6, 16, 12, 0);
      final yesterday = _appt(
        startsAt: DateTime.utc(2026, 6, 15, 10, 0),
        durationMin: 60,
      );
      final today = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 18, 0),
        durationMin: 60,
      );

      final counts = dashboardDayCounts([yesterday, today], now);

      expect(counts.pending, 1, reason: 'only today\'s future session counts');
      expect(counts.done, 0);
    });
  });
}
