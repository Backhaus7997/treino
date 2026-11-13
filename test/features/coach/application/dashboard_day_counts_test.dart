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
  AppointmentAttendance? attendance,
}) {
  return Appointment(
    id: 't_${startsAt.millisecondsSinceEpoch}',
    trainerId: 't',
    athleteId: 'a',
    athleteDisplayName: 'Alumno',
    startsAt: startsAt,
    durationMin: durationMin,
    status: status,
    attendance: attendance,
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

  // #1737: «ausente» (#1492) es un `attendance` sobre un turno `confirmed`, no
  // un status, y el conteo lo leía como COMPLETADO.
  group('dashboard_day_counts — AUSENTE (#1737)', () {
    final now = DateTime.utc(2026, 6, 16, 12, 0); // 12:00 ART

    test('un turno terminado y marcado ausente NO cuenta como completado', () {
      final absent = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 9, 0), // terminó 10:00 < 12:00
        durationMin: 60,
        attendance: AppointmentAttendance.absent,
      );
      final given = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 10, 0), // terminó 11:00 < 12:00
        durationMin: 60,
      );

      final counts = dashboardDayCounts([absent, given], now);

      expect(counts.done, 1, reason: 'sólo el que se dio');
      expect(counts.absent, 1);
      expect(counts.pending, 0);
      expect(counts.cancelled, 0);
    });

    test('un turno EN CURSO marcado ausente tampoco queda pendiente', () {
      // El PF puede marcarlo apenas empieza la sesión (#1492): ya no hay nada
      // por hacer con ella.
      final inProgress = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 11, 30), // 11:30–12:30, sigue
        durationMin: 60,
        attendance: AppointmentAttendance.absent,
      );

      final counts = dashboardDayCounts([inProgress], now);

      expect(counts.absent, 1);
      expect(counts.pending, 0);
      expect(counts.done, 0);
    });

    test('el día cierra: pendiente + completado + ausente + cancelado = turnos',
        () {
      final appts = [
        _appt(startsAt: DateTime.utc(2026, 6, 16, 8, 0), durationMin: 60),
        _appt(
          startsAt: DateTime.utc(2026, 6, 16, 9, 0),
          durationMin: 60,
          attendance: AppointmentAttendance.absent,
        ),
        _appt(
          startsAt: DateTime.utc(2026, 6, 16, 10, 0),
          durationMin: 60,
          status: AppointmentStatus.cancelled,
        ),
        _appt(startsAt: DateTime.utc(2026, 6, 16, 18, 0), durationMin: 60),
      ];

      final counts = dashboardDayCounts(appts, now);

      expect(counts.done, 1);
      expect(counts.absent, 1);
      expect(counts.cancelled, 1);
      expect(counts.pending, 1);
      expect(
        counts.done + counts.absent + counts.cancelled + counts.pending,
        appts.length,
      );
    });

    test(
        'un turno cancelado nunca cuenta como ausente, aunque arrastre '
        'attendance', () {
      final cancelled = _appt(
        startsAt: DateTime.utc(2026, 6, 16, 9, 0),
        durationMin: 60,
        status: AppointmentStatus.cancelled,
        attendance: AppointmentAttendance.absent,
      );

      final counts = dashboardDayCounts([cancelled], now);

      expect(counts.cancelled, 1);
      expect(counts.absent, 0);
    });

    test('un ausente de AYER no entra al resumen de hoy', () {
      final yesterday = _appt(
        startsAt: DateTime.utc(2026, 6, 15, 9, 0),
        durationMin: 60,
        attendance: AppointmentAttendance.absent,
      );

      expect(dashboardDayCounts([yesterday], now).absent, 0);
    });

    test('`absent` es opcional en el constructor (default 0)', () {
      const counts = DashboardDayCounts(pending: 1, done: 2, cancelled: 3);
      expect(counts.absent, 0);
    });
  });
}
