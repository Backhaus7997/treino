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

    testWidgets('SCENARIO-217: null params render as "0" for all stats',
        (tester) async {
      await tester.pumpWidget(_wrap(const PublicProfileStatsRow()));
      await tester.pump();

      // 4 occurrences of '0' — one per stat tile (null → '0')
      expect(find.text('0'), findsNWidgets(4));
    });

    testWidgets(
        'SCENARIO-218: stats row renders without overflow on narrow widths',
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

    // SCENARIO-324: real values render correctly in correct columns
    testWidgets(
        'SCENARIO-324: real values (89/23/412/284) display in correct columns',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const PublicProfileStatsRow(
          workoutsCount: 89,
          racha: 23,
          followersCount: 412,
          followingCount: 284,
        ),
      ));
      await tester.pump();

      // WORKOUTS: 89 < 1000 → '89'
      expect(find.text('89'), findsOneWidget);
      // RACHA: raw int → '23'
      expect(find.text('23'), findsOneWidget);
      // SEGUIDORES: 412 < 1000 → '412'
      expect(find.text('412'), findsOneWidget);
      // SIGUIENDO: 284 < 1000 → '284'
      expect(find.text('284'), findsOneWidget);
    });

    // SCENARIO-324b: kFormat applied to WORKOUTS
    testWidgets('SCENARIO-324b: kFormat applied to workoutsCount ≥ 1000',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const PublicProfileStatsRow(
          workoutsCount: 1500,
          racha: 7,
          followersCount: 92000,
          followingCount: 1000,
        ),
      ));
      await tester.pump();

      // 1500 → '2k'
      expect(find.text('2k'), findsAtLeastNWidgets(1));
      // 92000 → '92k'
      expect(find.text('92k'), findsOneWidget);
      // 1000 → '1k'
      expect(find.text('1k'), findsAtLeastNWidgets(1));
      // RACHA: raw → '7'
      expect(find.text('7'), findsOneWidget);
    });

    // SCENARIO-325: null values render as '0'
    testWidgets(
        'SCENARIO-325: null workoutsCount/followersCount/followingCount → "0"',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const PublicProfileStatsRow(
          workoutsCount: null,
          racha: null,
          followersCount: null,
          followingCount: null,
        ),
      ));
      await tester.pump();

      expect(find.text('0'), findsNWidgets(4));
    });
  });
}
