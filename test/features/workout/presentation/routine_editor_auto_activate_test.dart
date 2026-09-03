// Tests for RoutineEditorScreen — auto-activa on SelfCreating create
// (workout-area redesign slice 1, 2026-07-27).
//
// Contract: after a successful createUserOwned, the new routine becomes the
// active one ONLY when the athlete has no active routine yet. An existing
// marker is never stolen; an unresolved profile skips the write (lazy
// adoption in unifiedRoutinesProvider heals it later).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
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
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_analytics_service.dart';
import '../../../fixtures/exercises.dart';

import '../../../helpers/onboarding_test_helpers.dart';
import '../../../fixtures/routine_editor_ui.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

UserProfile _profile({String? activeRoutineId}) => UserProfile(
      onboardingSeen: allSurfacesSeen(),
      uid: 'athlete-1',
      email: 'a1@treino.app',
      displayName: 'A1',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

Future<void> _pumpEditor(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RoutineEditorScreen(mode: SelfCreating()),
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

/// Warms userProfileProvider so the editor's sync read sees resolved data —
/// mirrors production, where the app shell (home header, router redirects)
/// keeps the profile stream alive long before the editor opens. Do NOT call
/// for the unresolved-profile scenario.
Future<void> _warmProfile(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RoutineEditorScreen)),
  );
  container.listen(userProfileProvider, (_, __) {});
  await container.read(userProfileProvider.future);
}

List<Override> _overrides({
  required RoutineRepository repo,
  required UserRepository userRepo,
  Stream<UserProfile?>? profileStream,
  String? activeRoutineId,
}) {
  return [
    currentUidProvider.overrideWithValue('athlete-1'),
    routineRepositoryProvider.overrideWithValue(repo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider('athlete-1').overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
    userCreatedRoutinesProvider('athlete-1').overrideWith(
      (ref) => Stream.value(const <Routine>[]),
    ),
    userProfileProvider.overrideWith(
      (ref) =>
          profileStream ??
          Stream.value(_profile(activeRoutineId: activeRoutineId)),
    ),
    userRepositoryProvider.overrideWithValue(userRepo),
  ];
}

/// Fills the minimum valid SelfCreating form (name + 1 exercise with reps).
/// Mirrors the recipe of routine_editor_athlete_mode_test.dart's submit test.
Future<void> _fillForm(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('editor_name_field')), 'TEST BORRAR');
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
  expect(emptyFields, isNotEmpty, reason: 'expected empty REPS field');
  final repsField = emptyFields.last.widget as TextField;
  await tester.enterText(find.byWidget(repsField), '10');
  await tester.pumpAndSettle();
}

Future<void> _fillAndSubmit(WidgetTester tester) async {
  await _fillForm(tester);
  await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
      ),
    );
  });

  late _MockRoutineRepository repo;
  late _MockUserRepository userRepo;

  setUp(() {
    repo = _MockRoutineRepository();
    when(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft.copyWith(id: 'gen-id');
    });
    userRepo = _MockUserRepository();
    when(() => userRepo.update(any(), any())).thenAnswer((_) async {});
  });

  testWidgets(
      'create WITHOUT an active routine → the new routine is auto-activated '
      '(activeRoutineId = created id)', (tester) async {
    await _pumpEditor(
      tester,
      overrides: _overrides(repo: repo, userRepo: userRepo),
    );
    await _warmProfile(tester);

    await _fillAndSubmit(tester);

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    verify(() => userRepo.update('athlete-1', {'activeRoutineId': 'gen-id'}))
        .called(1);
  });

  testWidgets(
      'create WITH an active routine already set → the marker is NOT stolen',
      (tester) async {
    await _pumpEditor(
      tester,
      overrides: _overrides(
        repo: repo,
        userRepo: userRepo,
        activeRoutineId: 'other-routine',
      ),
    );
    await _warmProfile(tester);

    await _fillAndSubmit(tester);

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    verifyNever(() => userRepo.update(any(), any()));
  });

  testWidgets(
      'create while the profile is UNRESOLVED → create succeeds, activation '
      'is skipped (lazy adoption heals later)', (tester) async {
    await _pumpEditor(
      tester,
      overrides: _overrides(
        repo: repo,
        userRepo: userRepo,
        profileStream: const Stream.empty(),
      ),
    );

    await _fillAndSubmit(tester);

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    verifyNever(() => userRepo.update(any(), any()));
  });

  testWidgets(
      'editor disposed mid-create (back gesture during the await) → no '
      'exception and no activation write (lazy adoption heals later)',
      (tester) async {
    final createCompleter = Completer<Routine>();
    when(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((_) => createCompleter.future);

    await _pumpEditor(
      tester,
      overrides: _overrides(repo: repo, userRepo: userRepo),
    );
    await _warmProfile(tester);
    await _fillForm(tester);

    // Submit — createUserOwned stays in flight (single pump: the submitting
    // state may animate, so no pumpAndSettle here).
    await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
    await tester.pump();

    // Navigate away while the create is still awaiting → editor disposed.
    final ctx = tester.element(find.byType(RoutineEditorScreen));
    GoRouter.of(ctx).go('/workout');
    await tester.pumpAndSettle();
    expect(find.text('WorkoutHome'), findsOneWidget);

    // The create resolves AFTER disposal: the mounted-guard must bail out
    // before touching ref again — no StateError, no activation attempt.
    createCompleter.complete(
      const Routine(
        id: 'gen-id',
        name: 'TEST BORRAR',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    verifyNever(() => userRepo.update(any(), any()));
  });

  testWidgets(
      'activation write failure does not break the create flow (best-effort)',
      (tester) async {
    when(() => userRepo.update(any(), any())).thenThrow(Exception('offline'));

    await _pumpEditor(
      tester,
      overrides: _overrides(repo: repo, userRepo: userRepo),
    );
    await _warmProfile(tester);

    await _fillAndSubmit(tester);

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    // No unhandled exception — the guard swallowed the failed activation.
    expect(tester.takeException(), isNull);
  });
}
