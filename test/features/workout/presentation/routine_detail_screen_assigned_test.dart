// Tests for RoutineDetailScreen _AssignedByChip — SCENARIO-452, SCENARIO-453
// REQ-COACH-PLANS-019
// TDD RED: _AssignedByChip modification not yet implemented → tests fail.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/coach/presentation/coach_strings.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

RoutineSlot _makeSlot() => const RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Bench Press',
      muscleGroup: 'chest',
      targetSets: 4,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

RoutineDay _makeDay() => RoutineDay(
      dayNumber: 1,
      name: 'Push',
      slots: [_makeSlot()],
      estimatedMinutes: 45,
    );

Routine _makeAssignedRoutine({
  String id = 'r-1',
  String assignedBy = 'trainer-1',
}) =>
    Routine(
      id: id,
      name: 'Plan Fuerza',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: [_makeDay()],
      source: RoutineSource.trainerAssigned,
      assignedBy: assignedBy,
      assignedTo: 'athlete-1',
      visibility: RoutineVisibility.private,
    );

Routine _makeSystemRoutine({String id = 'r-2'}) => Routine(
      id: id,
      name: 'PPL Beginner',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: [_makeDay()],
      source: RoutineSource.system,
    );

UserPublicProfile _makeProfile(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ── Pump helper ───────────────────────────────────────────────────────────────

Widget _wrapWithOverrides(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('RoutineDetailScreen — _AssignedByChip', () {
    testWidgets(
        'SCENARIO-452: trainer-assigned routine shows "Asignado por" chip',
        (tester) async {
      final routine = _makeAssignedRoutine();

      await tester.pumpWidget(
        _wrapWithOverrides(
          const RoutineDetailScreen(routineId: 'r-1'),
          [
            routineByIdProvider('r-1').overrideWith(
              (ref) async => routine,
            ),
            userPublicProfileProvider('trainer-1').overrideWith(
              (ref) => Stream.value(_makeProfile('trainer-1', 'Lucas Pérez')),
            ),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.text('${CoachStrings.assignedByPrefix}Lucas Pérez'),
        findsOneWidget,
      );
    });

    testWidgets(
        'SCENARIO-453: system routine does NOT show "Asignado por" chip',
        (tester) async {
      final routine = _makeSystemRoutine();

      await tester.pumpWidget(
        _wrapWithOverrides(
          const RoutineDetailScreen(routineId: 'r-2'),
          [
            routineByIdProvider('r-2').overrideWith(
              (ref) async => routine,
            ),
          ],
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.textContaining(CoachStrings.assignedByPrefix),
        findsNothing,
      );
    });
  });
}
