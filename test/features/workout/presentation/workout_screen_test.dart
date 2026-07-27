import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/historial_section.dart';
import 'package:treino/features/workout/presentation/widgets/rutinas_section.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_section.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';
import 'package:treino/features/workout/workout_screen.dart';

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
        // RutinasSection: resolve the unified list to empty so tests that
        // only care about PLANTILLAS / HISTORIAL don't need a full stack.
        authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        assignedRoutinesProvider('test-uid').overrideWith((ref) async => []),
        userCreatedRoutinesProvider('test-uid')
            .overrideWith((ref) => Stream.value(const <Routine>[])),
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
        'three sections rendered in order: RUTINAS → PLANTILLAS → HISTORIAL',
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

      // The unified RutinasSection replaces the old MiPlan + MisRutinas pair
      // (workout redesign slice 1).
      expect(find.byType(RutinasSection), findsOneWidget);
      expect(find.text('PLANTILLAS'), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);

      final rutinasPos = tester.getTopLeft(find.byType(RutinasSection)).dy;
      final plantillasPos = tester.getTopLeft(find.text('PLANTILLAS')).dy;
      final historialPos = tester.getTopLeft(find.text('HISTORIAL')).dy;

      expect(rutinasPos, lessThanOrEqualTo(plantillasPos));
      expect(plantillasPos, lessThan(historialPos));
    });

    testWidgets(
        'RutinasSection empty state appears when the unified list is empty',
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

      expect(
        find.text(
          'Todavía no creaste ninguna rutina. '
          'Tocá CREAR RUTINA para armar la primera.',
        ),
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

  // ─── Rankings relocation ──────────────────────────────────────────────────
  //
  // Rankings moved from the Entrenar tab to the FEED tab
  // (`/feed?tab=rankings`) — WorkoutScreen is single-page again for
  // athletes: no TabBar, no rankings page. Rankings host coverage lives in
  // feed_screen_test.dart.
  group('WorkoutScreen — no rankings tab', () {
    testWidgets('athlete body renders without TabBar or rankings page',
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

      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
      expect(find.text('RANKINGS'), findsNothing);
      expect(find.byType(RutinasSection), findsOneWidget);
    });

    testWidgets('a trainer-role user renders ONLY TrainerWorkoutView',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          overrides: [
            userProfileProvider.overrideWith(
              (ref) => Stream.value(
                UserProfile(
                  uid: 'u1',
                  email: 't1@test.com',
                  displayName: 'Trainer',
                  role: UserRole.trainer,
                  createdAt: DateTime.utc(2026, 5, 12),
                  updatedAt: DateTime.utc(2026, 5, 12),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TrainerWorkoutView), findsOneWidget);
      expect(find.byType(TabBar), findsNothing);
      expect(find.byType(TabBarView), findsNothing);
    });
  });
}
