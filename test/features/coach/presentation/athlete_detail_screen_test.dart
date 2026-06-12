// Tests for AthleteDetailScreen — SCENARIO-455, 456
// REQ-COACH-PLANS-020, 021, 022

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

UserPublicProfile _makeProfile(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

Routine _makePlan({
  String id = 'plan-1',
  String name = 'Plan Fuerza',
  String assignedBy = 'trainer-1',
  String assignedTo = 'athlete-1',
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      visibility: RoutineVisibility.private,
    );

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String athleteId,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/$athleteId',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            Scaffold(body: child, bottomNavigationBar: const SizedBox()),
        routes: [
          GoRoute(
            path: '/coach/athlete/:athleteId',
            builder: (context, state) => AthleteDetailScreen(
              athleteId: state.pathParameters['athleteId']!,
            ),
          ),
          GoRoute(
            path: '/workout/routine-editor/:athleteId',
            builder: (_, state) => Scaffold(
              body: Text('RoutineEditor:${state.pathParameters['athleteId']}'),
            ),
          ),
        ],
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
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AthleteDetailScreen', () {
    testWidgets(
        'SCENARIO-455: renders athlete header, empty plans list, and CREAR PLAN CTA',
        (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Athlete name in header (appears in AppBar title and in body header)
      expect(find.text('Martín García'), findsWidgets);
      // Empty state text
      expect(find.text('Todavía no le asignaste planes.'), findsOneWidget);
      // CREAR PLAN button
      expect(find.text('CREAR PLAN'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-455 (triangulate): renders plan cards when trainer has assigned plans',
        (tester) async {
      final myPlan = _makePlan(
        id: 'plan-1',
        name: 'Plan Hipertrofia',
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );
      final otherPlan = _makePlan(
        id: 'plan-2',
        name: 'Plan Otro PF',
        assignedBy: 'trainer-99',
        // should be filtered out
        assignedTo: 'athlete-1',
      );

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => [myPlan, otherPlan],
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Only the plan assigned by the current trainer should be visible
      expect(find.text('Plan Hipertrofia'), findsOneWidget);
      expect(find.text('Plan Otro PF'), findsNothing);
      // No empty state because trainer has plans
      expect(find.text('Todavía no le asignaste planes.'), findsNothing);
    });

    testWidgets(
        'SCENARIO-456: tapping CREAR PLAN navigates to routine-editor route',
        (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('CREAR PLAN'));
      await tester.pumpAndSettle();

      expect(find.text('RoutineEditor:athlete-1'), findsOneWidget);
    });

    testWidgets('Fase B: renderiza botón MENSAJE en el footer', (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsOneWidget);
    });
  });
}
