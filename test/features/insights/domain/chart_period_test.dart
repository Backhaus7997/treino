import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/domain/chart_period.dart';

void main() {
  group('ChartPeriod.last30d (rolling, DEFAULT)', () {
    test('current window is [now-30d, now] inclusive-start/end-of-day', () {
      final now = DateTime(2026, 3, 15);
      final window = ChartPeriod.last30d.windowFor(now);

      // Rolling 30-CALENDAR-DAY inclusive window: currentStart..currentEnd
      // spans exactly 30 days (Feb 14 through Mar 15 inclusive = 30 days).
      expect(window.currentStart, DateTime(2026, 2, 14));
      expect(window.currentEnd, DateTime(2026, 3, 15));
    });

    test('previous window is the 30 days immediately preceding current', () {
      final now = DateTime(2026, 3, 15);
      final window = ChartPeriod.last30d.windowFor(now);

      expect(window.previousEnd, DateTime(2026, 2, 13));
      expect(window.previousStart, DateTime(2026, 1, 15));
    });

    test('rolling window is NOT calendar-month aligned', () {
      // 30 days back from March 15 lands mid-February, not month-start.
      final now = DateTime(2026, 3, 15);
      final window = ChartPeriod.last30d.windowFor(now);
      expect(window.currentStart.day, isNot(1));
    });
  });

  group('ChartPeriod.thisWeek', () {
    test('current window is Monday..Sunday of the week containing `now`', () {
      // 2026-07-07 is a Tuesday.
      final now = DateTime(2026, 7, 7);
      final window = ChartPeriod.thisWeek.windowFor(now);

      expect(window.currentStart, DateTime(2026, 7, 6)); // Monday
      expect(window.currentStart.weekday, DateTime.monday);
      expect(window.currentEnd, DateTime(2026, 7, 12)); // Sunday
      expect(window.currentEnd.weekday, DateTime.sunday);
    });

    test('previous window is the preceding Monday..Sunday week', () {
      final now = DateTime(2026, 7, 7);
      final window = ChartPeriod.thisWeek.windowFor(now);

      expect(window.previousStart, DateTime(2026, 6, 29));
      expect(window.previousEnd, DateTime(2026, 7, 5));
    });

    test('when `now` is exactly Monday, current week starts on `now`', () {
      final now = DateTime(2026, 7, 6); // Monday
      final window = ChartPeriod.thisWeek.windowFor(now);

      expect(window.currentStart, DateTime(2026, 7, 6));
      expect(window.currentEnd, DateTime(2026, 7, 12));
    });
  });

  group('ChartPeriod.month (calendar month)', () {
    test('current window is the full calendar month containing `now`', () {
      final now = DateTime(2026, 7, 15);
      final window = ChartPeriod.month.windowFor(now);

      expect(window.currentStart, DateTime(2026, 7, 1));
      expect(window.currentEnd, DateTime(2026, 7, 31));
    });

    test('previous window is the immediately preceding calendar month', () {
      final now = DateTime(2026, 7, 15);
      final window = ChartPeriod.month.windowFor(now);

      expect(window.previousStart, DateTime(2026, 6, 1));
      expect(window.previousEnd, DateTime(2026, 6, 30));
    });

    test('handles February in a non-leap year (28 days)', () {
      final now = DateTime(2026, 2, 10); // 2026 is not a leap year
      final window = ChartPeriod.month.windowFor(now);

      expect(window.currentStart, DateTime(2026, 2, 1));
      expect(window.currentEnd, DateTime(2026, 2, 28));
    });

    test('handles February in a leap year (29 days)', () {
      final now = DateTime(2028, 2, 10); // 2028 is a leap year
      final window = ChartPeriod.month.windowFor(now);

      expect(window.currentStart, DateTime(2028, 2, 1));
      expect(window.currentEnd, DateTime(2028, 2, 29));
    });

    test('handles a 30-day month (April) followed by previous 31-day month',
        () {
      final now = DateTime(2026, 4, 5);
      final window = ChartPeriod.month.windowFor(now);

      expect(window.currentStart, DateTime(2026, 4, 1));
      expect(window.currentEnd, DateTime(2026, 4, 30));
      expect(window.previousStart, DateTime(2026, 3, 1));
      expect(window.previousEnd, DateTime(2026, 3, 31));
    });

    test(
        'handles January → previous month rolls back to December of the '
        'prior year', () {
      final now = DateTime(2026, 1, 15);
      final window = ChartPeriod.month.windowFor(now);

      expect(window.currentStart, DateTime(2026, 1, 1));
      expect(window.currentEnd, DateTime(2026, 1, 31));
      expect(window.previousStart, DateTime(2025, 12, 1));
      expect(window.previousEnd, DateTime(2025, 12, 31));
    });
  });

  group('DST-safe arithmetic (America/Argentina context)', () {
    // Argentina does not currently observe DST (fixed UTC-3 since 2009), so
    // there is no local transition date to probe directly. The invariant we
    // guard here is the PORTABLE one: all window boundaries are built via
    // DateTime(y, m, d) calendar-constructor arithmetic — never
    // `.add(Duration(days: n))` — so the fix is correct regardless of which
    // timezone the runner/host executes in (including zones that DO observe
    // DST transitions in March/October).
    test('last30d window boundaries have zeroed time-of-day components', () {
      final now = DateTime(2026, 3, 15, 23, 45, 30, 500);
      final window = ChartPeriod.last30d.windowFor(now);

      for (final d in [
        window.currentStart,
        window.previousStart,
        window.previousEnd,
      ]) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
        expect(d.millisecond, 0);
      }
    });

    test('thisWeek window boundaries have zeroed time-of-day components', () {
      final now = DateTime(2026, 7, 7, 23, 45, 30, 500);
      final window = ChartPeriod.thisWeek.windowFor(now);

      for (final d in [
        window.currentStart,
        window.currentEnd,
        window.previousStart,
        window.previousEnd,
      ]) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
        expect(d.millisecond, 0);
      }
    });

    test('month window boundaries have zeroed time-of-day components', () {
      final now = DateTime(2026, 7, 15, 23, 45, 30, 500);
      final window = ChartPeriod.month.windowFor(now);

      for (final d in [
        window.currentStart,
        window.currentEnd,
        window.previousStart,
        window.previousEnd,
      ]) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
        expect(d.millisecond, 0);
      }
    });
  });

  group('ChartPeriod.last30d is the default', () {
    test('ChartPeriod.defaultPeriod is last30d', () {
      expect(ChartPeriod.defaultPeriod, ChartPeriod.last30d);
    });
  });
}
