import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/insights/domain/day_insights.dart';
import 'package:treino/features/insights/presentation/widgets/day_strip_labels.dart';
import 'package:treino/features/insights/presentation/widgets/day_strip_navigator.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

const _labels = DayStripLabels(
  todayLabel: 'HOY',
  emptyDayHint: 'Sin sesión este día.',
);

List<DayInsights> _sevenDays({required DateTime today, int trainedIndex = -1}) {
  return List.generate(7, (i) {
    final day = DateTime(today.year, today.month, today.day - (6 - i));
    return DayInsights(
      day: day,
      setsByGroup: const {},
      sessionsCount: i == trainedIndex ? 1 : 0,
    );
  });
}

void main() {
  group('DayStripNavigator', () {
    testWidgets('renders 7 day tiles', (tester) async {
      final today = DateTime(2026, 7, 7);
      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: _sevenDays(today: today),
          selectedDay: today,
          onDaySelected: (_) {},
          labels: _labels,
        ),
      ));

      expect(find.byType(GestureDetector), findsWidgets);
      expect(find.text('HOY'), findsOneWidget);
    });

    testWidgets('tapping a day tile invokes onDaySelected with that day',
        (tester) async {
      final today = DateTime(2026, 7, 7);
      DateTime? tapped;
      final days = _sevenDays(today: today, trainedIndex: 3);
      final tappedDay = days[3].day;

      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: days,
          selectedDay: today,
          onDaySelected: (d) => tapped = d,
          labels: _labels,
        ),
      ));

      await tester.tap(find.byKey(ValueKey(tappedDay)));
      await tester.pump();

      expect(tapped, tappedDay);
    });

    testWidgets(
        'exactly ONE trained day tile renders the check-fill icon — '
        'proves per-day state, not week-wide painting', (tester) async {
      final today = DateTime(2026, 7, 7);
      final days = _sevenDays(today: today, trainedIndex: 3);

      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: days,
          selectedDay: today,
          onDaySelected: (_) {},
          labels: _labels,
        ),
      ));

      // Exactly 1 of the 7 tiles is trained (index 3) → exactly 1 check
      // icon in the whole strip, not 0 (untested) and not 7 (week-painted).
      expect(find.byIcon(TreinoIcon.checkCircleFill), findsOneWidget);
    });

    testWidgets('no trained days → zero check icons rendered', (tester) async {
      final today = DateTime(2026, 7, 7);
      final days = _sevenDays(today: today); // trainedIndex: -1 → none

      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: days,
          selectedDay: today,
          onDaySelected: (_) {},
          labels: _labels,
        ),
      ));

      expect(find.byIcon(TreinoIcon.checkCircleFill), findsNothing);
    });
  });
}
