import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/domain/parsed_plan.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';

// ─── Mocks ──────────────────────────────────────────────────────────────────

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock
    implements HttpsCallableResult<dynamic> {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

UserProfile _trainerProfile() => UserProfile(
      uid: 'trainer-1',
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// A ParsedPlan whose day 1 has TWO identically-named unmatched rows.
ParsedPlan _planWithDuplicateUnmatched() => const ParsedPlan(
      name: 'Test Plan',
      daysPerWeek: 1,
      durationWeeks: 4,
      level: ExperienceLevel.intermediate,
      days: [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Sentadilla X',
              exerciseId: null,
              exerciseName: 'Sentadilla X',
              muscleGroup: null,
              sets: 3,
              repsMin: 10,
              repsMax: 12,
            ),
            ParsedPlanItem(
              rowName: 'Sentadilla X',
              exerciseId: null,
              exerciseName: 'Sentadilla X',
              muscleGroup: null,
              sets: 4,
              repsMin: 6,
              repsMax: 8,
            ),
          ],
        ),
      ],
      unmatched: [
        ParsedPlanUnmatched(dayNumber: 1, rowName: 'Sentadilla X'),
        ParsedPlanUnmatched(dayNumber: 1, rowName: 'Sentadilla X'),
      ],
    );

Exercise _exercise({String id = 'ex-1', String name = 'Sentadilla'}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: 'Legs',
      category: 'compound',
      aliases: const [],
    );

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group(
      'manual pick resolves only the targeted row, not every same-named row',
      () {
    testWidgets(
        'picking for the first of two identical unmatched rows leaves the '
        'second still unmatched', (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();
      final mockResult = MockHttpsCallableResult();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) async => mockResult);

      final plan = _planWithDuplicateUnmatched();
      final exercise = _exercise();

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            parsedPlanProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith(
              (ref) => Future.value([exercise]),
            ),
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream<List<TrainerLink>>.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Two identical unmatched rows → two badges, two manual-pick buttons.
      expect(find.text('sin match'), findsNWidgets(2));
      expect(find.text('Asignar manualmente'), findsNWidgets(2));

      // Resolve only the FIRST row.
      await tester.tap(find.text('Asignar manualmente').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // BUG: keying on rowName resolved BOTH rows (findsNothing).
      // FIXED: exactly one row remains unmatched.
      expect(find.text('sin match'), findsOneWidget);
      expect(find.text('Asignar manualmente'), findsOneWidget);
    });
  });
}
