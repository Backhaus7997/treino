import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_stats_row.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('PublicProfileStatsRow', () {
    testWidgets('SCENARIO-216: renders 4 stat labels', (tester) async {
      await tester.pumpWidget(_wrap(const PublicProfileStatsRow()));
      await tester.pump();

      expect(find.text('WORKOUTS'), findsOneWidget);
      expect(find.text('RACHA'), findsOneWidget);
      expect(find.text('SEGUIDORES'), findsOneWidget);
      expect(find.text('SIGUIENDO'), findsOneWidget);
    });

    testWidgets('SCENARIO-217: all four stats hardcoded to "0"',
        (tester) async {
      await tester.pumpWidget(_wrap(const PublicProfileStatsRow()));
      await tester.pump();

      // 4 occurrences of '0' — one per stat tile
      expect(find.text('0'), findsNWidgets(4));
    });

    testWidgets('SCENARIO-218: stats row renders without overflow on narrow widths',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(
          width: 320,
          child: PublicProfileStatsRow(),
        ),
      ));
      await tester.pump();

      // No exception thrown during pump = no overflow
      expect(tester.takeException(), isNull);
    });
  });
}
