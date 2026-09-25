// create_custom_exercise_dialog_test.dart — el rebote del servidor en la
// web (docs/limite-ejercicios-pf.md PR3, "El rebote del servidor").
//
// Espejo de custom_exercise_editor_screen_test.dart (móvil) para el diálogo
// del Coach Hub: un `permission-denied` en el CREATE de un PF muestra el
// MISMO aviso que el embudo — acá, el diálogo con VER PLANES — y no el error
// genérico del form. Nunca en EDIT.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_limit_notice.dart';
import 'package:treino/features/coach_hub/presentation/widgets/create_custom_exercise_dialog.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';

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

Future<void> _montar(
  WidgetTester tester, {
  required CustomExerciseRepository repo,
  required AsyncValue<CustomExerciseQuota> quota,
  CustomExercise? existing,
}) async {
  // Coach Hub web dialogs asumen viewport de escritorio; el default 800x600
  // de flutter_test deja el submit fuera del área hit-testeable.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_uid),
        customExerciseRepositoryProvider.overrideWithValue(repo),
        customExerciseQuotaProvider.overrideWithValue(quota),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => existing == null
                  ? showCreateCustomExerciseDialog(context)
                  : showEditCustomExerciseDialog(context, existing),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_existing());
  });

  setUp(() {
    // Seam de test (trainer_limit_notice.dart): `kIsWeb` es una
    // constante de compilación que bajo `flutter test` vale `false` siempre
    // — sin esto el aviso saldría con la forma MÓVIL (sheet) en un test del
    // diálogo WEB.
    debugTrainerLimitNoticeForm = TrainerLimitNoticeForm.dialog;
  });

  tearDown(() {
    debugTrainerLimitNoticeForm = null;
  });

  group('CREATE — rebote del servidor', () {
    testWidgets(
        'permission-denied con cuota resuelta ⇒ muestra el diálogo del tope '
        'con VER PLANES, no el error genérico', (tester) async {
      final repo = _MockRepo();
      when(() => repo.create(
            trainerId: any(named: 'trainerId'),
            name: any(named: 'name'),
            muscleGroup: any(named: 'muscleGroup'),
            equipment: any(named: 'equipment'),
            videoUrl: any(named: 'videoUrl'),
          )).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      await _montar(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: 60, count: 60)),
      );

      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Sentadilla',
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
      expect(find.text('No pudimos guardar el ejercicio.'), findsNothing);
    });

    testWidgets(
        'permission-denied SIN cuota resuelta ⇒ cae al error genérico del '
        'form (no inventa números)', (tester) async {
      final repo = _MockRepo();
      when(() => repo.create(
            trainerId: any(named: 'trainerId'),
            name: any(named: 'name'),
            muscleGroup: any(named: 'muscleGroup'),
            equipment: any(named: 'equipment'),
            videoUrl: any(named: 'videoUrl'),
          )).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      await _montar(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: null, count: 0)),
      );

      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Sentadilla',
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos guardar el ejercicio.'), findsOneWidget);
      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsNothing);
    });
  });

  group('EDIT — el rebote del tope no aplica', () {
    testWidgets(
        'permission-denied en UPDATE ⇒ nunca muestra el diálogo del tope '
        '(E3 — update no mira la cuota)', (tester) async {
      final repo = _MockRepo();
      when(() => repo.update(any())).thenThrow(
        FirebaseException(plugin: 'firestore', code: 'permission-denied'),
      );

      final ex = _existing();
      await _montar(
        tester,
        repo: repo,
        quota: const AsyncValue.data((limit: 60, count: 60)),
        existing: ex,
      );

      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos guardar el ejercicio.'), findsOneWidget);
      expect(find.text('TOPE DE EJERCICIOS PROPIOS'), findsNothing);
    });
  });
}
