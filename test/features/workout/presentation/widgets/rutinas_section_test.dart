// Widget tests for RutinasSection — unified routines list (workout-area
// redesign slice 1, 2026-07-27). Replaces mi_plan_section_test.dart +
// mis_rutinas_section_test.dart.
//
// Contract under test:
//   * ONE list: trainer-assigned plans pinned on TOP (with "DE TU COACH"
//     chip), then self-created routines.
//   * ACTIVA chip by match with UserProfile.activeRoutineId — always, even
//     with a single routine.
//   * "Marcar como activa" on non-active cards when the unified list has 2+
//     routines — coach plans included. No unmark action (lazy adoption keeps
//     exactly one active routine).
//   * Edit/archive remain exclusive to self-created cards.
//   * Create CTA + cap(10) count SELF-CREATED routines only.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/widgets/rutinas_section.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

// ── Fixtures ───────────────────────────────────────────────────────────────────

class _MockUser extends Mock implements User {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockUserRepository extends Mock implements UserRepository {}

UserProfile _profile({String uid = 'athlete-1', String? activeRoutineId}) =>
    UserProfile(
      uid: uid,
      email: '$uid@treino.app',
      displayName: 'A1',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Routine _makeUserRoutine({
  String id = 'r1',
  String name = 'Mi Rutina Full Body',
  String createdBy = 'athlete-1',
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
      createdBy: createdBy,
      status: status,
    );

Routine _makeCoachPlan({
  String id = 'plan-1',
  String name = 'Plan Fuerza',
  String assignedBy = 'trainer-1',
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: assignedBy,
      assignedTo: 'athlete-1',
      visibility: RoutineVisibility.private,
    );

TrainerLink _makeLink({
  TrainerLinkStatus status = TrainerLinkStatus.active,
  String trainerId = 'trainer-1',
}) =>
    TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: status,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

List<Routine> _make10Routines() => List.generate(
      10,
      (i) => _makeUserRoutine(id: 'r$i', name: 'Rutina $i'),
    );

// ── Test helper ────────────────────────────────────────────────────────────────

/// Pumps RutinasSection with the full unified stack overridden. The user
/// repository is ALWAYS mocked: unifiedRoutinesProvider's lazy adoption
/// writes `activeRoutineId` whenever the profile resolves without one.
Future<_Mocks> _pumpSection(
  WidgetTester tester, {
  List<Routine> assigned = const [],
  List<Routine> own = const [],
  String? activeRoutineId,
  TrainerLink? link,
  List<Override> extraOverrides = const [],
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final userRepo = _MockUserRepository();
  when(() => userRepo.update(any(), any())).thenAnswer((_) async {});
  final routineRepo = _MockRoutineRepository();

  final router = GoRouter(
    initialLocation: '/workout',
    routes: [
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: RutinasSection()),
        ),
        routes: [
          GoRoute(
            path: 'my-routine-editor',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Editor'))),
          ),
          GoRoute(
            path: 'routine/:routineId',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Detalles'))),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
        assignedRoutinesProvider('athlete-1')
            .overrideWith((ref) async => assigned),
        userCreatedRoutinesProvider('athlete-1')
            .overrideWith((ref) => Stream.value(own)),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_profile(activeRoutineId: activeRoutineId)),
        ),
        currentAthleteLinkProvider.overrideWith((ref) async => link),
        userPublicProfileProvider('trainer-1').overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(
              uid: 'trainer-1',
              displayName: 'Coach Vic',
              displayNameLowercase: 'coach vic',
            ),
          ),
        ),
        userRepositoryProvider.overrideWithValue(userRepo),
        routineRepositoryProvider.overrideWithValue(routineRepo),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  return (userRepo: userRepo, routineRepo: routineRepo);
}

typedef _Mocks = ({
  _MockUserRepository userRepo,
  _MockRoutineRepository routineRepo,
});

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Needed for mocktail.any() on Map<String, Object?> args in
    // UserRepository.update.
    registerFallbackValue(<String, Object?>{});
  });

  group('RutinasSection — unified list', () {
    testWidgets(
        'accessibility text scale stacks header and card status without overflow',
        (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'coach-plan')],
        own: [_makeUserRoutine(id: 'own-plan', name: 'Rutina personal larga')],
        activeRoutineId: 'coach-plan',
        textScaler: const TextScaler.linear(3.2),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('CREAR RUTINA')).dy,
        greaterThan(tester.getTopLeft(find.text('MIS RUTINAS')).dy),
      );
      expect(
        tester.getTopLeft(find.text('DE TU COACH')).dy,
        greaterThan(
          tester.getTopLeft(find.text('Plan Fuerza')).dy,
        ),
      );
      expect(find.text('CREAR RUTINA').hitTestable(), findsOneWidget);
    });

    testWidgets('empty state renders motivational message + CTA enabled',
        (tester) async {
      await _pumpSection(tester);
      await tester.pumpAndSettle();

      expect(find.text('MIS RUTINAS'), findsOneWidget);
      expect(
        find.textContaining('Todavía no creaste ninguna rutina'),
        findsOneWidget,
      );
      expect(find.text('CREAR RUTINA'), findsOneWidget);
    });

    testWidgets(
        'coach plan is PINNED above self-created routines and carries the '
        'DE TU COACH chip', (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1', name: 'Plan Fuerza')],
        own: [
          _makeUserRoutine(id: 'r1', name: 'Rutina A'),
          _makeUserRoutine(id: 'r2', name: 'Rutina B'),
        ],
        activeRoutineId: 'plan-1',
      );
      await tester.pumpAndSettle();

      // All three cards render.
      expect(find.byKey(const Key('routine_card_plan-1')), findsOneWidget);
      expect(find.byKey(const Key('routine_card_r1')), findsOneWidget);
      expect(find.byKey(const Key('routine_card_r2')), findsOneWidget);

      // Coach plan on top.
      final coachY =
          tester.getTopLeft(find.byKey(const Key('routine_card_plan-1'))).dy;
      final ownAY =
          tester.getTopLeft(find.byKey(const Key('routine_card_r1'))).dy;
      final ownBY =
          tester.getTopLeft(find.byKey(const Key('routine_card_r2'))).dy;
      expect(coachY, lessThan(ownAY));
      expect(ownAY, lessThan(ownBY));

      // Coach chip only on the coach card.
      expect(
        find.byKey(const Key('routine_coach_chip_plan-1')),
        findsOneWidget,
      );
      expect(find.text('DE TU COACH'), findsOneWidget);
      expect(find.byKey(const Key('routine_coach_chip_r1')), findsNothing);

      // Trainer display name resolves on the coach card.
      expect(find.text('Coach Vic'), findsOneWidget);
    });

    testWidgets(
        'ACTIVA chip renders by activeRoutineId match even with a SINGLE '
        'routine (new contract — no >1 gate)', (tester) async {
      await _pumpSection(
        tester,
        own: [_makeUserRoutine(id: 'r-only', name: 'Only Routine')],
        activeRoutineId: 'r-only',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('routine_active_chip_r-only')),
        findsOneWidget,
      );
      expect(find.text('ACTIVA'), findsOneWidget);
    });

    testWidgets(
        'ACTIVA chip can sit on the coach plan (coach routines are '
        'activatable too)', (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        own: [_makeUserRoutine(id: 'r1')],
        activeRoutineId: 'plan-1',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('routine_active_chip_plan-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('routine_active_chip_r1')), findsNothing);
    });

    testWidgets(
        'single routine → overflow has NO toggle action (nothing to switch '
        'to); own card keeps EDITAR/ELIMINAR', (tester) async {
      await _pumpSection(
        tester,
        own: [_makeUserRoutine(id: 'r-only')],
        activeRoutineId: 'r-only',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r-only')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('routine_card_toggle_active_r-only')),
        findsNothing,
      );
      expect(find.text('EDITAR'), findsOneWidget);
      expect(find.text('ELIMINAR'), findsOneWidget);
    });

    testWidgets(
        '2+ routines → non-active cards offer MARCAR COMO ACTIVA; the active '
        'card offers no unmark (mark-only contract)', (tester) async {
      await _pumpSection(
        tester,
        own: [
          _makeUserRoutine(id: 'r1', name: 'Rutina A'),
          _makeUserRoutine(id: 'r2', name: 'Rutina B'),
        ],
        activeRoutineId: 'r2',
      );
      await tester.pumpAndSettle();

      // Non-active card → MARCAR available.
      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      expect(find.text('MARCAR COMO ACTIVA'), findsOneWidget);
      expect(find.text('DESMARCAR COMO ACTIVA'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Active card → no toggle at all, no unmark.
      await tester.tap(find.byKey(const Key('routine_card_more_r2')));
      await tester.pumpAndSettle();
      expect(find.text('MARCAR COMO ACTIVA'), findsNothing);
      expect(find.text('DESMARCAR COMO ACTIVA'), findsNothing);
    });

    testWidgets(
        'coach plan (non-active) offers MARCAR COMO ACTIVA and tapping it '
        'writes activeRoutineId = plan id', (tester) async {
      final mocks = await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        own: [_makeUserRoutine(id: 'r1')],
        activeRoutineId: 'r1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_plan-1')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('routine_card_toggle_active_plan-1')));
      await tester.pumpAndSettle();

      verify(
        () => mocks.userRepo.update('athlete-1', {'activeRoutineId': 'plan-1'}),
      ).called(1);
      // Coach cards never expose edit/archive.
      expect(find.text('EDITAR'), findsNothing);
      expect(find.text('ELIMINAR'), findsNothing);
    });

    testWidgets(
        'active coach plan renders NO overflow menu at all (toggle is its '
        'only possible action)', (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        own: [_makeUserRoutine(id: 'r1')],
        activeRoutineId: 'plan-1',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('routine_card_more_plan-1')),
        findsNothing,
      );
    });

    testWidgets(
        'tap MARCAR COMO ACTIVA on own card calls UserRepository.update with '
        'that routine id', (tester) async {
      final mocks = await _pumpSection(
        tester,
        own: [
          _makeUserRoutine(id: 'r1', name: 'Rutina A'),
          _makeUserRoutine(id: 'r2', name: 'Rutina B'),
        ],
        activeRoutineId: 'r2',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MARCAR COMO ACTIVA'));
      await tester.pumpAndSettle();

      verify(
        () => mocks.userRepo.update('athlete-1', {'activeRoutineId': 'r1'}),
      ).called(1);
    });

    testWidgets(
        'lazy adoption: profile without activeRoutineId + non-empty list → '
        'head of the list (coach plan) is adopted once', (tester) async {
      final mocks = await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        own: [_makeUserRoutine(id: 'r1')],
      );
      await tester.pumpAndSettle();

      verify(
        () => mocks.userRepo.update('athlete-1', {'activeRoutineId': 'plan-1'}),
      ).called(1);
    });

    testWidgets(
        'cap: 10 self-created routines → CTA hidden + inline hint '
        '(coach plans do not count)', (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        own: _make10Routines(),
        activeRoutineId: 'plan-1',
      );
      await tester.pumpAndSettle();

      expect(find.text('CREAR RUTINA'), findsNothing);
      expect(find.textContaining('máximo'), findsOneWidget);
    });

    testWidgets('loading state renders a spinner', (tester) async {
      final completer = Completer<List<Routine>>();
      await _pumpSection(
        tester,
        extraOverrides: [
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Resolve to avoid resource leak warnings.
      completer.complete(const []);
    });

    testWidgets(
        'error state renders message + Reintentar, and retry re-fetches the '
        'unified list', (tester) async {
      var attempts = 0;
      await _pumpSection(
        tester,
        activeRoutineId: 'plan-1',
        extraOverrides: [
          assignedRoutinesProvider('athlete-1').overrideWith((ref) async {
            attempts++;
            if (attempts == 1) throw Exception('backend down');
            return [_makeCoachPlan(id: 'plan-1', name: 'Plan Fuerza')];
          }),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('No pudimos cargar tus rutinas.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Plan Fuerza'), findsOneWidget);
      expect(find.text('No pudimos cargar tus rutinas.'), findsNothing);
    });

    testWidgets('overflow ELIMINAR → CANCELAR → repo.archive NOT called',
        (tester) async {
      final mocks = await _pumpSection(
        tester,
        own: [_makeUserRoutine(id: 'r1')],
        activeRoutineId: 'r1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar rutina'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'CANCELAR'));
      await tester.pumpAndSettle();

      verifyNever(() => mocks.routineRepo.archive(any()));
    });

    testWidgets('overflow ELIMINAR → confirm → repo.archive called',
        (tester) async {
      final mocks = await _pumpSection(
        tester,
        own: [_makeUserRoutine(id: 'r1')],
        activeRoutineId: 'r1',
      );
      when(() => mocks.routineRepo.archive(any())).thenAnswer((_) async {});
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_more_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminar rutina'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'ELIMINAR'));
      await tester.pumpAndSettle();

      verify(() => mocks.routineRepo.archive('r1')).called(1);
    });

    testWidgets('tap on a card navigates to the routine detail screen',
        (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        activeRoutineId: 'plan-1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_plan-1')));
      await tester.pumpAndSettle();

      expect(find.text('Detalles'), findsOneWidget);
    });

    testWidgets(
        'tap on the SECOND self-created card (both non-active) navigates too '
        '— QA #REGR: reported dead on real device/simulator, unreproduced '
        'here', (tester) async {
      await _pumpSection(
        tester,
        own: [
          _makeUserRoutine(id: 'r1', name: 'Rutina A'),
          _makeUserRoutine(id: 'r2', name: 'Rutina B'),
        ],
        activeRoutineId: 'r1',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_card_r2')));
      await tester.pumpAndSettle();

      expect(find.text('Detalles'), findsOneWidget);
    });

    testWidgets(
        'terminated trainer link → coach card shows "Plan finalizado" chip',
        (tester) async {
      await _pumpSection(
        tester,
        assigned: [_makeCoachPlan(id: 'plan-1')],
        activeRoutineId: 'plan-1',
        link: _makeLink(status: TrainerLinkStatus.terminated),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan finalizado'), findsOneWidget);
    });

    testWidgets('tap CTA navigates to /workout/my-routine-editor',
        (tester) async {
      await _pumpSection(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('CREAR RUTINA'));
      await tester.pumpAndSettle();

      expect(find.text('Editor'), findsOneWidget);
    });
  });
}
