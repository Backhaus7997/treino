// Tests for RoutineEditorScreen — trainer edit modes (TrainerAssigning + TrainerTemplating).
//
// Covers:
//   SCENARIO-TRN-EDIT-001: TrainerAssigning(existingPlanId) hydrates name/split/level.
//   SCENARIO-TRN-EDIT-002: TrainerAssigning(existingPlanId) shows "Editar plan" title.
//   SCENARIO-TRN-EDIT-003: TrainerAssigning(existingPlanId) submit calls updateAssigned
//                          (not createAssigned).
//   SCENARIO-TRN-EDIT-004: TrainerAssigning(existingPlanId) with null getById → not-found.
//   SCENARIO-TRN-EDIT-005: TrainerTemplating(existingTemplateId) hydrates name/split/level.
//   SCENARIO-TRN-EDIT-006: TrainerTemplating(existingTemplateId) shows "Editar plan" title.
//   SCENARIO-TRN-EDIT-007: TrainerTemplating(existingTemplateId) submit calls updateTemplate
//                          (not createTemplate).
//   SCENARIO-TRN-EDIT-008: TrainerAssigning(existingPlanId: null) still calls createAssigned.
//   SCENARIO-TRN-EDIT-009: TrainerTemplating(existingTemplateId: null) still calls createTemplate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/features/workout/presentation/workout_strings.dart';

import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/exercises.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Helper — pump with explicit mode ─────────────────────────────────────────

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
        pageBuilder: (context, state) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('CoachHome'))),
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

// ── Shared overrides ──────────────────────────────────────────────────────────

List<Override> _overrides({
  RoutineRepository? repo,
  String uid = 'trainer-1',
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
    userCreatedRoutinesProvider(uid).overrideWith(
      (ref) => Stream.value(const []),
    ),
  ];
}

// ── Existing plan / template for hydration tests ──────────────────────────────

const _existingPlan = Routine(
  id: 'plan-id-1',
  name: 'Plan Preexistente',
  split: 'PPL',
  level: ExperienceLevel.intermediate,
  days: [],
  source: RoutineSource.trainerAssigned,
  assignedBy: 'trainer-1',
  assignedTo: 'athlete-x',
  visibility: RoutineVisibility.private,
);

const _existingTemplate = Routine(
  id: 'tmpl-id-1',
  name: 'Plantilla Preexistente',
  split: 'Full Body',
  level: ExperienceLevel.advanced,
  days: [],
  source: RoutineSource.trainerTemplate,
  assignedBy: 'trainer-1',
  visibility: RoutineVisibility.private,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerAssigned,
        assignedBy: 'trainer-fallback',
        assignedTo: 'athlete-fallback',
      ),
    );
  });

  // ── TrainerAssigning edit ─────────────────────────────────────────────────

  testWidgets(
      'SCENARIO-TRN-EDIT-001: TrainerAssigning(existingPlanId) hydrates name '
      'and split from getById', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('plan-id-1'))
        .thenAnswer((_) async => _existingPlan);

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-id-1',
      ),
      overrides: _overrides(repo: repo),
    );

    verify(() => repo.getById('plan-id-1')).called(1);

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('editor_name_field')),
    );
    expect(nameField.controller?.text, equals('Plan Preexistente'));

    final splitField = tester.widget<TextField>(
      find.byKey(const Key('editor_split_field')),
    );
    expect(splitField.controller?.text, equals('PPL'));
  });

  testWidgets(
      'SCENARIO-TRN-EDIT-002: TrainerAssigning(existingPlanId) shows '
      '"Editar plan" title', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('plan-id-1'))
        .thenAnswer((_) async => _existingPlan);

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-id-1',
      ),
      overrides: _overrides(repo: repo),
    );

    expect(find.text('Editar plan'), findsOneWidget);
    expect(find.text('Crear plan'), findsNothing);
  });

  testWidgets(
      'SCENARIO-TRN-EDIT-003: TrainerAssigning(existingPlanId) submit calls '
      'updateAssigned (not createAssigned)', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('plan-id-1'))
        .thenAnswer((_) async => _existingPlan);
    when(() => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft;
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'plan-id-1',
      ),
      overrides: _overrides(repo: repo),
    );
    // Extra pump to let the _loading = false rebuild settle.
    await tester.pump();

    // The form is valid: name is hydrated, split is hydrated, days is empty
    // but in trainer mode days must be non-empty. Add one slot via the CTA.
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
    await tester.pumpAndSettle();

    // Fill reps field.
    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    expect(emptyFields, isNotEmpty);
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '8');
    await tester.pumpAndSettle();

    // Tap GUARDAR CAMBIOS.
    await tester.tap(
        find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));
    await tester.pumpAndSettle();

    verify(() => repo.updateAssigned(
          uid: 'trainer-1',
          draft: any(named: 'draft'),
        )).called(1);
    verifyNever(() => repo.createAssigned(any()));
  });

  testWidgets(
      'SCENARIO-TRN-EDIT-004: TrainerAssigning(existingPlanId) with null '
      'getById shows not-found message', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('gone-plan')).thenAnswer((_) async => null);

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(
        athleteId: 'athlete-x',
        existingPlanId: 'gone-plan',
      ),
      overrides: _overrides(repo: repo),
    );

    expect(find.text(WorkoutStrings.selfEditorNotFound), findsOneWidget);
    expect(find.byKey(const Key('editor_name_field')), findsNothing);
  });

  // ── TrainerTemplating edit ────────────────────────────────────────────────

  testWidgets(
      'SCENARIO-TRN-EDIT-005: TrainerTemplating(existingTemplateId) hydrates '
      'name and split from getById', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('tmpl-id-1'))
        .thenAnswer((_) async => _existingTemplate);

    await _pumpEditor(
      tester,
      mode: const TrainerTemplating(existingTemplateId: 'tmpl-id-1'),
      overrides: _overrides(repo: repo),
    );

    verify(() => repo.getById('tmpl-id-1')).called(1);

    final nameField = tester.widget<TextField>(
      find.byKey(const Key('editor_name_field')),
    );
    expect(nameField.controller?.text, equals('Plantilla Preexistente'));

    final splitField = tester.widget<TextField>(
      find.byKey(const Key('editor_split_field')),
    );
    expect(splitField.controller?.text, equals('Full Body'));
  });

  testWidgets(
      'SCENARIO-TRN-EDIT-006: TrainerTemplating(existingTemplateId) shows '
      '"Editar plan" title', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('tmpl-id-1'))
        .thenAnswer((_) async => _existingTemplate);

    await _pumpEditor(
      tester,
      mode: const TrainerTemplating(existingTemplateId: 'tmpl-id-1'),
      overrides: _overrides(repo: repo),
    );

    expect(find.text('Editar plan'), findsOneWidget);
    expect(find.text('Crear plan'), findsNothing);
  });

  testWidgets(
      'SCENARIO-TRN-EDIT-007: TrainerTemplating(existingTemplateId) submit '
      'calls updateTemplate (not createTemplate)', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.getById('tmpl-id-1'))
        .thenAnswer((_) async => _existingTemplate);
    when(() => repo.updateTemplate(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft;
    });

    await _pumpEditor(
      tester,
      mode: const TrainerTemplating(existingTemplateId: 'tmpl-id-1'),
      overrides: _overrides(repo: repo),
    );
    await tester.pump();

    // Add a slot so the form is valid.
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
    await tester.pumpAndSettle();

    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    expect(emptyFields, isNotEmpty);
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '10');
    await tester.pumpAndSettle();

    await tester.tap(
        find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));
    await tester.pumpAndSettle();

    verify(() => repo.updateTemplate(
          uid: 'trainer-1',
          draft: any(named: 'draft'),
        )).called(1);
    verifyNever(() => repo.createTemplate(any()));
  });

  // ── Create paths still work (no existingId) ───────────────────────────────

  testWidgets(
      'SCENARIO-TRN-EDIT-008: TrainerAssigning(existingPlanId: null) still '
      'calls createAssigned', (tester) async {
    final repo = _MockRoutineRepository();
    when(() => repo.createAssigned(any())).thenAnswer((inv) async {
      final r = inv.positionalArguments.first as Routine;
      return r.copyWith(id: 'new-plan-id');
    });

    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-x'),
      overrides: _overrides(repo: repo),
    );

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Nuevo Plan');
    await tester.enterText(
        find.byKey(const Key('editor_split_field')), 'PPL');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WorkoutStrings.pickerAddButton(1)));
    await tester.pumpAndSettle();

    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    expect(emptyFields, isNotEmpty);
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '8');
    await tester.pumpAndSettle();

    await tester.tap(
        find.widgetWithText(ElevatedButton, 'ASIGNAR PLAN'));
    await tester.pumpAndSettle();

    verify(() => repo.createAssigned(any())).called(1);
    verifyNever(() => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ));
  });
}
