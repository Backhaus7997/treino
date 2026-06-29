// Widget tests for the inline day-name editor introduced 2026-06-29.
// Decisión A1 + 2A + E2: tap on the pencil icon turns the day title into a
// TextField; an empty commit restores the localized "Día N" default.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
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
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (_, __) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Override> _overrides({String uid = 'athlete-1'}) {
  final mockRepo = _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    userCreatedRoutinesProvider(uid)
        .overrideWith((ref) => Stream<List<Routine>>.value(const [])),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
  ];
}

const _firstDayPencilKey = Key('day_name_edit_button_1');
const _editingFieldKey = Key('day_name_editing_field');

void main() {
  group('Editable day name (decisión A1 + 2A + E2)', () {
    testWidgets(
      'E2: each day card renders a pencil IconButton next to the title',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        // Default editor opens with at least Día 1; the pencil signals
        // editability per day (decisión E2).
        expect(find.byKey(const Key('day_name_edit_button_1')), findsOneWidget);
      },
    );

    testWidgets(
      'A1: tap pencil swaps the Text for an inline TextField with the current '
      'name pre-selected',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        // Pre-edit: Text "Día 1" present, TextField absent.
        expect(find.text('Día 1'), findsOneWidget);
        expect(find.byKey(_editingFieldKey), findsNothing);

        await tester.tap(find.byKey(_firstDayPencilKey));
        await tester.pumpAndSettle();

        // Post-edit: TextField present, Text label gone (only the editing
        // field stays).
        expect(find.byKey(_editingFieldKey), findsOneWidget);
        final field = tester.widget<TextField>(find.byKey(_editingFieldKey));
        expect(field.controller!.text, 'Día 1');
        // The pencil itself hides while editing — UI signals "you are inside".
        expect(find.byKey(_firstDayPencilKey), findsNothing);
      },
    );

    testWidgets(
      'A1: editing + onSubmitted commits the new custom name and reverts the '
      'TextField to a static Text label',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.tap(find.byKey(_firstDayPencilKey));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(_editingFieldKey),
          'Día 1 - Pecho',
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // New custom label visible.
        expect(find.text('Día 1 - Pecho'), findsOneWidget);
        // Field is gone, pencil is back.
        expect(find.byKey(_editingFieldKey), findsNothing);
        expect(find.byKey(_firstDayPencilKey), findsOneWidget);
      },
    );

    testWidgets(
      '2A: committing an empty string restores the localized "Día N" default '
      '(no error, no friction)',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.tap(find.byKey(_firstDayPencilKey));
        await tester.pumpAndSettle();

        // Set a custom name first.
        await tester.enterText(find.byKey(_editingFieldKey), 'PUSH');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('PUSH'), findsOneWidget);

        // Now wipe it.
        await tester.tap(find.byKey(_firstDayPencilKey));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_editingFieldKey), '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        // Localized default is back, no PUSH leftover.
        expect(find.text('Día 1'), findsOneWidget);
        expect(find.text('PUSH'), findsNothing);
      },
    );

    testWidgets(
      '2A: whitespace-only commit is treated like empty and restores default',
      (tester) async {
        await _pumpEditor(
          tester,
          mode: const SelfCreating(),
          overrides: _overrides(),
        );

        await tester.tap(find.byKey(_firstDayPencilKey));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_editingFieldKey), '   ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Día 1'), findsOneWidget);
      },
    );
  });
}
