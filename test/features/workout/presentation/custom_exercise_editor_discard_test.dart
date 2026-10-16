// custom_exercise_editor_discard_test.dart — #1502: salir de «Nuevo ejercicio»
// con datos cargados pregunta antes de descartarlos.
//
// Antes, «atrás» tiraba todo sin avisar. El guard es el mismo del editor de
// planes: `PopScope(canPop: !dirty)` + "¿Descartar cambios?". Se prueba por las
// DOS puertas —la flecha de la pantalla y el back del sistema / swipe de iOS—
// y que GUARDAR (un pop programático) no se frene a sí mismo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart'
    show customExerciseVideoCapsProvider, customExerciseVideoCountProvider;
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/presentation/custom_exercise_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockRepo extends Mock implements CustomExerciseRepository {}

const _uid = 'trainer-1';
const _discardTitle = '¿Descartar cambios?';
const _homeText = 'HOME';

CustomExercise _existing() => CustomExercise(
      id: 'ex-1',
      ownerId: _uid,
      name: 'Press banca',
      muscleGroup: 'chest',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Home → push al editor, para que haya a dónde volver y el pop se vea.
Future<void> _pumpEditor(
  WidgetTester tester, {
  required CustomExerciseRepository repo,
  String exerciseId = 'new',
  List<CustomExercise> existing = const [],
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Column(
            children: [
              const Text(_homeText),
              TextButton(
                onPressed: () => context.push('/editor'),
                child: const Text('ABRIR'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/editor',
        builder: (_, __) => Scaffold(
          body: SafeArea(
            child: CustomExerciseEditorScreen(exerciseId: exerciseId),
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_uid),
        customExerciseRepositoryProvider.overrideWithValue(repo),
        customExercisesForTrainerStreamProvider(_uid)
            .overrideWith((ref) => Stream.value(existing)),
        customExerciseQuotaProvider
            .overrideWithValue(const AsyncValue.data((limit: 60, count: 0))),
        customExerciseVideoCountProvider.overrideWith((ref) => Stream.value(0)),
        customExerciseVideoCapsProvider
            .overrideWithValue((maxCount: 50, maxBytes: 100 * 1024 * 1024)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('ABRIR'));
  await _settle(tester);
}

/// `pump()` fijo y no `pumpAndSettle()`: `ExerciseVideoPlayer` puede dejar un
/// Timer vivo en el árbol (gotcha de este repo).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tapBackArrow(WidgetTester tester) async {
  await tester.tap(find.byIcon(TreinoIcon.back));
  await _settle(tester);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_existing());
  });

  group('#1502 — Nuevo ejercicio', () {
    testWidgets('sin datos cargados, atrás sale directo (sin diálogo)',
        (tester) async {
      await _pumpEditor(tester, repo: _MockRepo());
      expect(find.text('NUEVO EJERCICIO'), findsOneWidget);

      await _tapBackArrow(tester);

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });

    testWidgets('con datos cargados, atrás pregunta; Cancelar se queda',
        (tester) async {
      await _pumpEditor(tester, repo: _MockRepo());
      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.pump();

      await _tapBackArrow(tester);

      expect(find.text(_discardTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('discard_changes_cancel')));
      await _settle(tester);

      // Sigue en el editor y NO perdió lo que escribió.
      expect(find.text(_discardTitle), findsNothing);
      expect(find.text('NUEVO EJERCICIO'), findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
    });

    testWidgets('con datos cargados, Descartar sale del editor',
        (tester) async {
      await _pumpEditor(tester, repo: _MockRepo());
      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.pump();

      await _tapBackArrow(tester);
      await tester.tap(find.byKey(const Key('discard_changes_confirm')));
      await _settle(tester);

      expect(find.text(_homeText), findsOneWidget);
      expect(find.text('NUEVO EJERCICIO'), findsNothing);
    });

    testWidgets('el back del sistema / swipe de iOS también pregunta',
        (tester) async {
      await _pumpEditor(tester, repo: _MockRepo());
      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.pump();

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).last,
      );
      await navigator.maybePop();
      await _settle(tester);

      expect(find.text(_discardTitle), findsOneWidget);
      expect(find.text('NUEVO EJERCICIO'), findsOneWidget);
    });

    testWidgets('borrar lo escrito vuelve a dejar salir sin preguntar',
        (tester) async {
      await _pumpEditor(tester, repo: _MockRepo());
      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      await _tapBackArrow(tester);

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });

    testWidgets('GUARDAR con cambios no se frena a sí mismo ni pregunta',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.create(
            trainerId: any(named: 'trainerId'),
            name: any(named: 'name'),
            muscleGroup: any(named: 'muscleGroup'),
            secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
            description: any(named: 'description'),
            videoUrl: any(named: 'videoUrl'),
            equipment: any(named: 'equipment'),
          )).thenAnswer((_) async => _existing());
      await _pumpEditor(tester, repo: repo);
      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.pump();

      await tester.tap(find.text('GUARDAR EJERCICIO'));
      await _settle(tester);

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });
  });

  group('#1502 — Editar ejercicio', () {
    testWidgets('sin tocar nada, atrás sale directo', (tester) async {
      await _pumpEditor(
        tester,
        repo: _MockRepo(),
        exerciseId: 'ex-1',
        existing: [_existing()],
      );
      expect(find.text('EDITAR EJERCICIO'), findsOneWidget);

      await _tapBackArrow(tester);

      expect(find.text(_discardTitle), findsNothing);
      expect(find.text(_homeText), findsOneWidget);
    });

    testWidgets('si cambió el nombre, atrás pregunta', (tester) async {
      await _pumpEditor(
        tester,
        repo: _MockRepo(),
        exerciseId: 'ex-1',
        existing: [_existing()],
      );
      await tester.enterText(find.byType(TextField).first, 'Press inclinado');
      await tester.pump();

      await _tapBackArrow(tester);

      expect(find.text(_discardTitle), findsOneWidget);
    });
  });
}
