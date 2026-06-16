// Tests for RoutineEditorScreen — string localization.
//
// Regression guard: the editor used to hardcode Spanish for many user-facing
// labels (section headers, week controls, default day name, slot/set menus).
// These now flow through AppL10n, so rendering the editor under a non-Spanish
// locale must surface the localized (English) copy — not the old literals.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/exercises.dart';

class _FakeRoutineRepository extends Fake implements RoutineRepository {}

Future<void> _pumpEditorEn(
  WidgetTester tester, {
  required RoutineEditorMode mode,
}) async {
  const uid = 'athlete-loc-1';
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        routineRepositoryProvider.overrideWithValue(_FakeRoutineRepository()),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider(uid).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider(uid).overrideWith(
          (ref) => Stream<List<Routine>>.value(const []),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('en'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'editor renders localized (EN) labels instead of hardcoded Spanish',
    (tester) async {
      await _pumpEditorEn(tester, mode: const SelfCreating());

      // English copy is present.
      expect(find.text('WEEKS'), findsOneWidget);
      expect(find.text('PLAN DAYS'), findsOneWidget);
      expect(find.text('Day 1'), findsOneWidget); // default day name

      // The old hardcoded Spanish literals must not leak under en.
      expect(find.text('SEMANAS'), findsNothing);
      expect(find.text('DÍAS DEL PLAN'), findsNothing);
      expect(find.text('Día 1'), findsNothing);
    },
  );
}
