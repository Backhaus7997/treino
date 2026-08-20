import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/l10n/app_l10n.dart';
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
import 'package:treino/features/workout/presentation/widgets/plantillas_tab.dart';
import 'package:treino/features/workout/presentation/widgets/rutinas_section.dart';
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

TrainerLink makeLink() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrapWorkout(
  Widget w, {
  List<Override> overrides = const [],
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('test-uid'),
        sessionsByUidProvider.overrideWith((ref, uid) async => []),
        // RutinasSection: resolve the unified list to empty so tests that
        // only care about EXPLORAR / HISTORIAL don't need a full stack.
        authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        assignedRoutinesProvider('test-uid').overrideWith((ref) async => []),
        userCreatedRoutinesProvider('test-uid')
            .overrideWith((ref) => Stream.value(const <Routine>[])),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
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

  // ─── WorkoutScreen tests (workout redesign slice 2: 2 tabs) ───────────────

  group('WorkoutScreen — tab TU ENTRENO (page 0)', () {
    testWidgets(
        'accessibility text scale grows and scrolls the top tabs without overflow',
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(),
          textScaler: const TextScaler.linear(3.2),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('TU ENTRENO').hitTestable(), findsOneWidget);
      for (final label in ['TU ENTRENO', 'EXPLORAR']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.maxLines, 1);
        expect(text.softWrap, isFalse);
      }
    });

    testWidgets(
        'default: pill tabs TU ENTRENO | EXPLORAR y page 0 con '
        'RUTINAS → HISTORIAL (sin secciones de plantillas)', (tester) async {
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

      // Segmented pill control with both labels.
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('TU ENTRENO'), findsOneWidget);
      expect(find.text('EXPLORAR'), findsOneWidget);

      // Page 0 body: unified routines + history, in that order. The template
      // sections left this page — they live in the EXPLORAR tab now.
      expect(find.byType(RutinasSection), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);
      expect(find.byType(PlantillasTab), findsNothing);

      final rutinasPos = tester.getTopLeft(find.byType(RutinasSection)).dy;
      final historialPos = tester.getTopLeft(find.text('HISTORIAL')).dy;
      expect(rutinasPos, lessThanOrEqualTo(historialPos));
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
  });

  group('WorkoutScreen — tab EXPLORAR (page 1)', () {
    testWidgets('tapping the EXPLORAR tab shows the unified template grid',
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

      await tester.tap(find.text('EXPLORAR'));
      await tester.pumpAndSettle();

      expect(find.byType(PlantillasTab), findsOneWidget);
      expect(find.text('ROUTINE'), findsNWidgets(2));
      // Page 0 swiped away.
      expect(find.byType(RutinasSection), findsNothing);
    });

    testWidgets("initialTab: 'plantillas' opens directly on the grid page",
        (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(initialTab: 'plantillas'),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PlantillasTab), findsOneWidget);
      expect(find.text('No hay rutinas todavía.'), findsOneWidget);
      expect(find.byType(RutinasSection), findsNothing);
    });

    testWidgets(
        "unknown initialTab (e.g. 'rankings'-era junk) falls back to "
        'page 0 without crashing', (tester) async {
      await tester.pumpWidget(
        _wrapWorkout(
          const WorkoutScreen(initialTab: 'xyz'),
          overrides: [
            routinesProvider.overrideWith((ref) async => []),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(RutinasSection), findsOneWidget);
      expect(find.byType(PlantillasTab), findsNothing);
    });

    testWidgets(
        'lifecycle: la cadena de templates del coach sobrevive los swipes '
        '(keep-alive) y se libera al desmontar la pantalla', (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue('test-uid'),
          sessionsByUidProvider.overrideWith((ref, uid) async => []),
          authStateChangesProvider.overrideWith((ref) => const Stream.empty()),
          currentAthleteLinkProvider.overrideWith((ref) async => makeLink()),
          assignedRoutinesProvider('test-uid').overrideWith((ref) async => []),
          userCreatedRoutinesProvider('test-uid')
              .overrideWith((ref) => Stream.value(const <Routine>[])),
          routinesProvider.overrideWith((ref) async => []),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(
              const UserPublicProfile(
                uid: 'trainer-1',
                displayName: 'Coach Vic',
                displayNameLowercase: 'coach vic',
                sharedTemplatesWithAthletes: true,
              ),
            ),
          ),
          trainerTemplatesStreamProvider('trainer-1').overrideWith(
            (ref) => Stream.value([makeRoutine(id: 'coach-1')]),
          ),
        ],
      );
      addTearDown(container.dispose);

      Widget host(Widget child) => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.dark(),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              locale: const Locale('es', 'AR'),
              home: Scaffold(
                body: SizedBox(height: 800, child: child),
              ),
            ),
          );

      await tester.pumpWidget(host(const WorkoutScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Page 0 activa: EXPLORAR nunca se visitó → la cadena del coach ni
      // siquiera se construyó.
      expect(
        container.exists(trainerTemplatesStreamProvider('trainer-1')),
        isFalse,
      );

      await tester.drag(find.byType(TabBarView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pump();
      expect(find.byType(PlantillasTab), findsOneWidget);
      expect(
        container.exists(trainerTemplatesStreamProvider('trainer-1')),
        isTrue,
      );

      // Volver a TU ENTRENO: keep-alive → el stream NO se desmonta (sin
      // churn de listener ni flicker del coach al volver a EXPLORAR).
      await tester.drag(find.byType(TabBarView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(RutinasSection), findsOneWidget);
      expect(
        container.exists(trainerTemplatesStreamProvider('trainer-1')),
        isTrue,
      );

      // Salir de /workout (desmontar la pantalla): TODA la cadena
      // autoDispose se libera.
      await tester.pumpWidget(host(const SizedBox()));
      await tester.pump();
      await tester.pump();
      expect(
        container.exists(trainerTemplatesStreamProvider('trainer-1')),
        isFalse,
      );
    });

    testWidgets('swiping between pages works both ways', (tester) async {
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

      expect(find.byType(RutinasSection), findsOneWidget);

      // > half the 800px test viewport so the ballistic lands on page 1.
      await tester.drag(find.byType(TabBarView), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(PlantillasTab), findsOneWidget);

      await tester.drag(find.byType(TabBarView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(RutinasSection), findsOneWidget);
    });
  });

  // ─── Rankings relocation ──────────────────────────────────────────────────
  //
  // Rankings moved from the Entrenar tab to the FEED tab
  // (`/feed?tab=rankings`) — the second page here is EXPLORAR now, never
  // rankings. Rankings host coverage lives in feed_screen_test.dart.
  group('WorkoutScreen — no rankings page', () {
    testWidgets('athlete tabs are TU ENTRENO | EXPLORAR — no RANKINGS label',
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
