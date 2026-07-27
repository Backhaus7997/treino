import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/post_workout_summary_screen.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/session_detail_screen.dart';
import 'package:treino/features/workout/workout_screen.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/l10n/app_l10n.dart';

// Minimal shell that mirrors _ShellScaffold from router.dart: provides a
// Scaffold with TreinoBottomBar so SCENARIO-110/111 can assert the bar exists.
class _TestShell extends StatelessWidget {
  const _TestShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: child,
        bottomNavigationBar: TreinoBottomBar(
          currentIndex: 0,
          onTap: (_) {},
        ),
      );
}

GoRouter _buildTestRouter({
  required List<Override> overrides,
  required Widget Function(BuildContext, GoRouterState) routineBuilder,
  required Widget Function(BuildContext, GoRouterState) exerciseBuilder,
}) =>
    GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(path: '/start', builder: (_, __) => const Text('START')),
        ShellRoute(
          builder: (context, state, child) => _TestShell(child: child),
          routes: [
            GoRoute(
              path: '/workout',
              builder: (_, __) => const Text('WORKOUT'),
              routes: [
                GoRoute(
                  path: 'routine/:routineId',
                  builder: routineBuilder,
                ),
                GoRoute(
                  path: 'exercise/:exerciseId',
                  builder: exerciseBuilder,
                ),
              ],
            ),
          ],
        ),
      ],
    );

const Routine _kRoutine = Routine(
  id: 'test-id',
  name: 'PPL Beginner',
  split: 'PPL',
  level: ExperienceLevel.beginner,
  days: [
    RoutineDay(
      dayNumber: 1,
      name: 'Push',
      slots: [
        RoutineSlot(
          exerciseId: 'bench-press',
          exerciseName: 'Bench Press',
          muscleGroup: 'chest',
          targetSets: 4,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 90,
        ),
      ],
    ),
  ],
);

const Exercise _kExercise = Exercise(
  id: 'bench-press',
  name: 'Bench Press',
  muscleGroup: 'chest',
  category: 'compound',
);

void main() {
  group('Router workout routes', () {
    testWidgets(
        'SCENARIO-110: /workout/routine/:id resolves to RoutineDetailScreen with TreinoBottomBar',
        (tester) async {
      final router = _buildTestRouter(
        overrides: [],
        routineBuilder: (ctx, state) => RoutineDetailScreen(
          routineId: state.pathParameters['routineId']!,
        ),
        exerciseBuilder: (ctx, state) => ExerciseDetailScreen(
          exerciseId: state.pathParameters['exerciseId']!,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routineByIdStreamProvider('test-id')
                .overrideWith((ref) => Stream.value(_kRoutine)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout/routine/test-id');
      await tester.pumpAndSettle();

      expect(find.byType(RoutineDetailScreen), findsOneWidget);
      expect(find.byType(TreinoBottomBar), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-111: /workout/exercise/:id resolves to ExerciseDetailScreen with TreinoBottomBar',
        (tester) async {
      final router = _buildTestRouter(
        overrides: [],
        routineBuilder: (ctx, state) => RoutineDetailScreen(
          routineId: state.pathParameters['routineId']!,
        ),
        exerciseBuilder: (ctx, state) => ExerciseDetailScreen(
          exerciseId: state.pathParameters['exerciseId']!,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exerciseByIdProvider('bench-press')
                .overrideWith((ref) async => _kExercise),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout/exercise/bench-press');
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.byType(TreinoBottomBar), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-354: /workout/session-summary/:sessionId resolves to PostWorkoutSummaryScreen WITHOUT TreinoBottomBar (immersive)',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(path: '/start', builder: (_, __) => const Text('START')),
          GoRoute(
            path: '/workout/session-summary/:sessionId',
            builder: (context, state) => PostWorkoutSummaryScreen(
              sessionId: state.pathParameters['sessionId']!,
            ),
          ),
          ShellRoute(
            builder: (context, state, child) => _TestShell(child: child),
            routes: [
              GoRoute(
                path: '/workout',
                builder: (_, __) => const Text('WORKOUT'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('u1'),
            sessionSummaryProvider.overrideWith(
              (ref, key) async => (session: null, setLogs: <SetLog>[]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout/session-summary/s1');
      await tester.pumpAndSettle();

      expect(find.byType(PostWorkoutSummaryScreen), findsOneWidget);
      expect(find.byType(TreinoBottomBar), findsNothing);
    });

    // SCENARIO-378 (PR-B): /workout/historial/:sessionId resolves to
    // SessionDetailScreen WITHOUT TreinoBottomBar (immersive, top-level route
    // outside ShellRoute). PR-B replaces the PR-A stub with SessionDetailScreen.
    testWidgets(
        'SCENARIO-378: /workout/historial/:sessionId resolves to SessionDetailScreen WITHOUT TreinoBottomBar',
        (tester) async {
      // Router mirrors production structure: top-level GoRoute (no shell) for
      // /workout/historial/:sessionId plus a ShellRoute for /workout.
      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(path: '/start', builder: (_, __) => const Text('START')),
          // Top-level immersive route — outside ShellRoute (no bottom bar).
          GoRoute(
            path: '/workout/historial/:sessionId',
            pageBuilder: (context, state) => CustomTransitionPage(
              child: SessionDetailScreen(
                sessionId: state.pathParameters['sessionId']!,
              ),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              transitionsBuilder: (_, __, ___, child) => child,
            ),
          ),
          ShellRoute(
            builder: (context, state, child) => _TestShell(child: child),
            routes: [
              GoRoute(
                path: '/workout',
                builder: (_, __) => const Text('WORKOUT'),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('u1'),
            sessionSummaryProvider.overrideWith(
              (ref, key) async => (session: null, setLogs: <SetLog>[]),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout/historial/abc123');
      await tester.pumpAndSettle();

      expect(find.byType(SessionDetailScreen), findsOneWidget);
      expect(find.byType(TreinoBottomBar), findsNothing);
    });
  });

  // ─── /workout?tab=rankings legacy redirect ────────────────────────────────
  //
  // Rankings relocated from the Entrenar tab to the FEED tab: the production
  // `/workout` route keeps a redirect so legacy `?tab=rankings` deep-links
  // (old bookmarks / notifications) land on `/feed?tab=rankings`, whose
  // builder forwards the query param as `FeedScreen.initialTab`. The mini
  // routers below mirror the production wiring in router.dart.
  group('/workout?tab= deep-link', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
            GoRoute(
              path: '/workout',
              redirect: (_, state) =>
                  state.uri.queryParameters['tab'] == 'rankings'
                      ? '/feed?tab=rankings'
                      : null,
              pageBuilder: (_, __) =>
                  const NoTransitionPage(child: WorkoutScreen()),
            ),
            GoRoute(
              path: '/feed',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return NoTransitionPage(child: FeedScreen(initialTab: tab));
              },
            ),
          ],
        );

    Widget wrapRouter(GoRouter router) => ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(null),
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(null)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        );

    testWidgets(
        '/workout?tab=rankings redirects to /feed?tab=rankings and builds '
        "FeedScreen with initialTab: 'rankings'", (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(wrapRouter(router));

      router.go('/workout?tab=rankings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/feed?tab=rankings'),
      );
      final screen = tester.widget<FeedScreen>(find.byType(FeedScreen));
      expect(screen.initialTab, equals('rankings'));
    });

    testWidgets('/workout (no query param) stays on /workout', (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(wrapRouter(router));

      router.go('/workout');
      await tester.pump();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/workout'),
      );
      expect(find.byType(WorkoutScreen), findsOneWidget);
    });
  });

  // ─── /profile/rankings redirect ───────────────────────────────────────────
  //
  // `/profile/rankings` stays REGISTERED as a redirect (safety net for any
  // lingering `context.push('/profile/rankings')` call or bookmark) — now
  // pointing at `/feed?tab=rankings`, the rankings' current home.
  group('/profile/rankings redirect', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
            GoRoute(
              path: '/feed',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return NoTransitionPage(child: FeedScreen(initialTab: tab));
              },
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const Text('PROFILE'),
              routes: [
                GoRoute(
                  path: 'rankings',
                  redirect: (_, __) => '/feed?tab=rankings',
                ),
              ],
            ),
          ],
        );

    testWidgets(
        '/profile/rankings redirects to /feed?tab=rankings and builds '
        "FeedScreen with initialTab: 'rankings'", (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(null),
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(null)),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/profile/rankings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/feed?tab=rankings'),
      );
      final screen = tester.widget<FeedScreen>(find.byType(FeedScreen));
      expect(screen.initialTab, equals('rankings'));
    });
  });
}
