import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/search_users_provider.dart';
import 'package:treino/features/feed/presentation/search_users_screen.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/user_search_result_tile.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUserPublicProfileRepository extends Mock
    implements UserPublicProfileRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserPublicProfile _fakeProfile({
  String uid = 'u1',
  String? displayName = 'Martin',
  String? gymId,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName?.toLowerCase(),
      gymId: gymId,
    );

/// Wraps [SearchUsersScreen] in GoRouter so context.push works.
/// The shell Scaffold provides the Material ancestor for TextField.
Widget _wrapWithRouter({
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, __) => const Scaffold(body: SearchUsersScreen()),
      ),
      GoRoute(
        path: '/feed/profile/:uid',
        builder: (_, state) =>
            Scaffold(body: Text('Profile ${state.pathParameters['uid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

void main() {
  late MockUserPublicProfileRepository mockRepo;

  setUp(() {
    mockRepo = MockUserPublicProfileRepository();
    // Default: return empty list
    when(() => mockRepo.searchByDisplayName(any()))
        .thenAnswer((_) async => []);
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-286: Initial state shows empty prompt
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — initial state', () {
    testWidgets(
        'SCENARIO-286: shows FeedEmptyState with "Buscá usuarios por nombre" '
        'on initial render',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      expect(
        find.textContaining('Buscá usuarios por nombre'),
        findsOneWidget,
      );
      expect(find.byType(FeedEmptyState), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-295: header title "BUSCAR USUARIOS" is visible on render',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      expect(find.text('BUSCAR USUARIOS'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-287: 1-char still shows empty prompt
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — below minimum chars', () {
    testWidgets(
        'SCENARIO-287: typing 1 character still shows "Buscá usuarios" '
        'empty-state prompt (2-char minimum not met)',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();

      expect(
        find.textContaining('Buscá usuarios por nombre'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-288: Loading state shows spinner
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — loading state', () {
    testWidgets(
        'SCENARIO-288: shows CircularProgressIndicator while provider is loading',
        (tester) async {
      // Use a completer to keep the provider in loading state
      final completer = Completer<List<UserPublicProfile>>();
      when(() => mockRepo.searchByDisplayName(any()))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      // Type 3+ chars and advance past debounce
      await tester.enterText(find.byType(TextField), 'mar');
      await tester.pump(const Duration(milliseconds: 400));

      // Provider is still loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete to avoid pending timer warnings
      completer.complete([]);
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-289: Data state shows ListView with tiles
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — data state', () {
    testWidgets(
        'SCENARIO-289: provider returns 3 profiles → ListView with 3 '
        'UserSearchResultTile items',
        (tester) async {
      final profiles = [
        _fakeProfile(uid: 'u1', displayName: 'Martin'),
        _fakeProfile(uid: 'u2', displayName: 'Maria'),
        _fakeProfile(uid: 'u3', displayName: 'Marcos'),
      ];
      when(() => mockRepo.searchByDisplayName(any()))
          .thenAnswer((_) async => profiles);

      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byType(UserSearchResultTile), findsNWidgets(3));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-290: Empty results shows no-results message with query
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — empty results state', () {
    testWidgets(
        'SCENARIO-290: provider returns empty list → FeedEmptyState with '
        'message containing the active query',
        (tester) async {
      when(() => mockRepo.searchByDisplayName(any()))
          .thenAnswer((_) async => []);

      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin resultados'), findsOneWidget);
      expect(find.textContaining('xyz'), findsAtLeastNWidgets(1));
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-291: Error state shows error text
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — error state', () {
    testWidgets(
        'SCENARIO-291: provider errors → shows error text '
        '"No pudimos buscar usuarios. Intentá de nuevo."',
        (tester) async {
      when(() => mockRepo.searchByDisplayName(any()))
          .thenThrow(Exception('network error'));

      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'er');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No pudimos buscar usuarios'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-292: Clear button appears when field is non-empty
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — clear button', () {
    testWidgets(
        'SCENARIO-292: clear button appears when text field contains text',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      // Initially no clear button
      expect(find.byIcon(Icons.close), findsNothing);

      await tester.enterText(find.byType(TextField), 'mart');
      await tester.pump();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // SCENARIO-293: Clear button resets field and shows empty prompt
    // -------------------------------------------------------------------------
    testWidgets(
        'SCENARIO-293: tapping clear resets the field and shows empty-state '
        '"Buscá usuarios por nombre"',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(
        overrides: [
          userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
        ],
      ));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'martin');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', equals(''));
      expect(
        find.textContaining('Buscá usuarios por nombre'),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // SCENARIO-294: Back arrow pops navigator
  // ---------------------------------------------------------------------------
  group('SearchUsersScreen — navigation', () {
    testWidgets(
        'SCENARIO-294: tapping back arrow calls context.pop() — navigator has '
        'only one entry so pop goes to initial empty state',
        (tester) async {
      // Set up router with a parent route so we can push to /search
      final router = GoRouter(
        initialLocation: '/feed',
        routes: [
          GoRoute(
            path: '/feed',
            builder: (_, __) => const Scaffold(body: Text('Feed')),
          ),
          GoRoute(
            path: '/search',
            builder: (_, __) => const Scaffold(body: SearchUsersScreen()),
          ),
          GoRoute(
            path: '/feed/profile/:uid',
            builder: (_, state) => Scaffold(
                body: Text('Profile ${state.pathParameters['uid']}')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userPublicProfileRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      // Navigate to /search
      router.push('/search');
      await tester.pumpAndSettle();

      // Back arrow visible
      expect(find.text('BUSCAR USUARIOS'), findsOneWidget);

      // Tap back arrow (find the GestureDetector wrapping an arrow icon)
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Should be back at /feed
      expect(find.text('Feed'), findsOneWidget);
    });
  });
}
