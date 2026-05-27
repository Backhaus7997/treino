import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/presentation/profile_routines_screen.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';

Routine _routine({required String id, required String name}) {
  return Routine(
    id: id,
    name: name,
    split: 'Full Body',
    level: ExperienceLevel.beginner,
    days: const [],
    source: RoutineSource.trainerAssigned,
    assignedBy: 'trainer-uid',
    assignedTo: _uid,
    visibility: RoutineVisibility.private,
  );
}

Widget _buildScreen({
  required List<Override> overrides,
}) {
  final router = GoRouter(
    initialLocation: '/profile/routines',
    routes: [
      GoRoute(
        path: '/profile/routines',
        builder: (_, __) => const Scaffold(
          body: ProfileRoutinesScreen(),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-520, SCENARIO-521
// ---------------------------------------------------------------------------

void main() {
  group('ProfileRoutinesScreen', () {
    final mockUser = MockUser();

    // Loading state
    testWidgets('shows CircularProgressIndicator during loading',
        (tester) async {
      // Use a Completer that never completes to hold loading state without
      // creating a pending timer (which would fail the test teardown).
      final completer = Completer<List<Routine>>();

      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(mockUser),
            ),
            assignedRoutinesProvider(_uid).overrideWith(
              (_) => completer.future,
            ),
          ],
        ),
      );
      await tester.pump(); // One frame — loading state only.

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the future before test ends to avoid resource leak warnings.
      completer.complete([]);
    });

    // SCENARIO-521: empty state
    testWidgets('SCENARIO-521: shows empty state when no routines are assigned',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(mockUser),
            ),
            assignedRoutinesProvider(_uid).overrideWith(
              (_) async => [],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Tu PF todavía no te asignó ninguna rutina'),
        findsOneWidget,
      );
    });

    // SCENARIO-520: data state renders RoutineCard per item
    testWidgets('SCENARIO-520: renders one RoutineCard per assigned routine',
        (tester) async {
      final routines = [
        _routine(id: 'r1', name: 'Plan Hipertrofia'),
        _routine(id: 'r2', name: 'Plan Fuerza'),
      ];

      await tester.pumpWidget(
        _buildScreen(
          overrides: [
            authStateChangesProvider.overrideWith(
              (_) => Stream.value(mockUser),
            ),
            assignedRoutinesProvider(_uid).overrideWith(
              (_) async => routines,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN HIPERTROFIA'), findsOneWidget);
      expect(find.text('PLAN FUERZA'), findsOneWidget);
    });
  });
}
