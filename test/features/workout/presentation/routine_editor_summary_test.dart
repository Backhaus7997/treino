// Tests for the plain-language routine summary field (#648) in the MOBILE
// editor — RoutineEditorScreen.
//
// Covers:
//   - the field renders in the two PF modes (TrainerAssigning, TrainerTemplating)
//   - the field is ABSENT in SelfCreating: firestore.rules lists `summary` in
//     the athlete UPDATE path's keys() but NOT in its affectedKeys(), so the
//     athlete cannot write it, and a field whose every save is a
//     permission-denied is worse than no field at all
//   - the 280-char cap (mirror of `optStrMaxLen(..., 280)` in the rules) and
//     its visible counter
//   - the field is OPTIONAL: saving with it blank persists `summary: null`
//   - an existing resumen hydrates into the field and round-trips on save
//
// Run: flutter test test/features/workout/presentation/routine_editor_summary_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
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
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/routine_editor_ui.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

/// One of the 7 seeded system resúmenes, verbatim — 74 characters, the length
/// the field is designed around (the seeded set spans 61–100).
const _kResumen =
    'Empujar, tirar y piernas: cada día trabajás un tipo de movimiento distinto.';

final _summaryField = find.byKey(const Key('editor_summary_field'));

/// Trainer-assigned plan with no days — the hydration tests add the exercise
/// the save gate requires.
Routine _planWithSummary(String? summary) => Routine(
      id: 'plan-1',
      name: 'Plan del PF',
      split: 'PPL',
      level: ExperienceLevel.intermediate,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-1',
      assignedTo: 'athlete-1',
      visibility: RoutineVisibility.private,
      summary: summary,
    );

/// Athlete-owned routine that already carries a PF-authored resumen.
Routine _ownRoutineWithSummary(String summary) => Routine(
      id: 'own-1',
      name: 'Mi rutina',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      createdBy: 'trainer-1',
      visibility: RoutineVisibility.private,
      summary: summary,
    );

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  RoutineRepository? repo,
}) async {
  final mockRepo = repo ?? _MockRoutineRepository();
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
      overrides: [
        currentUidProvider.overrideWithValue('trainer-1'),
        routineRepositoryProvider.overrideWithValue(mockRepo),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider('trainer-1').overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const []),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider('trainer-1').overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
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

/// Adds one exercise with complete reps so the save gate opens — every day
/// needs at least one exercise and every visible set needs its reps.
Future<void> _addOneExercise(WidgetTester tester) async {
  // The CTA lives inside the editor's ListView, below the RESUMEN field —
  // scroll it into the 800x600 test viewport before tapping.
  // `scrollUntilVisible` y no `ensureVisible`: el editor es un ListView y
  // el CTA no está CONSTRUIDO hasta que se scrollea hasta él —
  // `ensureVisible` necesita un elemento que ya exista y tira "No element".
  // Se notó al sumar el selector PARA QUÉ SIRVE (#635 PR#1b), que corrió el
  // CTA fuera del área inicial en modo plantilla.
  await tester.scrollUntilVisible(
    find.text('Agregar ejercicio'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 1 ejercicio'));
  await tester.pumpAndSettle();
  // Desde este cambio el ejercicio agregado nace PLEGADO: quien avisa
  // que le falta completar sets es el borde rojo, no la card abierta.
  await expandirEjercicios(tester);

  final emptyFields = find.byType(TextField).evaluate().where((e) {
    final w = e.widget as TextField;
    return w.controller != null && w.controller!.text.isEmpty;
  }).toList();
  expect(emptyFields, isNotEmpty);
  final repsField = emptyFields.last.widget as TextField;
  await tester.enterText(find.byWidget(repsField), '8');
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ElevatedButton, label));
  await tester.pumpAndSettle();
}

/// Captures the single [Routine] passed to a mocked update call.
Routine _capturedDraft(VerificationResult result) =>
    result.captured.single as Routine;

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerAssigned,
        assignedBy: 'trainer-fallback',
        assignedTo: 'athlete-fallback',
      ),
    );
  });

  // ── Mode gate ───────────────────────────────────────────────────────────

  group('mode gate — PF only', () {
    testWidgets('renders in TrainerAssigning', (tester) async {
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
      );

      expect(_summaryField, findsOneWidget);
    });

    testWidgets('renders in TrainerTemplating', (tester) async {
      await _pumpEditor(tester, mode: const TrainerTemplating());

      expect(_summaryField, findsOneWidget);
    });

    testWidgets(
        'is ABSENT in SelfCreating — the athlete cannot write summary, and a '
        'field whose every save is permission-denied is worse than no field',
        (tester) async {
      await _pumpEditor(tester, mode: const SelfCreating());

      expect(_summaryField, findsNothing);
      expect(find.text('RESUMEN'), findsNothing);
    });
  });

  // ── Copy ────────────────────────────────────────────────────────────────

  group('copy', () {
    testWidgets('says what the field is for, in plain language',
        (tester) async {
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
      );

      expect(find.text('RESUMEN'), findsOneWidget);
      expect(
        find.text(
          'Una frase que explique qué es la rutina, para alguien que nunca '
          'pisó un gimnasio.',
        ),
        findsOneWidget,
      );
    });
  });

  // ── 280-char cap ────────────────────────────────────────────────────────

  group('280-char cap (mirrors optStrMaxLen in firestore.rules)', () {
    testWidgets('truncates input past 280 characters', (tester) async {
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
      );

      await tester.enterText(_summaryField, 'A' * 400);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(_summaryField);
      expect(field.maxLength, equals(280));
      expect(field.controller!.text.length, equals(280));
    });

    testWidgets('shows a live character counter', (tester) async {
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-1'),
      );

      // The counter is NOT suppressed the way the coaching-note field
      // suppresses its own with counterText: '' — here the cap is an editorial
      // constraint the PF writes against.
      expect(find.text('0/280'), findsOneWidget);

      await tester.enterText(_summaryField, _kResumen);
      await tester.pumpAndSettle();

      expect(find.text('${_kResumen.length}/280'), findsOneWidget);
    });
  });

  // ── Persistence ─────────────────────────────────────────────────────────

  group('persistence — trainer-assigned plan', () {
    testWidgets('saves the trimmed resumen', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('plan-1'))
          .thenAnswer((_) async => _planWithSummary(null));
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-1',
          existingPlanId: 'plan-1',
        ),
        repo: repo,
      );
      // Type the resumen BEFORE adding the exercise: the editor body is a
      // ListView, so once the exercise card pushes the field past the fold it
      // leaves the tree entirely.
      await tester.enterText(_summaryField, '  $_kResumen  ');
      await tester.pumpAndSettle();
      await _addOneExercise(tester);
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      expect(draft.summary, equals(_kResumen));
    });

    testWidgets(
        'is OPTIONAL — a plan saved with the field untouched persists '
        'summary: null, not an empty string', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('plan-1'))
          .thenAnswer((_) async => _planWithSummary(null));
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-1',
          existingPlanId: 'plan-1',
        ),
        repo: repo,
      );
      await _addOneExercise(tester);

      // Resumen deliberately left blank — the save must still go through.
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      expect(draft.summary, isNull);
      expect(draft.name, equals('Plan del PF'));
    });

    testWidgets('whitespace-only input saves as null', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('plan-1'))
          .thenAnswer((_) async => _planWithSummary(null));
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-1',
          existingPlanId: 'plan-1',
        ),
        repo: repo,
      );
      await tester.enterText(_summaryField, '   ');
      await tester.pumpAndSettle();
      await _addOneExercise(tester);
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      expect(draft.summary, isNull);
    });

    testWidgets('hydrates an existing resumen and round-trips it on save',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('plan-1'))
          .thenAnswer((_) async => _planWithSummary(_kResumen));
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-1',
          existingPlanId: 'plan-1',
        ),
        repo: repo,
      );

      final field = tester.widget<TextField>(_summaryField);
      expect(field.controller!.text, equals(_kResumen));

      await _addOneExercise(tester);
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      expect(draft.summary, equals(_kResumen));
    });

    testWidgets('an emptied field clears the resumen', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('plan-1'))
          .thenAnswer((_) async => _planWithSummary(_kResumen));
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-1',
          existingPlanId: 'plan-1',
        ),
        repo: repo,
      );
      await tester.enterText(_summaryField, '');
      await tester.pumpAndSettle();
      await _addOneExercise(tester);
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      expect(draft.summary, isNull);
    });
  });

  group('persistence — trainer template', () {
    testWidgets('saves the resumen on a template', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createTemplate(any())).thenAnswer(
        (inv) async =>
            (inv.positionalArguments.first as Routine).copyWith(id: 'tmpl-1'),
      );

      await _pumpEditor(tester, mode: const TrainerTemplating(), repo: repo);

      await tester.enterText(
        find.byKey(const Key('editor_name_field')),
        'Full Body para principiantes',
      );
      await tester.enterText(
        find.byKey(const Key('editor_split_field')),
        'Full Body',
      );
      await tester.enterText(_summaryField, _kResumen);
      await tester.pumpAndSettle();
      await _addOneExercise(tester);
      // Es una PLANTILLA: desde #871 su CTA dice lo suyo en vez de reusar el
      // de asignar un plan, que hablaba de asignarle algo a alguien.
      await _tapSave(tester, 'GUARDAR PLANTILLA');

      final draft = verify(() => repo.createTemplate(captureAny()))
          .captured
          .single as Routine;
      expect(draft.summary, equals(_kResumen));
    });
  });

  group('persistence — athlete never writes summary', () {
    testWidgets(
        'an athlete re-saving a routine that carries a resumen sends no '
        'summary at all — the field stays out of the SelfCreating draft',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('own-1'))
          .thenAnswer((_) async => _ownRoutineWithSummary(_kResumen));
      when(() => repo.updateUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer(
        (inv) async => inv.namedArguments[const Symbol('draft')] as Routine,
      );

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'own-1'),
        repo: repo,
      );
      await _addOneExercise(tester);
      await _tapSave(tester, 'GUARDAR CAMBIOS');

      final draft = _capturedDraft(
        verify(
          () => repo.updateUserOwned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ),
      );
      // RoutineRepository.updateUserOwned never puts `summary` in its payload,
      // so the stored resumen survives untouched — this asserts the editor
      // does not smuggle it in either.
      expect(draft.summary, isNull);
    });
  });
}
