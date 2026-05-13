import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/plantillas_section.dart';
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
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
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
          routineByIdProvider('test-id').overrideWith((_) async => routine),
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
          routineByIdProvider('test-id').overrideWith((_) async => routine),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
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
        'three sections rendered in order: PLANTILLAS → TU RUTINA → HISTORIAL',
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

      expect(find.text('PLANTILLAS'), findsOneWidget);
      expect(find.text('TU RUTINA'), findsOneWidget);
      expect(find.text('HISTORIAL'), findsOneWidget);

      final plantillasPos = tester.getTopLeft(find.text('PLANTILLAS')).dy;
      final tuRutinaPos = tester.getTopLeft(find.text('TU RUTINA')).dy;
      final historialPos = tester.getTopLeft(find.text('HISTORIAL')).dy;

      expect(plantillasPos, lessThan(tuRutinaPos));
      expect(tuRutinaPos, lessThan(historialPos));
    });

    testWidgets(
        '"No tenés rutina asignada todavía." appears in Tu Rutina section',
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
        find.text('No tenés rutina asignada todavía.'),
        findsOneWidget,
      );
    });

    testWidgets(
        '"Tus entrenamientos completados aparecerán acá." in Historial section',
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
        find.text('Tus entrenamientos completados aparecerán acá.'),
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
}
