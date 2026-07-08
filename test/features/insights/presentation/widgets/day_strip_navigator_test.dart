import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
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

DateTime _todayOnly() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

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
      final today = _todayOnly();
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
      final today = _todayOnly();
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
      final today = _todayOnly();
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
      final today = _todayOnly();
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

    testWidgets(
        'selected day outline uses palette.highlight, distinct from the '
        'trained/today marker color (palette.accent) — proves selection '
        'feedback is visually separate from the trained state', (tester) async {
      final today = _todayOnly();
      // Select a day that is NEITHER today NOR trained, so any border color
      // we see is caused ONLY by the isSelected flag.
      final days = _sevenDays(today: today, trainedIndex: 3);
      final selected = days[1].day; // untrained, not today

      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: days,
          selectedDay: selected,
          onDaySelected: (_) {},
          labels: _labels,
        ),
      ));

      // The OUTER-most Container is the selection ring — it wraps the
      // trained/today marker Container, so both stay visible at once.
      final selectedTile = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey(selected)),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = selectedTile.decoration as BoxDecoration;
      final border = decoration.border as Border;

      expect(border.top.color, AppPalette.mintMagenta.highlight);
      expect(border.top.color, isNot(AppPalette.mintMagenta.accent));
    });

    testWidgets(
        'selected day AND today are the SAME day → both markers render '
        'simultaneously (today\'s mint outline nested inside the magenta '
        'selection ring, not replaced by it)', (tester) async {
      final today = _todayOnly();
      final days = _sevenDays(today: today); // last tile == today
      final todayDay = days.last.day;

      await tester.pumpWidget(_wrap(
        DayStripNavigator(
          days: days,
          selectedDay: todayDay,
          onDaySelected: (_) {},
          labels: _labels,
        ),
      ));

      final containers = tester
          .widgetList<Container>(find.descendant(
            of: find.byKey(ValueKey(todayDay)),
            matching: find.byType(Container),
          ))
          .toList();

      // Outer ring (selection, magenta) + inner circle (today, mint) — two
      // distinct Containers, two distinct border colors.
      expect(containers.length, 2);
      final outerBorder =
          (containers[0].decoration as BoxDecoration).border as Border;
      final innerBorder =
          (containers[1].decoration as BoxDecoration).border as Border;

      expect(outerBorder.top.color, AppPalette.mintMagenta.highlight);
      expect(innerBorder.top.color, AppPalette.mintMagenta.accent);
    });
  });
}
