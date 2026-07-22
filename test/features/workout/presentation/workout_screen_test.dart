import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/gym_rankings/application/ranking_providers.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/ranking_optin_controller_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/historial_section.dart';
import 'package:treino/features/workout/presentation/widgets/mi_plan_section.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_section.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';
import 'package:treino/features/workout/workout_screen.dart';

class _MockUser extends Mock implements User {}

User fakeUser(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

Routine makeRoutine({
  String id = 'test-id',
  String name = 'Routine',
  ExperienceLevel level = ExperienceLevel.beginner,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: level,
      days: const [],
    );

UserProfile makeProfile() => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrapWorkout(Widget w, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('test-uid'),
        sessionsByUidProvider.overrideWith((ref, uid) async => []),
        // MiPlanSection: return null user → section renders SizedBox.shrink.
        // Tests that only care about PLANTILLAS / HISTORIAL order don't need
        // the full MiPlanSection provider stack.
        authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SizedBox(
            height: 800,
            child: w,
          ),
        ),
      ),
    );

void main() {
  // ─── Router tests (T-7.1) ──────────────────────────────────────────────────

  group('Router — /workout/routine/:id', () {
    testWidgets(
        'navigating to /workout/routine/test-id renders RoutineDetailScreen',
        (tester) async {
      final routine = makeRoutine(id: 'test-id');

      final container = ProviderContainer(
        overrides: [
          routineByIdStreamProvider('test-id')
              .overrideWith((_) => Stream.value(routine)),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/workout/routine/test-id',
        routes: [
          GoRoute(
            path: '/workout/routine/:id',
            builder: (context, state) => RoutineDetailScreen(
              routineId: state.pathParameters['id']!,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            locale: const Locale('es', 'AR'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(RoutineDetailScreen), findsOneWidget);
    });

    testWidgets(
        'route is inside ShellRoute — TreinoBottomBar persists on /workout/routine/:id',
        (tester) async {
      final routine = makeRoutine(id: 'test-id');

      // Build a minimal shell that mirrors the production ShellRoute structure.
      // The bottom bar is always shown by _ShellScaffold for any /workout/* path.
      final router = GoRouter(
        initialLocation: '/workout/routine/test-id',
        routes: [
          ShellRoute(
            builder: (context, state, child) => Scaffold(
              body: child,
              bottomNavigationBar: TreinoBottomBar(
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
            routes: [
              GoRoute(
                path: '/workout',
                builder: (_, __) => const Scaffold(body: Text('workout')),
              ),
              GoRoute(
                path: '/workout/routine/:id',
                builder: (context, state) => RoutineDetailScreen(
                  routineId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          routineByIdStreamProvider('test-id')
              .overrideWith((_) => Stream.value(routine)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            locale: const Locale('es', 'AR'),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TreinoBottomBar), findsOneWidget);
    });
  });

  // ─── WorkoutScreen tests (T-8.1) ──────────────────────────────────────────

  group('WorkoutScreen', () {
    testWidgets(
        'three sections rendered in order: MI PLAN → PLANTILLAS → HISTORIAL',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
            // Provide a user so MiPlanSection is visible (shows empty state).
            authStateChangesProvider.overrideWith(
              (ref) => Stream.value(null),
            ),
            assignedRoutinesProvider('').overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // MiPlanSection renders SizedBox.shrink when uid is null (null User).
      // Test presence of MiPlanSection widget and remaining sections.
      expect(find.byType(MiPlanSection), findsOneWidget);
      expect(find.text('PLANTILLAS'), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);

      final miPlanPos = tester.getTopLeft(find.byType(MiPlanSection)).dy;
      final plantillasPos = tester.getTopLeft(find.text('PLANTILLAS')).dy;
      final historialPos = tester.getTopLeft(find.text('HISTORIAL')).dy;

      expect(miPlanPos, lessThanOrEqualTo(plantillasPos));
      expect(plantillasPos, lessThan(historialPos));
    });

    testWidgets('MiPlanSection empty state appears when plans list is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
            currentUidProvider.overrideWithValue('athlete-1'),
            assignedRoutinesProvider('athlete-1')
                .overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('No tenés rutina asignada todavía.'),
        findsOneWidget,
      );
    });

    // REQ-HIST-020: WorkoutScreen uses real HistorialSection (not placeholder).
    // Asserts that HistorialSection widget is rendered and shows empty state
    // when sessionsByUidProvider returns an empty list.
    testWidgets(
        'REQ-HIST-020: WorkoutScreen renders HistorialSection with empty state message',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Real HistorialSection must be in the tree (not the private placeholder)
      expect(find.byType(HistorialSection), findsOneWidget);
      // Empty state message from WorkoutStrings
      expect(
        find.text('Todavía no entrenaste.'),
        findsOneWidget,
      );
    });

    testWidgets('no Scaffold / AppBar / SafeArea rendered by WorkoutScreen',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Only 1 Scaffold (the outer test wrapper's)
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(SafeArea), findsNothing);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('no RenderFlex overflow when pumped in 800-height container',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'PlantillasSection is present and functional with filteredRoutinesProvider override',
        (tester) async {
      final routines = [makeRoutine(id: 'r1'), makeRoutine(id: 'r2')];

      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            routinesProvider.overrideWith((ref) async => routines),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PlantillasSection), findsOneWidget);
    });
  });

  // ─── Two-page Entrenar tab (rankings-v2 Phase 2, task 2.1) ────────────────
  //
  // Spec `gym-rankings` — Rankings Placement: for the athlete role, rankings
  // MUST be reachable as the second page of the Entrenar tab, by swipe
  // and/or a top tab control. Trainer role NEVER sees the rankings page.
  // Design `sdd/rankings-v2/design` AD-1: fixed 2-page DefaultTabController +
  // swipeable TabBarView, zero added rebuilds to page 0's section providers.
  group('WorkoutScreen — two-page Entrenar tab', () {
    const uid = 'athlete-1';
    const gymId = 'gym-a';

    UserProfile athleteProfile({String? gymIdOverride = gymId}) => UserProfile(
          uid: uid,
          email: 'a1@test.com',
          displayName: 'Athlete',
          role: UserRole.athlete,
          createdAt: DateTime.utc(2026, 5, 12),
          updatedAt: DateTime.utc(2026, 5, 12),
          gymId: gymIdOverride,
        );

    UserProfile trainerProfile() => UserProfile(
          uid: uid,
          email: 't1@test.com',
          displayName: 'Trainer',
          role: UserRole.trainer,
          createdAt: DateTime.utc(2026, 5, 12),
          updatedAt: DateTime.utc(2026, 5, 12),
        );

    List<Override> rankingsOverrides({bool rankingOptIn = true}) => [
          userPublicProfileProvider(uid).overrideWith(
            (_) => Stream.value(
              UserPublicProfile(uid: uid, rankingOptIn: rankingOptIn),
            ),
          ),
          streakLeaderboardProvider(gymId).overrideWith((_) async => []),
          volumeLeaderboardProvider(gymId).overrideWith((_) async => []),
          squatLeaderboardProvider(gymId).overrideWith((_) async => []),
          benchLeaderboardProvider(gymId).overrideWith((_) async => []),
          deadliftLeaderboardProvider(gymId).overrideWith((_) async => []),
          // AD-4 self-heal fires unconditionally via ref.read whenever
          // rankingOptIn == true — default to a no-op fake so these tests
          // never touch real Firestore through the singleton controller.
          rankingOptInControllerProvider
              .overrideWithValue(_FakeRankingOptInController()),
        ];

    Widget wrapAthleteWorkout({
      String? initialTab,
      List<Override> overrides = const [],
    }) =>
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            sessionsByUidProvider.overrideWith((ref, u) async => []),
            authStateChangesProvider
                .overrideWith((ref) => Stream.value(fakeUser(uid))),
            currentAthleteLinkProvider.overrideWith((ref) async => null),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(athleteProfile()),
            ),
            routinesProvider.overrideWith((ref) async => []),
            assignedRoutinesProvider(uid).overrideWith((ref) async => []),
            userCreatedRoutinesProvider(uid).overrideWith((ref) => Stream.value(
                  const <Routine>[],
                )),
            ...rankingsOverrides(),
            ...overrides,
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: Scaffold(
              body: SizedBox(
                height: 800,
                child: WorkoutScreen(initialTab: initialTab),
              ),
            ),
          ),
        );

    testWidgets(
        'default (initialTab absent) starts _AthleteWorkout on page 0 '
        '("Tu entreno")', (tester) async {
      await tester.pumpWidget(wrapAthleteWorkout());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(MiPlanSection), findsOneWidget);
      expect(find.byKey(const Key('rankings_invitation_state')), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
    });

    testWidgets("initialTab: 'rankings' starts on page 1 (Rankings)",
        (tester) async {
      await tester.pumpWidget(wrapAthleteWorkout(initialTab: 'rankings'));
      await tester.pumpAndSettle();

      expect(find.byType(MiPlanSection), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
    });

    testWidgets('swiping the TabBarView switches pages', (tester) async {
      await tester.pumpWidget(wrapAthleteWorkout());
      await tester.pumpAndSettle();

      expect(find.byType(MiPlanSection), findsOneWidget);

      await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      expect(find.byType(MiPlanSection), findsNothing);
      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
    });

    testWidgets(
        'a trainer-role user still renders ONLY TrainerWorkoutView — no '
        'TabBar, no rankings page, no swipe target exists', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            sessionsByUidProvider.overrideWith((ref, u) async => []),
            authStateChangesProvider
                .overrideWith((ref) => const Stream.empty()),
            currentAthleteLinkProvider.overrideWith((ref) async => null),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(trainerProfile()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const Scaffold(
              body: SizedBox(height: 800, child: WorkoutScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TrainerWorkoutView), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
    });

    testWidgets(
        "page 0's section providers are NOT rebuilt when swiping to page 1 "
        'and back (keep-alive assertion)', (tester) async {
      var buildCount = 0;

      await tester.pumpWidget(wrapAthleteWorkout(overrides: [
        assignedRoutinesProvider(uid).overrideWith((ref) async {
          buildCount++;
          return <Routine>[];
        }),
      ]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(buildCount, equals(1));

      // Swipe to page 1 (Rankings).
      await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 800);
      await tester.pumpAndSettle();

      // Swipe back to page 0 (Tu entreno).
      await tester.fling(find.byType(TabBarView), const Offset(400, 0), 800);
      await tester.pumpAndSettle();

      expect(find.byType(MiPlanSection), findsOneWidget);
      // autoDispose provider would re-fire if page 0 was disposed on swipe
      // away — keep-alive means the FutureProvider result is cached, so the
      // fetch only runs once.
      expect(buildCount, equals(1));
    });
  });

  // ─── Rankings page host (rankings-v2 Phase 2, task 2.3) ────────────────────
  //
  // Page 1 hosts the gated rankings surface (the Phase 1 leaderboard body) —
  // reusing the invitation/leaderboards override pattern from
  // rankings_screen_test.dart.
  group('WorkoutScreen — rankings page host', () {
    const uid = 'athlete-1';
    const gymId = 'gym-a';

    UserProfile athleteProfile() => UserProfile(
          uid: uid,
          email: 'a1@test.com',
          displayName: 'Athlete',
          role: UserRole.athlete,
          createdAt: DateTime.utc(2026, 5, 12),
          updatedAt: DateTime.utc(2026, 5, 12),
          gymId: gymId,
        );

    Widget wrapAthleteWorkout({
      required bool rankingOptIn,
    }) =>
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            sessionsByUidProvider.overrideWith((ref, u) async => []),
            authStateChangesProvider
                .overrideWith((ref) => Stream.value(fakeUser(uid))),
            currentAthleteLinkProvider.overrideWith((ref) async => null),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(athleteProfile()),
            ),
            routinesProvider.overrideWith((ref) async => []),
            assignedRoutinesProvider(uid).overrideWith((ref) async => []),
            userCreatedRoutinesProvider(uid).overrideWith((ref) => Stream.value(
                  const <Routine>[],
                )),
            userPublicProfileProvider(uid).overrideWith(
              (_) => Stream.value(
                UserPublicProfile(uid: uid, rankingOptIn: rankingOptIn),
              ),
            ),
            streakLeaderboardProvider(gymId).overrideWith((_) async => []),
            volumeLeaderboardProvider(gymId).overrideWith((_) async => []),
            squatLeaderboardProvider(gymId).overrideWith((_) async => []),
            benchLeaderboardProvider(gymId).overrideWith((_) async => []),
            deadliftLeaderboardProvider(gymId).overrideWith((_) async => []),
            rankingOptInControllerProvider
                .overrideWithValue(_FakeRankingOptInController()),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: WorkoutScreen(initialTab: 'rankings'),
              ),
            ),
          ),
        );

    testWidgets('invitation state renders when opted out', (tester) async {
      await tester.pumpWidget(wrapAthleteWorkout(rankingOptIn: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
          find.byKey(const Key('rankings_invitation_state')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_streak')), findsNothing);
    });

    testWidgets('leaderboards state renders when opted in', (tester) async {
      await tester.pumpWidget(wrapAthleteWorkout(rankingOptIn: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rankings_section_streak')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_volume')), findsOneWidget);
      expect(find.byKey(const Key('rankings_section_lifts')), findsOneWidget);
      expect(find.byKey(const Key('rankings_invitation_state')), findsNothing);
    });
  });

  // ─── Disable affordance header (rankings-v2 Phase 2, task 2.7) ─────────────
  group('WorkoutScreen — rankings header disable affordance', () {
    const uid = 'athlete-1';
    const gymId = 'gym-a';

    UserProfile athleteProfile() => UserProfile(
          uid: uid,
          email: 'a1@test.com',
          displayName: 'Athlete',
          role: UserRole.athlete,
          createdAt: DateTime.utc(2026, 5, 12),
          updatedAt: DateTime.utc(2026, 5, 12),
          gymId: gymId,
        );

    Widget wrapAthleteWorkout({
      required RankingOptInControllerBase controller,
    }) =>
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue(uid),
            sessionsByUidProvider.overrideWith((ref, u) async => []),
            authStateChangesProvider
                .overrideWith((ref) => Stream.value(fakeUser(uid))),
            currentAthleteLinkProvider.overrideWith((ref) async => null),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(athleteProfile()),
            ),
            routinesProvider.overrideWith((ref) async => []),
            assignedRoutinesProvider(uid).overrideWith((ref) async => []),
            userCreatedRoutinesProvider(uid).overrideWith((ref) => Stream.value(
                  const <Routine>[],
                )),
            userPublicProfileProvider(uid).overrideWith(
              (_) => Stream.value(
                const UserPublicProfile(uid: uid, rankingOptIn: true),
              ),
            ),
            streakLeaderboardProvider(gymId).overrideWith((_) async => []),
            volumeLeaderboardProvider(gymId).overrideWith((_) async => []),
            squatLeaderboardProvider(gymId).overrideWith((_) async => []),
            benchLeaderboardProvider(gymId).overrideWith((_) async => []),
            deadliftLeaderboardProvider(gymId).overrideWith((_) async => []),
            rankingOptInControllerProvider.overrideWithValue(controller),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const Scaffold(
              body: SizedBox(
                height: 800,
                child: WorkoutScreen(initialTab: 'rankings'),
              ),
            ),
          ),
        );

    testWidgets(
        'disable affordance is accessible in the slim header, confirming '
        'calls disableRankingOptIn', (tester) async {
      final fake = _FakeRankingOptInController();
      await tester.pumpWidget(wrapAthleteWorkout(controller: fake));
      await tester.pumpAndSettle();

      // Both the segmented tab pill and the slim page header read
      // "RANKINGS" (tab label vs. header title) — assert 2, not scoping by
      // text alone.
      expect(find.text('RANKINGS'), findsNWidgets(2));
      expect(
          find.byKey(const Key('rankings_disable_affordance')), findsOneWidget);

      await tester.tap(find.byKey(const Key('rankings_disable_affordance')));
      await tester.pumpAndSettle();

      // Confirm dialog appears — confirm it.
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();

      expect(fake.disabledCalls, equals([uid]));
    });
  });
}

class _FakeRankingOptInController implements RankingOptInControllerBase {
  final List<String> enabledCalls = [];
  final List<String> disabledCalls = [];

  @override
  Future<void> enableRankingOptIn(String uid) async {
    enabledCalls.add(uid);
  }

  @override
  Future<void> disableRankingOptIn(String uid) async {
    disabledCalls.add(uid);
  }

  @override
  Future<void> syncGymIfDesynced(String uid) async {}
}
