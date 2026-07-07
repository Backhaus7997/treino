import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/insights/domain/workout_days_month.dart';
import 'package:treino/features/insights/presentation/widgets/workout_days_calendar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      );

  const labels = WorkoutDaysCalendarLabels(
    streakLabelBuilder: _streakLabel,
    weekdayLetters: ['L', 'M', 'M', 'J', 'V', 'S', 'D'],
  );

  group('WorkoutDaysCalendar (SCENARIO-WDC-W01..04)', () {
    // June 2026: 1st is a Monday, 30 days — no leading/trailing blanks
    // needed to test the "clean" case; July 2026 (below) covers mid-week.
    testWidgets('SCENARIO-WDC-W01: marks exactly the trained days of the month',
        (tester) async {
      final data = WorkoutDaysMonth(
        month: DateTime(2026, 6),
        trainedDays: {
          DateTime(2026, 6, 1),
          DateTime(2026, 6, 30),
        },
        streak: 3,
      );

      await tester.pumpWidget(wrap(
        WorkoutDaysCalendar(data: data, labels: labels),
      ));

      // Day-number cells for every day 1..30 must be present.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('30'), findsOneWidget);

      final trainedFinder = find.byKey(const ValueKey('workout-day-trained'));
      expect(trainedFinder, findsNWidgets(2));
    });

    // July 2026: 1st is a Wednesday → 2 leading blank cells before day 1
    // in a Mon-Sun grid, exercising week-row math for a mid-week start.
    testWidgets(
        'SCENARIO-WDC-W02: renders leading blank cells for a month '
        'starting mid-week (Mon-Sun columns)', (tester) async {
      final data = WorkoutDaysMonth(
        month: DateTime(2026, 7),
        trainedDays: {DateTime(2026, 7, 1)},
        streak: 0,
      );

      await tester.pumpWidget(wrap(
        WorkoutDaysCalendar(data: data, labels: labels),
      ));

      final calendar = tester.widget<WorkoutDaysCalendar>(
        find.byType(WorkoutDaysCalendar),
      );
      // July 2026 starts on a Wednesday (DateTime.wednesday == 3), so the
      // Mon-Sun grid needs 2 leading blanks before day 1.
      expect(DateTime(2026, 7, 1).weekday, DateTime.wednesday);
      expect(calendar.data.month.month, 7);

      expect(find.byKey(const ValueKey('workout-day-blank-leading-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('workout-day-blank-leading-1')),
          findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('SCENARIO-WDC-W03: renders nonzero streak text',
        (tester) async {
      final data = WorkoutDaysMonth(
        month: DateTime(2026, 6),
        trainedDays: const {},
        streak: 5,
      );

      await tester.pumpWidget(wrap(
        WorkoutDaysCalendar(data: data, labels: labels),
      ));

      expect(find.text(_streakLabel(5)), findsOneWidget);
      expect(find.byIcon(TreinoIcon.streak), findsOneWidget);
    });

    testWidgets('SCENARIO-WDC-W04: zero streak is shown, not hidden',
        (tester) async {
      final data = WorkoutDaysMonth(
        month: DateTime(2026, 6),
        trainedDays: const {},
        streak: 0,
      );

      await tester.pumpWidget(wrap(
        WorkoutDaysCalendar(data: data, labels: labels),
      ));

      expect(find.text(_streakLabel(0)), findsOneWidget);
    });
  });
}

String _streakLabel(int streak) => 'Racha de $streak días';
