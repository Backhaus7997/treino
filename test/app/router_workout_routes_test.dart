import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

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
            routerConfig: router,
          ),
        ),
      );

      router.go('/workout/exercise/bench-press');
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseDetailScreen), findsOneWidget);
      expect(find.byType(TreinoBottomBar), findsOneWidget);
    });
  });
}
