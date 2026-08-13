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
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/l10n/app_l10n.dart';

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

/// A ParsedPlan with a single unmatched row so the preview shows one
/// "Asignar manualmente" button that opens the picker sheet under test.
ParsedPlan _planWithOneUnmatched() => const ParsedPlan(
      name: 'Test Plan',
      daysPerWeek: 1,
      durationWeeks: 4,
      level: ExperienceLevel.intermediate,
      days: [
        ParsedPlanDay(
          dayNumber: 1,
          items: [
            ParsedPlanItem(
              rowName: 'Misterioso',
              exerciseId: null,
              exerciseName: 'Misterioso',
              muscleGroup: null,
              sets: 3,
              repsMin: 10,
              repsMax: 12,
            ),
          ],
        ),
      ],
      unmatched: [
        ParsedPlanUnmatched(dayNumber: 1, rowName: 'Misterioso'),
      ],
    );

/// Catalogue exercising the three match dimensions: multi-word names with
/// filler words, accented names, aliases, and an English muscleGroup key
/// ('chest') that no name or alias contains.
List<Exercise> _catalogue() => const [
      Exercise(
        id: 'ex-press-banca',
        name: 'Press de Banca (Barra)',
        muscleGroup: 'chest',
        category: 'compound',
        aliases: ['bench press'],
      ),
      Exercise(
        id: 'ex-press-militar',
        name: 'Press Militar',
        muscleGroup: 'shoulders',
        category: 'compound',
        aliases: [],
      ),
      Exercise(
        id: 'ex-curl-biceps',
        name: 'Curl de Bíceps',
        muscleGroup: 'biceps',
        category: 'isolation',
        aliases: [],
      ),
      Exercise(
        id: 'ex-dominadas',
        name: 'Dominadas',
        muscleGroup: 'back',
        category: 'compound',
        aliases: ['pull up', 'chin up'],
      ),
    ];

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

Future<void> _pumpPreviewAndOpenPicker(WidgetTester tester) async {
  final mockFunctions = MockFirebaseFunctions();
  final mockCallable = MockHttpsCallable();
  final mockResult = MockHttpsCallableResult();

  when(() => mockFunctions.httpsCallable('addAlias')).thenReturn(mockCallable);
  when(() => mockCallable.call(any<Map<String, dynamic>>()))
      .thenAnswer((_) async => mockResult);

  await tester.pumpWidget(
    _wrap(
      const CoachHubPlanPreviewScreen(),
      overrides: [
        cloudFunctionsProvider.overrideWithValue(mockFunctions),
        parsedPlanProvider.overrideWith((ref) => _planWithOneUnmatched()),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_trainerProfile()),
        ),
        exercisesProvider.overrideWith(
          (ref) => Future.value(_catalogue()),
        ),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream<List<TrainerLink>>.value(const []),
        ),
      ],
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Asignar manualmente'));
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('plan preview picker search uses the shared tokenized predicate', () {
    testWidgets('multi-word query matches despite filler words in the name',
        (tester) async {
      await _pumpPreviewAndOpenPicker(tester);
      await _search(tester, 'press banca');

      expect(find.text('Press de Banca (Barra)'), findsOneWidget);
      expect(find.text('Press Militar'), findsNothing);
      expect(find.text('Sin resultados.'), findsNothing);
    });

    testWidgets('accent folding works both ways combined with tokenization',
        (tester) async {
      await _pumpPreviewAndOpenPicker(tester);

      // Accented multi-word query against the accented name: the old code
      // (whole-phrase substring, no fold) matched neither direction.
      await _search(tester, 'curl bíceps');
      expect(find.text('Curl de Bíceps'), findsOneWidget);
      expect(find.text('Dominadas'), findsNothing);

      // Unaccented single-word query still matches the accented name.
      await _search(tester, 'biceps');
      expect(find.text('Curl de Bíceps'), findsOneWidget);
      expect(find.text('Dominadas'), findsNothing);
    });

    testWidgets('query still matches aliases', (tester) async {
      await _pumpPreviewAndOpenPicker(tester);
      await _search(tester, 'pull up');

      expect(find.text('Dominadas'), findsOneWidget);
      expect(find.text('Press de Banca (Barra)'), findsNothing);
    });

    testWidgets(
        'internal muscleGroup key no longer matches — "chest" finds nothing '
        'even though a listed exercise stores muscleGroup: chest',
        (tester) async {
      await _pumpPreviewAndOpenPicker(tester);
      await _search(tester, 'chest');

      expect(find.text('Press de Banca (Barra)'), findsNothing);
      expect(find.text('Sin resultados.'), findsOneWidget);
    });

    testWidgets('clearing the query shows the full catalogue', (tester) async {
      await _pumpPreviewAndOpenPicker(tester);
      await _search(tester, 'chest');
      await _search(tester, '');

      expect(find.text('Press de Banca (Barra)'), findsOneWidget);
      expect(find.text('Press Militar'), findsOneWidget);
      expect(find.text('Curl de Bíceps'), findsOneWidget);
      expect(find.text('Dominadas'), findsOneWidget);
    });
  });
}
