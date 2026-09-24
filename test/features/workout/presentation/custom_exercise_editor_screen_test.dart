// custom_exercise_editor_screen_test.dart — el rebote del servidor
// (docs/limite-ejercicios-pf.md PR3, "El rebote del servidor").
//
// Un `permission-denied` en el CREATE de un PF —el contador se adelantó, o
// hubo una carrera— tiene que mostrar el MISMO aviso que el embudo
// (`intentarCrearEjercicioPropio`), no el toast genérico. Nunca en EDIT: E3
// dice que bajar de plan no toca lo que ya existe, y el update no mira la
// cuota (`firestore.rules`, "Update y delete NO miran la cuota").

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
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

CustomExercise _existing() => CustomExercise(
      id: 'ex-1',
      ownerId: _uid,
      name: 'Press banca',
      muscleGroup: 'chest',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required CustomExerciseRepository repo,
  required AsyncValue<CustomExerciseQuota> quota,
  String? exerciseId = 'new',
  List<CustomExercise> existing = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_uid),
        customExerciseRepositoryProvider.overrideWithValue(repo),
        customExercisesForTrainerStreamProvider(_uid)
            .overrideWith((ref) => Stream.value(existing)),
        customExerciseQuotaProvider.overrideWithValue(quota),
        // No hay Firestore real en este test — fijos, para no depender de
        // Firebase.initializeApp().
        customExerciseVideoCountProvider.overrideWith((ref) => Stream.value(0)),
        customExerciseVideoCapsProvider
            .overrideWithValue((maxCount: 50, maxBytes: 100 * 1024 * 1024)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: SafeArea(
            child: CustomExerciseEditorScreen(exerciseId: exerciseId),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() {
    registerFallbackValue(_existing());
  });

  group('CREATE — rebote del servidor', () {
    testWidgets(
        'permission-denied con cuota resuelta ⇒ muestra el aviso del tope, '
        'no el toast genérico', (tester) async {
      final repo = _MockRepo();
      when(() => repo.create(
            trainerId: any(named: 'trainerId'),
            name: any(named: 'name'),
            muscleGroup: any(named: 'muscleGroup'),
            secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
            description: any(named: 'description'),
            videoUrl: any(named: 'videoUrl'),
            equipment: any(named: 'equipment'),
          )).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      await _pump(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: 60, count: 60)),
      );

      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.tap(find.text('GUARDAR EJERCICIO'));
      // `pump()` fijo y no `pumpAndSettle()`: `ExerciseVideoPlayer` puede
      // dejar un Timer vivo en el árbol (gotcha de este repo — keepAlive +
      // Timer cuelgan pumpAndSettle sin excepción legible).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Llegaste a los 60 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsOneWidget,
      );
      expect(find.text('No pudimos guardar el ejercicio.'), findsNothing);
    });

    testWidgets(
        'permission-denied SIN cuota resuelta ⇒ cae al toast genérico (no '
        'inventa números)', (tester) async {
      final repo = _MockRepo();
      when(() => repo.create(
            trainerId: any(named: 'trainerId'),
            name: any(named: 'name'),
            muscleGroup: any(named: 'muscleGroup'),
            secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
            description: any(named: 'description'),
            videoUrl: any(named: 'videoUrl'),
            equipment: any(named: 'equipment'),
          )).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      await _pump(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: null, count: 0)),
      );

      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.tap(find.text('GUARDAR EJERCICIO'));
      // `pump()` fijo y no `pumpAndSettle()`: `ExerciseVideoPlayer` puede
      // dejar un Timer vivo en el árbol (gotcha de este repo — keepAlive +
      // Timer cuelgan pumpAndSettle sin excepción legible).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No pudimos guardar el ejercicio.'), findsOneWidget);
    });

    testWidgets('otro código de error ⇒ NO muestra el aviso del tope',
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
          )).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'unavailable'),
      );

      await _pump(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: 60, count: 60)),
      );

      await tester.enterText(find.byType(TextField).first, 'Sentadilla');
      await tester.tap(find.text('GUARDAR EJERCICIO'));
      // `pump()` fijo y no `pumpAndSettle()`: `ExerciseVideoPlayer` puede
      // dejar un Timer vivo en el árbol (gotcha de este repo — keepAlive +
      // Timer cuelgan pumpAndSettle sin excepción legible).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No pudimos guardar el ejercicio.'), findsOneWidget);
      expect(
        find.text('Llegaste a los 60 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsNothing,
      );
    });
  });

  group('EDIT — el rebote del tope no aplica', () {
    testWidgets(
        'permission-denied en UPDATE ⇒ nunca muestra el aviso del tope '
        '(E3 — update no mira la cuota)', (tester) async {
      final repo = _MockRepo();
      when(() => repo.update(any())).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      final ex = _existing();
      await _pump(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: 60, count: 60)),
        exerciseId: ex.id,
        existing: [ex],
      );

      await tester.tap(find.text('GUARDAR CAMBIOS'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No pudimos guardar el ejercicio.'), findsOneWidget);
      expect(
        find.text('Llegaste a los 60 ejercicios propios de tu plan. Podés '
            'editar o borrar los que ya tenés.'),
        findsNothing,
      );
    });
  });
}
