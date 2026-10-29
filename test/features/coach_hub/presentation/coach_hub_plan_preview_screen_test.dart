import 'dart:async';

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
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'periodized_draft_fixtures.dart';

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

/// Un renglón sin match en el DÍA 1.
PeriodizedImportDraft _planWithUnmatched() => draftOf([
      [1, 'Sentadilla', null, ...sameWeeks('3x10')],
    ]);

PeriodizedImportDraft _planWithSuggestion() => draftOf(
      [
        [1, 'Sentadilla búlgara', null, ...sameWeeks('3x10')],
      ],
      suggestions: {
        'Sentadilla búlgara': MatcherExercise(
          id: 'squat-bar',
          name: 'Sentadilla con barra',
          muscleGroup: 'Legs',
        ),
      },
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
        // Las acciones de la vista previa salen de AppL10n: sin locale el
        // test las vería en inglés.
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  useTallSurface();

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  // ── T-CXP-029 RED ─────────────────────────────────────────────────────────

  group('SCENARIO-744: cloudFunctionsProvider is overridable in tests', () {
    test('cloudFunctionsProvider can be overridden with a mock', () {
      final mockFunctions = MockFirebaseFunctions();
      final container = ProviderContainer(
        overrides: [
          cloudFunctionsProvider.overrideWithValue(mockFunctions),
        ],
      );
      addTearDown(container.dispose);

      final functions = container.read(cloudFunctionsProvider);
      expect(functions, same(mockFunctions));
    });
  });

  // ── T-CXP-031 RED ────────────────────────────────────────────────────────

  group(
      'SCENARIO-745: _pickExerciseFor resuelve sin llamar a addAlias (el alias '
      'se registra al asignar)', () {
    testWidgets(
        'after manual mapping, addAlias is NOT called yet: it waits for '
        'ASIGNAR PLAN', (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();
      final mockResult = MockHttpsCallableResult();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) async => mockResult);

      final plan = _planWithUnmatched();
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
            // _AthletePicker watches the real-time stream provider
            // (ADR-CHLM-03); override it so the picker reaches its data
            // branch instead of hanging on the loading spinner.
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Vincular con la biblioteca" to trigger manual mapping
      await tester.tap(find.text('Vincular con la biblioteca'));
      await tester.pumpAndSettle();

      // Pick the exercise from the bottom sheet
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // El alias ya no se registra al vincular: se registra al asignar, con
      // la asignación final (plan_import_preview_controller_test.dart).
      verifyNever(() => mockCallable.call(any<Map<String, dynamic>>()));

      // Verify local state preserved (item is no longer unmatched)
      expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
          findsNothing);
    });
  });

  group('SCENARIO-746: _pickExerciseFor does not block on hanging CF', () {
    testWidgets('UI returns to idle immediately even when CF never completes',
        (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      // Never-completing future — simulates CF hang
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) => Completer<HttpsCallableResult<dynamic>>().future);

      final plan = _planWithUnmatched();
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
            // _AthletePicker watches the real-time stream provider
            // (ADR-CHLM-03); override it so the picker reaches its data
            // branch instead of hanging on the loading spinner.
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vincular con la biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // UI must be idle — no blocking spinner from _pickExerciseFor itself
      // The assign button is still enabled (not saving)
      expect(find.text('ASIGNAR PLAN'), findsOneWidget);
    });
  });

  // ── T-CXP-032 RED ────────────────────────────────────────────────────────

  group('SCENARIO-747: _addAlias swallows CF exceptions silently', () {
    testWidgets(
        'CF throws FirebaseFunctionsException — no error shown, mapping state preserved',
        (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();

      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>())).thenThrow(
        FirebaseFunctionsException(
          message: 'permission-denied',
          code: 'permission-denied',
        ),
      );

      final plan = _planWithUnmatched();
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
            // _AthletePicker watches the real-time stream provider
            // (ADR-CHLM-03); override it so the picker reaches its data
            // branch instead of hanging on the loading spinner.
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vincular con la biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla').last);
      await tester.pumpAndSettle();

      // No error text shown to user
      expect(find.text('permission-denied'), findsNothing);
      // No exception propagated — widget tree still intact
      expect(find.byType(CoachHubPlanPreviewScreen), findsOneWidget);
      // Local mapping state preserved (unmatched badge gone)
      expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
          findsNothing);
    });
  });

  group(
      'SCENARIO-STALE — _AthletePicker sostiene el roster ante error '
      'transitorio (pulido-post-revision)', () {
    // Regression: `_AthletePicker.build` despachaba con
    // `linksAsync.when(loading:, error:, data:)` — dispatch por SUBTIPO
    // runtime, ignora `hasValue`. `trainerLinksStreamProvider` es un
    // StreamProvider en vivo — Riverpod 2.5+ preserva el valor previo dentro
    // de un AsyncError subsiguiente (copyWithPrevious/"seamless"), así que
    // un error transitorio (con alumnos ya cargados) tapaba el picker con
    // "No pudimos cargar tus alumnos.".
    testWidgets(
        'los alumnos ya cargados no desaparecen tras un error transitorio '
        'del stream (stale-while-refresh)', (tester) async {
      var listens = 0;
      final controller = StreamController<List<TrainerLink>>.broadcast(
        onListen: () => listens++,
      );
      addTearDown(controller.close);

      final plan = _planWithUnmatched();

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            periodizedImportProvider.overrideWith((ref) => plan),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith((ref) => Future.value(const [])),
            trainerLinksStreamProvider.overrideWith((ref) => controller.stream),
          ],
        ),
      );
      await tester.pump();

      controller.add(const <TrainerLink>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No pudimos cargar tus alumnos.'), findsNothing);
      expect(
        find.text(
          'No tenés alumnos activos para asignarles este plan. '
          'Esperá que un atleta acepte tu vínculo y volvé a importar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Datos desactualizados'), findsNothing);

      controller.addError(Exception('transient stream hiccup'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('No pudimos cargar tus alumnos.'),
        findsNothing,
        reason: 'un error transitorio con alumnos ya cargados no debe tapar '
            'el picker con el mensaje de error',
      );
      expect(find.text('Datos desactualizados'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(listens, 2, reason: 'Reintentar tiene que re-suscribir el stream');

      controller.add(const <TrainerLink>[]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Datos desactualizados'), findsNothing);
    });
  });

  group('sugerencias de match', () {
    testWidgets(
        'muestra texto original y sugerencia; confirmar resuelve sin alias '
        '(se registra al asignar)', (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();
      final mockResult = MockHttpsCallableResult();
      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) async => mockResult);

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            periodizedImportProvider
                .overrideWith((ref) => _planWithSuggestion()),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sentadilla búlgara'), findsOneWidget);
      expect(find.bySemanticsLabel('Sugerencia: Sentadilla con barra'),
          findsOneWidget);
      expect(find.bySemanticsLabel('sugerencia por confirmar'), findsOneWidget);

      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verifyNever(() => mockCallable.call(any<Map<String, dynamic>>()));
      expect(find.bySemanticsLabel('sugerencia por confirmar'), findsNothing);
      expect(find.text('Sentadilla con barra'), findsOneWidget);
    });

    testWidgets(
        'cambiar abre el picker y resuelve con la elección, sin alias '
        'todavía', (tester) async {
      final mockFunctions = MockFirebaseFunctions();
      final mockCallable = MockHttpsCallable();
      final mockResult = MockHttpsCallableResult();
      when(() => mockFunctions.httpsCallable('addAlias'))
          .thenReturn(mockCallable);
      when(() => mockCallable.call(any<Map<String, dynamic>>()))
          .thenAnswer((_) async => mockResult);

      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            cloudFunctionsProvider.overrideWithValue(mockFunctions),
            periodizedImportProvider
                .overrideWith((ref) => _planWithSuggestion()),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            exercisesProvider.overrideWith(
              (ref) => Future.value([
                _exercise(
                  id: 'bulgarian-assisted',
                  name: 'Sentadilla búlgara asistida',
                ),
              ]),
            ),
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla búlgara asistida'));
      await tester.pumpAndSettle();

      verifyNever(() => mockCallable.call(any<Map<String, dynamic>>()));
      expect(find.text('Sentadilla búlgara asistida'), findsOneWidget);
      expect(find.bySemanticsLabel('sugerencia por confirmar'), findsNothing);
    });

    testWidgets('una sugerencia pendiente bloquea la asignación',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const CoachHubPlanPreviewScreen(),
          overrides: [
            periodizedImportProvider
                .overrideWith((ref) => _planWithSuggestion()),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_trainerProfile()),
            ),
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ASIGNAR PLAN'));
      await tester.pump();

      expect(
        find.text(
          'Hay sugerencias pendientes. Confirmalas o cambialas antes de '
          'continuar.',
        ),
        findsOneWidget,
      );
    });
  });
}
