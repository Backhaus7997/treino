// Tests for MiPlanSection widget — SCENARIO-444..451
// REQ-COACH-PLANS-013..018

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/coach_strings.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/widgets/mi_plan_section.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:mocktail/mocktail.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Routine _makePlan({
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

UserPublicProfile _makeProfile(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ── Test helper ───────────────────────────────────────────────────────────────

Future<void> _pumpMiPlanSection(
  WidgetTester tester, {
  required List<Override> overrides,
  List<GoRoute> extraRoutes = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/workout',
    routes: [
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: MiPlanSection()),
        ),
        routes: [
          GoRoute(
            path: 'routine/:routineId',
            builder: (_, __) =>
                const Scaffold(body: Center(child: Text('Detalles'))),
          ),
        ],
      ),
      ...extraRoutes,
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('MiPlanSection', () {
    testWidgets('SCENARIO-444: AsyncLoading → loading indicator visible',
        (tester) async {
      final completer = Completer<List<Routine>>();

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) => completer.future,
          ),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      );

      // pump once to trigger loading state
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // complete the future so the test disposes cleanly
      completer.complete([]);
      await tester.pumpAndSettle();
    });

    testWidgets('SCENARIO-445: AsyncError → error text visible',
        (tester) async {
      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => throw Exception('network error'),
          ),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.miPlanError), findsOneWidget);
      expect(find.byKey(const Key('mi_plan_card')), findsNothing);
    });

    testWidgets('SCENARIO-446: empty list → empty state text visible',
        (tester) async {
      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1').overrideWith((ref) async => []),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.miPlanEmpty), findsOneWidget);
      expect(find.byKey(const Key('mi_plan_card')), findsNothing);
    });

    testWidgets('SCENARIO-447: single plan shows name and trainer displayName',
        (tester) async {
      final plan = _makePlan();

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [plan]),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas Pérez')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('Plan Fuerza'), findsOneWidget);
      expect(find.text('Lucas Pérez'), findsOneWidget);
    });

    testWidgets('SCENARIO-448: tapping plan card navigates to routine detail',
        (tester) async {
      final plan = _makePlan(id: 'routine-42');

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [plan]),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('mi_plan_card')));
      await tester.pumpAndSettle();

      expect(find.text('Detalles'), findsOneWidget);
    });

    testWidgets('SCENARIO-449: multiple plans show all cards in order',
        (tester) async {
      final planNew = _makePlan(id: 'plan-new', name: 'Plan Nuevo');
      final planOld = _makePlan(id: 'plan-old', name: 'Plan Viejo');

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [planNew, planOld]),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('Plan Nuevo'), findsOneWidget);
      expect(find.text('Plan Viejo'), findsOneWidget);
      expect(find.byKey(const Key('mi_plan_card')), findsNWidgets(2));
    });

    testWidgets(
        'SCENARIO-450: badge "Plan finalizado" when link terminated and trainer matches',
        (tester) async {
      final plan = _makePlan();
      final link = _makeLink(status: TrainerLinkStatus.terminated);

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [plan]),
          currentAthleteLinkProvider.overrideWith((ref) async => link),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.miPlanFinalizado), findsOneWidget);
      // Card should still be tappable
      expect(find.byKey(const Key('mi_plan_card')), findsOneWidget);
    });

    testWidgets(
        'current badge: single plan does NOT show "Actual" chip (redundant)',
        (tester) async {
      final plan = _makePlan();

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [plan]),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mi_plan_current_chip')), findsNothing);
    });

    testWidgets(
        'current badge: multiple plans → only the FIRST shows the "Actual" chip',
        (tester) async {
      final planNew = _makePlan(id: 'plan-new', name: 'Plan Nuevo');
      final planOld = _makePlan(id: 'plan-old', name: 'Plan Viejo');

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          // listAssignedTo returns newest first; the order here mirrors that.
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [planNew, planOld]),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Exactly one "Actual" chip, sitting next to the newest plan.
      expect(find.byKey(const Key('mi_plan_current_chip')), findsOneWidget);
      expect(find.text(CoachStrings.miPlanCurrent.toUpperCase()), findsOneWidget);
    });

    testWidgets('SCENARIO-451: no badge when link is active', (tester) async {
      final plan = _makePlan();
      final link = _makeLink(status: TrainerLinkStatus.active);

      await _pumpMiPlanSection(
        tester,
        overrides: [
          authStateChangesProvider
              .overrideWith((ref) => Stream.value(_userWithUid('athlete-1'))),
          assignedRoutinesProvider('athlete-1')
              .overrideWith((ref) async => [plan]),
          currentAthleteLinkProvider.overrideWith((ref) async => link),
          userPublicProfileProvider('trainer-1').overrideWith(
            (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas')),
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text(CoachStrings.miPlanFinalizado), findsNothing);
    });
  });
}
