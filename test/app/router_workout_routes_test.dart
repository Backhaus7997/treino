import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
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
            routineByIdProvider('test-id')
                .overrideWith((ref) async => _kRoutine),
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

  // ─── /workout?tab= deep-link (rankings-v2 Phase 2, task 2.5) ───────────────
  //
  // Design AD-2: the `/workout` route builder reads `?tab=` and forwards it
  // as `WorkoutScreen.initialTab`, mirroring the `/coach` builder
  // (router.dart:467-472) exactly.
  group('/workout?tab= deep-link', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
            GoRoute(
              path: '/workout',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return NoTransitionPage(
                  child: WorkoutScreen(initialTab: tab),
                );
              },
            ),
          ],
        );

    testWidgets(
        '/workout?tab=rankings builds WorkoutScreen with initialTab: '
        "'rankings'", (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout?tab=rankings');
      await tester.pump();

      final screen = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
      expect(screen.initialTab, equals('rankings'));
    });

    testWidgets(
        '/workout (no query param) builds WorkoutScreen with initialTab: '
        'null', (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout');
      await tester.pump();

      final screen = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
      expect(screen.initialTab, isNull);
    });
  });

  // ─── /profile/rankings redirect (rankings-v2 Phase 3, task 3.3) ───────────
  //
  // Design AD-3: `/profile/rankings` is retired as a pushed route but stays
  // REGISTERED as a redirect to `/workout?tab=rankings` — a safety net for
  // any lingering `context.push('/profile/rankings')` call or bookmark, per
  // spec `gym-rankings` — REMOVED Requirement: Rankings Reachable via
  // Profile Tile and /profile/rankings (route disposition: redirect, not
  // hard-remove).
  group('/profile/rankings redirect', () {
    GoRouter buildRouter() => GoRouter(
          initialLocation: '/start',
          routes: [
            GoRoute(path: '/start', builder: (_, __) => const Text('START')),
            GoRoute(
              path: '/workout',
              pageBuilder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return NoTransitionPage(
                  child: WorkoutScreen(initialTab: tab),
                );
              },
            ),
            GoRoute(
              path: '/profile',
              builder: (_, __) => const Text('PROFILE'),
              routes: [
                GoRoute(
                  path: 'rankings',
                  redirect: (_, __) => '/workout?tab=rankings',
                ),
              ],
            ),
          ],
        );

    testWidgets(
        '/profile/rankings redirects to /workout?tab=rankings and builds '
        'WorkoutScreen with initialTab: \'rankings\'', (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(
        ProviderScope(
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

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        equals('/workout?tab=rankings'),
      );
      final screen = tester.widget<WorkoutScreen>(find.byType(WorkoutScreen));
      expect(screen.initialTab, equals('rankings'));
    });
  });
}
