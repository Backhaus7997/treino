import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/domain/parsed_plan.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A matched item whose weight is a whole number (60.0) — mirrors the Excel
/// template that ships integer weights parsed to doubles.
ParsedPlan _planWithWholeWeight() => const ParsedPlan(
      name: 'Test Plan',
      daysPerWeek: 1,
      durationWeeks: 4,
      level: ExperienceLevel.intermediate,
      days: [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Sentadilla',
              exerciseId: 'ex-1',
              exerciseName: 'Sentadilla',
              muscleGroup: 'Legs',
              sets: 4,
              repsMin: 8,
              repsMax: 10,
              restSec: 90,
              weightKg: 60.0,
            ),
          ],
        ),
      ],
      unmatched: [],
    );

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: child),
      ),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('Plan preview weight formatting', () {
    testWidgets('whole-number weight renders without a trailing .0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            parsedPlanProvider.overrideWith((ref) => _planWithWholeWeight()),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith((ref) => Future.value(const [])),
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Subtitle should read "... · 60 kg", never "60.0 kg".
      expect(find.textContaining('60 kg'), findsOneWidget);
      expect(find.textContaining('60.0 kg'), findsNothing);
    });
  });
}
