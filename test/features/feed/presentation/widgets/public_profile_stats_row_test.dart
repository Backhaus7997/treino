import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_stats_row.dart';
import 'package:treino/features/workout/presentation/widgets/session_stats_card.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('PublicProfileStatsRow', () {
    // ── acceso estilo Instagram a las listas ────────────────────────────────
    //
    // Los contadores son la puerta de entrada a SEGUIDORES y SEGUIDOS. Los
    // callbacks son opcionales: los otros seis usos de StatTile en la app no
    // los pasan y tienen que seguir renderizando igual, sin zona tappable.

    testWidgets('tocar SEGUIDORES dispara su callback, no el otro',
        (tester) async {
      var seguidores = 0;
      var siguiendo = 0;
      await tester.pumpWidget(_wrap(
        PublicProfileStatsRow(
          followersCount: 3,
          followingCount: 5,
          onFollowersTap: () => seguidores++,
          onFollowingTap: () => siguiendo++,
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('SEGUIDORES'));
      await tester.pump();

      expect(seguidores, 1);
      expect(siguiendo, 0);
    });

    testWidgets('tocar SIGUIENDO dispara su callback, no el otro',
        (tester) async {
      var seguidores = 0;
      var siguiendo = 0;
      await tester.pumpWidget(_wrap(
        PublicProfileStatsRow(
          followersCount: 3,
          followingCount: 5,
          onFollowersTap: () => seguidores++,
          onFollowingTap: () => siguiendo++,
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('SIGUIENDO'));
      await tester.pump();

      expect(siguiendo, 1);
      expect(seguidores, 0);
    });

    testWidgets('WORKOUTS y RACHA no son tappables aunque las otras lo sean',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PublicProfileStatsRow(
          onFollowersTap: () {},
          onFollowingTap: () {},
        ),
      ));
      await tester.pump();

      // Sólo los dos contadores sociales quedan envueltos.
      expect(find.byType(TreinoTappable), findsNWidgets(2));
    });

    testWidgets('sin callbacks no hay nada tappable', (tester) async {
      await tester.pumpWidget(_wrap(const PublicProfileStatsRow()));
      await tester.pump();

      expect(find.byType(TreinoTappable), findsNothing);
    });

    testWidgets('los contadores tappables anuncian que son botones',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        PublicProfileStatsRow(
          onFollowersTap: () {},
          onFollowingTap: () {},
          followersSemanticsLabel: 'Ver seguidores',
          followingSemanticsLabel: 'Ver seguidos',
        ),
      ));
      await tester.pump();

      // El nombre accesible del nodo mezcla la etiqueta con el contenido del
      // tile ("SEGUIDORES", "0"), así que se busca por subcadena.
      expect(find.bySemanticsLabel(RegExp('Ver seguidores')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Ver seguidos')), findsOneWidget);

      final nodo = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Ver seguidores')),
      );
      expect(nodo.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    testWidgets('SCENARIO-216: renders 4 stat labels', (tester) async {
      await tester.pumpWidget(_wrap(const PublicProfileStatsRow()));
      await tester.pump();

      expect(find.byType(SessionStatsCard), findsOneWidget);
      expect(find.byType(StatTile), findsNWidgets(4));
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

    testWidgets('RACHA preserves the accent-color highlight', (tester) async {
      await tester.pumpWidget(_wrap(
        const PublicProfileStatsRow(racha: 23),
      ));
      await tester.pump();

      final context = tester.element(find.byType(PublicProfileStatsRow));
      final rachaValue = tester.widget<Text>(find.text('23'));

      expect(rachaValue.style?.color, AppPalette.of(context).accent);
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
