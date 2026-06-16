import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/domain/parsed_plan.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';

import '../../../helpers/fake_analytics_service.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockRoutineRepository extends Mock implements RoutineRepository {}

class FakeRoutine extends Fake implements Routine {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A fully-matched ParsedPlan (no unmatched items) with an 8-week duration.
ParsedPlan _matchedPlan({required int durationWeeks}) => ParsedPlan(
      name: 'Periodized Plan',
      daysPerWeek: 1,
      durationWeeks: durationWeeks,
      level: ExperienceLevel.intermediate,
      days: const [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Sentadilla',
              exerciseId: 'ex-1',
              exerciseName: 'Sentadilla',
              muscleGroup: 'Legs',
              sets: 3,
              repsMin: 10,
              repsMax: 12,
            ),
          ],
        ),
      ],
      unmatched: const [],
    );

TrainerLink _activeLink() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(FakeRoutine());
  });

  group('Plan duration is propagated to the assigned Routine', () {
    testWidgets(
        'assigning a multi-week plan persists numWeeks == plan.durationWeeks',
        (tester) async {
      final repo = MockRoutineRepository();
      late Routine captured;

      when(() => repo.createAssigned(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as Routine;
        return captured.copyWith(id: 'routine-1');
      });

      final plan = _matchedPlan(durationWeeks: 8);

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            routineRepositoryProvider.overrideWithValue(repo),
            analyticsServiceProvider
                .overrideWithValue(FakeAnalyticsService()),
            parsedPlanProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            linksForTrainerProvider('trainer-1').overrideWith(
              (ref) async => [_activeLink()],
            ),
            userPublicProfileProvider('athlete-1').overrideWith(
              (ref) => Stream<UserPublicProfile?>.value(
                const UserPublicProfile(uid: 'athlete-1'),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select the only active athlete.
      await tester.tap(find.text('Atleta'));
      await tester.pumpAndSettle();

      // Assign the plan.
      await tester.tap(find.text('ASIGNAR PLAN'));
      await tester.pumpAndSettle();

      verify(() => repo.createAssigned(any())).called(1);
      expect(captured.numWeeks, 8);
    });
  });
}
