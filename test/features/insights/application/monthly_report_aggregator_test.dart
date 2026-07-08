import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/application/monthly_report_aggregator.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

Session _session(
  String id,
  DateTime startedAt, {
  SessionStatus status = SessionStatus.finished,
  int durationMin = 0,
  double totalVolumeKg = 0,
}) =>
    Session(
      id: id,
      uid: 'athlete1',
      routineId: 'r1',
      routineName: 'Rutina A',
      startedAt: startedAt,
      status: status,
      durationMin: durationMin,
      totalVolumeKg: totalVolumeKg,
    );

void main() {
  group('aggregateMonthlyReport', () {
    test('buckets sessions into their calendar month (local time)', () {
      // 'now' anchors the last-12-months window: Jan 2026.
      final now = DateTime(2026, 1, 15);
      final sessions = [
        _session('s1', DateTime(2025, 6, 10),
            durationMin: 40, totalVolumeKg: 1000),
        _session('s2', DateTime(2025, 6, 20),
            durationMin: 30, totalVolumeKg: 500),
        _session('s3', DateTime(2025, 7, 1), durationMin: 50),
      ];
      final setsCountBySessionId = {'s1': 12, 's2': 8, 's3': 10};

      final report = aggregateMonthlyReport(
        sessions: sessions,
        setsCountBySessionId: setsCountBySessionId,
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        now: now,
      );

      expect(report.points.length, 12);

      final june = report.points.firstWhere(
        (p) => p.month.year == 2025 && p.month.month == 6,
      );
      expect(june.workoutsCount, 2);
      expect(june.durationMin, 70);
      expect(june.volumeKg, 1500);
      expect(june.setsCount, 20);

      final july = report.points.firstWhere(
        (p) => p.month.year == 2025 && p.month.month == 7,
      );
      expect(july.workoutsCount, 1);
      expect(july.durationMin, 50);
      expect(july.setsCount, 10);
    });

    test('produces exactly 12 points, oldest to newest, ending at "now"', () {
      final now = DateTime(2026, 3, 5);
      final report = aggregateMonthlyReport(
        sessions: const [],
        setsCountBySessionId: const {},
        durationMinBySessionId: const {},
        now: now,
      );

      expect(report.points.length, 12);
      expect(report.points.first.month, DateTime(2025, 4, 1));
      expect(report.points.last.month, DateTime(2026, 3, 1));
    });

    test('empty months render as zero-valued points, not gaps', () {
      final now = DateTime(2026, 1, 1);
      final report = aggregateMonthlyReport(
        sessions: const [],
        setsCountBySessionId: const {},
        durationMinBySessionId: const {},
        now: now,
      );

      expect(report.points.length, 12);
      for (final p in report.points) {
        expect(p.workoutsCount, 0);
        expect(p.durationMin, 0);
        expect(p.volumeKg, 0);
        expect(p.setsCount, 0);
      }
    });

    test('handles year rollover (Jan back to previous December)', () {
      final now = DateTime(2026, 1, 20);
      final sessions = [
        _session('s1', DateTime(2025, 2, 1)),
      ];

      final report = aggregateMonthlyReport(
        sessions: sessions,
        setsCountBySessionId: const {},
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        now: now,
      );

      expect(report.points.first.month, DateTime(2025, 2, 1));
      expect(report.points.last.month, DateTime(2026, 1, 1));
      final feb = report.points.firstWhere(
        (p) => p.month.year == 2025 && p.month.month == 2,
      );
      expect(feb.workoutsCount, 1);
    });

    test('current partial month includes sessions up to "now"', () {
      final now = DateTime(2026, 6, 15);
      final sessions = [
        _session('s1', DateTime(2026, 6, 1), durationMin: 20),
        _session('s2', DateTime(2026, 6, 30), durationMin: 20),
      ];

      final report = aggregateMonthlyReport(
        sessions: sessions,
        setsCountBySessionId: const {},
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        now: now,
      );

      final currentMonth = report.points.last;
      expect(currentMonth.month, DateTime(2026, 6, 1));
      // Both sessions in June counted, even the one on day 30 (after 'now'
      // within the same month) — the bucket is the whole calendar month.
      expect(currentMonth.workoutsCount, 2);
    });

    test('excludes non-finished sessions', () {
      final now = DateTime(2026, 1, 1);
      final sessions = [
        _session('s1', DateTime(2025, 12, 5), status: SessionStatus.active),
      ];

      final report = aggregateMonthlyReport(
        sessions: sessions,
        setsCountBySessionId: const {},
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        now: now,
      );

      final dec = report.points.firstWhere(
        (p) => p.month.year == 2025 && p.month.month == 12,
      );
      expect(dec.workoutsCount, 0);
    });

    test('sessions older than the 12-month window are excluded', () {
      final now = DateTime(2026, 1, 1);
      final sessions = [
        _session('old', DateTime(2024, 1, 1)),
      ];

      final report = aggregateMonthlyReport(
        sessions: sessions,
        setsCountBySessionId: const {},
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        now: now,
      );

      for (final p in report.points) {
        expect(p.workoutsCount, 0);
      }
    });

    test('daily duration report returns every day in selected month', () {
      final month = DateTime(2026, 6, 1);
      final sessions = [
        _session('s1', DateTime(2026, 6, 1), durationMin: 40),
        _session('s2', DateTime(2026, 6, 1, 18), durationMin: 25),
        _session('s3', DateTime(2026, 6, 2), durationMin: 50),
        _session('s4', DateTime(2026, 7, 1), durationMin: 90),
      ];

      final points = aggregateDailyDurationReport(
        sessions: sessions,
        durationMinBySessionId: {
          for (final session in sessions) session.id: session.durationMin,
        },
        month: month,
      );

      expect(points.length, 30);
      expect(points[0].durationMin, 65);
      expect(points[1].durationMin, 50);
      expect(points.last.durationMin, 0);
    });
  });
}
