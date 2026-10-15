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
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'periodized_draft_fixtures.dart';
import 'package:treino/features/profile/application/user_providers.dart';
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

/// Un plan cuyo DÍA 1 tiene DOS renglones sin match con el mismo nombre.
PeriodizedImportDraft _planWithDuplicateUnmatched() => draftOf([
      [1, 'Sentadilla X', null, ...sameWeeks('3x10')],
      [2, 'Sentadilla X', null, ...sameWeeks('4x6')],
    ]);

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
  useTallSurface();

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('manual pick resolves only the targeted row, not every same-named row',
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
            periodizedImportProvider.overrideWith((ref) => plan),
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
      expect(find.text('Vincular con la biblioteca'), findsNWidgets(2));

      // Resolve only the FIRST row.
      await tester.tap(find.text('Vincular con la biblioteca').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // BUG: keying on rowName resolved BOTH rows (findsNothing).
      // FIXED: exactly one row remains unmatched.
      expect(find.text('sin match'), findsOneWidget);
      expect(find.text('Vincular con la biblioteca'), findsOneWidget);
    });
  });
}
