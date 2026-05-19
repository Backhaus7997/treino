import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/user_search_result_tile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserPublicProfile _fakeProfile({
  String uid = 'u1',
  String? displayName = 'Ana',
  String? gymId,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName?.toLowerCase(),
      gymId: gymId,
    );

/// Wraps the tile inside a GoRouter so context.push works.
Widget _wrapWithRouter(Widget tile) {
  final routes = <GoRoute>[
    GoRoute(
      path: '/',
      builder: (_, __) => Scaffold(body: tile),
    ),
    GoRoute(
      path: '/feed/profile/:uid',
      builder: (_, state) =>
          Scaffold(body: Text('Profile ${state.pathParameters['uid']}')),
    ),
  ];

  final router = GoRouter(initialLocation: '/', routes: routes);

  return MaterialApp.router(
    theme: AppTheme.dark(),
    routerConfig: router,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // SCENARIO-281: Tile renders avatar, displayName, and gym name
  // ---------------------------------------------------------------------------
  group('UserSearchResultTile — rendering', () {
    testWidgets(
        'SCENARIO-281: renders PostAvatar, displayName, and gym name when '
        'gymId is "smart-fit-palermo"',
        (tester) async {
      final tile = UserSearchResultTile(
        profile: _fakeProfile(uid: 'u1', displayName: 'Ana', gymId: 'smart-fit-palermo'),
        onTap: () {},
      );

      await tester.pumpWidget(_wrapWithRouter(tile));
      await tester.pump();

      // displayName visible (rendered uppercase by design)
      expect(find.textContaining('ANA'), findsOneWidget);
      // gym name resolved from gymId
      expect(find.textContaining('SMART FIT'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // SCENARIO-282: null displayName → no crash
    // -------------------------------------------------------------------------
    testWidgets(
        'SCENARIO-282: tile renders without throwing when displayName is null',
        (tester) async {
      final tile = UserSearchResultTile(
        profile: _fakeProfile(uid: 'u1', displayName: null),
        onTap: () {},
      );

      await tester.pumpWidget(_wrapWithRouter(tile));
      await tester.pump();

      // Should not throw. Fallback text visible.
      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // SCENARIO-285: null gymId → blank, no crash
    // -------------------------------------------------------------------------
    testWidgets(
        'SCENARIO-285: tile renders without exception when gymId is null; '
        'gym name area is blank',
        (tester) async {
      final tile = UserSearchResultTile(
        profile: _fakeProfile(uid: 'u1', displayName: 'Ana', gymId: null),
        onTap: () {},
      );

      await tester.pumpWidget(_wrapWithRouter(tile));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-283: tap → context.push('/feed/profile/u1')
  // ---------------------------------------------------------------------------
  group('UserSearchResultTile — navigation', () {
    testWidgets(
        'SCENARIO-283: tapping the tile calls onTap callback which navigates '
        'to /feed/profile/u1',
        (tester) async {
      var tapped = false;

      final tile = UserSearchResultTile(
        profile: _fakeProfile(uid: 'u1'),
        onTap: () => tapped = true,
      );

      await tester.pumpWidget(_wrapWithRouter(tile));
      await tester.pump();

      await tester.tap(find.byType(UserSearchResultTile));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-284: no follow button
  // ---------------------------------------------------------------------------
  group('UserSearchResultTile — no follow button', () {
    testWidgets(
        'SCENARIO-284: widget tree contains no follow button or ElevatedButton',
        (tester) async {
      final tile = UserSearchResultTile(
        profile: _fakeProfile(uid: 'u1'),
        onTap: () {},
      );

      await tester.pumpWidget(_wrapWithRouter(tile));
      await tester.pump();

      // No ElevatedButton or TextButton follow affordance
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('Seguir'), findsNothing);
      expect(find.textContaining('Follow'), findsNothing);
    });
  });
}
