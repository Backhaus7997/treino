// Tests for the Coach Hub WEB exercise picker dialog — mirrors the coverage
// of the mobile exercise_picker_sheet_test.dart, adapted for a Dialog
// presentation (tap-outside-barrier dismiss instead of drag-to-dismiss) and
// the inline muscle/equipment chip filters (ADR-CHW-005 — no bottom sheet).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/widgets/custom_exercise_video_web_uploader.dart';
import 'package:treino/features/coach_hub/presentation/widgets/exercise_picker_dialog.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';

import '../../../../fixtures/exercises.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _kExercises = [
  kExerciseSeed[0], // bench-press (chest/barra)
  kExerciseSeed[1], // incline-dumbbell-press (chest/mancuerna)
  kExerciseSeed[6], // back-squat (quads/barra)
];

/// One custom exercise owned by 'u1' — used by the edit/delete tests.
final _customBench = CustomExercise(
  id: 'cx-1',
  ownerId: 'u1',
  name: 'Press plano casero',
  muscleGroup: 'chest',
  equipment: EquipmentType.mancuerna,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

List<Override> _overrides({List<Exercise>? exercises}) => [
  currentUidProvider.overrideWithValue('u1'),
  exercisesProvider.overrideWith((ref) async => exercises ?? _kExercises),
  customExercisesForTrainerStreamProvider(
    'u1',
  ).overrideWith((ref) => Stream<List<CustomExercise>>.value(const [])),
];

Future<void> _openPicker(
  WidgetTester tester, {
  List<Exercise>? exercises,
  Set<String> alreadySelectedIds = const {},
  void Function(List<Exercise>?)? onResult,
  List<Override> extraOverrides = const [],
}) async {
  // Coach Hub web dialogs assume a desktop viewport; the picker's 640px
  // height overflows the flutter_test default 800x600 surface.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._overrides(exercises: exercises),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () async {
                final result = await showExercisePickerDialog(
                  ctx,
                  alreadySelectedIds: alreadySelectedIds,
                );
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

class _MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class _MockVideoUploader extends Mock
    implements CustomExerciseVideoWebUploader {}

void main() {
  setUpAll(() {
    registerFallbackValue(EquipmentType.mancuerna);
    registerFallbackValue(_customBench);
  });

  group('ExercisePickerDialog (web) — core selection', () {
    testWidgets('empty selection: CTA shows "Agregar" without a count', (
      tester,
    ) async {
      await _openPicker(tester);

      expect(find.text('Agregar'), findsOneWidget);
      expect(find.textContaining('Agregar ('), findsNothing);
    });

    testWidgets('single tap: CTA shows "Agregar (1)"', (tester) async {
      await _openPicker(tester);
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar (1)'), findsOneWidget);
    });

    testWidgets('multi-tap then deselect: counter updates', (tester) async {
      await _openPicker(tester);

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla con Barra'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar (2)'), findsOneWidget);

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();

      expect(find.text('Agregar (1)'), findsOneWidget);
    });

    testWidgets('confirm: pops List<Exercise> with the selected ids', (
      tester,
    ) async {
      List<Exercise>? result;
      await _openPicker(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sentadilla con Barra'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Agregar (2)'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      final ids = result!.map((e) => e.id).toSet();
      expect(ids, {'bench-press', 'back-squat'});
    });

    testWidgets('Cancelar button pops null', (tester) async {
      List<Exercise>? result = _kExercises; // non-null sentinel
      await _openPicker(tester, onResult: (r) => result = r);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('tap outside the dialog barrier pops null', (tester) async {
      List<Exercise>? result = _kExercises;
      await _openPicker(tester, onResult: (r) => result = r);

      // Corner of the screen, outside the 560x640 centered dialog.
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    testWidgets('alreadySelectedIds pre-marks the CTA count', (tester) async {
      await _openPicker(tester, alreadySelectedIds: const {'bench-press'});

      expect(find.text('Agregar (1)'), findsOneWidget);
    });

    testWidgets('the confirm CTA is disabled at zero selection', (
      tester,
    ) async {
      await _openPicker(tester);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Agregar'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('ExercisePickerDialog (web) — search + inline filters', () {
    testWidgets('search filters the list; selected count is maintained', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      expect(find.text('Agregar (1)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'sentadilla');
      await tester.pumpAndSettle();

      // Counter still 1 even though bench-press scrolled out of the filtered list.
      expect(find.text('Agregar (1)'), findsOneWidget);
      expect(find.text('Sentadilla con Barra'), findsOneWidget);
      expect(find.text('Press de Banca'), findsNothing);
    });

    testWidgets(
      'inline muscle chip filters by muscle group (no bottom sheet)',
      (tester) async {
        await _openPicker(tester);

        // Both chest exercises + the quads one are visible before filtering.
        expect(find.text('Press de Banca'), findsOneWidget);
        expect(find.text('Sentadilla con Barra'), findsOneWidget);

        // Tap the PECHO muscle chip — filters to chest-only.
        await tester.tap(find.text('PECHO'));
        await tester.pumpAndSettle();

        expect(find.text('Press de Banca'), findsOneWidget);
        expect(find.text('Sentadilla con Barra'), findsNothing);

        // Tapping PECHO again toggles it off — back to the unfiltered list.
        await tester.tap(find.text('PECHO'));
        await tester.pumpAndSettle();

        expect(find.text('Sentadilla con Barra'), findsOneWidget);
      },
    );

    testWidgets('no-match filters show the empty-state message', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.enterText(find.byType(TextField), 'zzz-no-existe');
      await tester.pumpAndSettle();

      expect(
        find.text('No encontramos ejercicios con esos filtros.'),
        findsOneWidget,
      );
    });
  });

  group('ExercisePickerDialog (web) — crear ejercicio nuevo (inline)', () {
    testWidgets('muestra el botón "+ Crear ejercicio nuevo"', (tester) async {
      await _openPicker(tester);

      expect(
        find.byKey(const Key('create_new_exercise_button')),
        findsOneWidget,
      );
      expect(find.text('Crear ejercicio nuevo'), findsOneWidget);
    });

    testWidgets('tocarlo abre el formulario de nuevo ejercicio', (
      tester,
    ) async {
      await _openPicker(tester);

      await tester.tap(find.byKey(const Key('create_new_exercise_button')));
      await tester.pumpAndSettle();

      expect(find.text('Nuevo ejercicio'), findsOneWidget);
      expect(
        find.byKey(const Key('create_exercise_name_field')),
        findsOneWidget,
      );
    });

    testWidgets('sin nombre no llama al repo y muestra el error', (
      tester,
    ) async {
      final repo = _MockCustomExerciseRepository();
      await _openPicker(
        tester,
        extraOverrides: [
          customExerciseRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await tester.tap(find.byKey(const Key('create_new_exercise_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Poné un nombre al ejercicio.'), findsOneWidget);
      verifyNever(
        () => repo.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        ),
      );
    });

    testWidgets('crear un ejercicio lo persiste y lo autoselecciona', (
      tester,
    ) async {
      final repo = _MockCustomExerciseRepository();
      when(
        () => repo.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        ),
      ).thenAnswer(
        (inv) async => CustomExercise(
          id: 'new-ex-1',
          ownerId: inv.namedArguments[#trainerId] as String,
          name: inv.namedArguments[#name] as String,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );

      await _openPicker(
        tester,
        extraOverrides: [
          customExerciseRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await tester.tap(find.byKey(const Key('create_new_exercise_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Sentadilla búlgara',
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      // Repo persisted it with the trainer uid + trimmed name.
      final captured = verify(
        () => repo.create(
          trainerId: captureAny(named: 'trainerId'),
          name: captureAny(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        ),
      ).captured;
      expect(captured, ['u1', 'Sentadilla búlgara']);

      // Back in the picker, the new exercise is pre-selected → CTA count = 1.
      expect(find.text('Agregar (1)'), findsOneWidget);
    });
  });

  group('ExercisePickerDialog (web) — editar/borrar ejercicio custom', () {
    List<Override> withCustom(CustomExerciseRepository repo) => [
      customExercisesForTrainerStreamProvider(
        'u1',
      ).overrideWith((ref) => Stream.value([_customBench])),
      customExerciseRepositoryProvider.overrideWithValue(repo),
    ];

    testWidgets('editar abre el form pre-cargado y guarda vía update', (
      tester,
    ) async {
      final repo = _MockCustomExerciseRepository();
      when(() => repo.update(any())).thenAnswer((_) async {});
      await _openPicker(tester, extraOverrides: withCustom(repo));

      expect(find.text('Press plano casero'), findsOneWidget);
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      // Modo edición, pre-cargado.
      expect(find.text('Editar ejercicio'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Press plano en casa',
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      // update conserva el id (mismo doc) y toma el nombre nuevo.
      final updated =
          verify(() => repo.update(captureAny())).captured.single
              as CustomExercise;
      expect(updated.id, 'cx-1');
      expect(updated.name, 'Press plano en casa');
    });

    testWidgets('borrar pide confirmación y llama a delete', (tester) async {
      final repo = _MockCustomExerciseRepository();
      when(
        () => repo.delete(
          trainerId: any(named: 'trainerId'),
          id: any(named: 'id'),
        ),
      ).thenAnswer((_) async {});
      await _openPicker(tester, extraOverrides: withCustom(repo));

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();

      // Confirmación → el botón "Eliminar" del diálogo (no el ícono).
      expect(find.text('¿Eliminar ejercicio?'), findsOneWidget);
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();

      verify(() => repo.delete(trainerId: 'u1', id: 'cx-1')).called(1);
      expect(find.text('Ejercicio eliminado.'), findsOneWidget);
    });

    testWidgets('cancelar la confirmación no borra', (tester) async {
      final repo = _MockCustomExerciseRepository();
      await _openPicker(tester, extraOverrides: withCustom(repo));

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      // El footer del picker también tiene "Cancelar" → scopear al diálogo de
      // confirmación (AlertDialog; el picker es un Dialog).
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar'),
        ),
      );
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.delete(
          trainerId: any(named: 'trainerId'),
          id: any(named: 'id'),
        ),
      );
    });
  });

  group('ExercisePickerDialog (web) — video del ejercicio custom', () {
    // Neither a YouTube nor a Storage URL → ExerciseVideoPlayer renders a static
    // placeholder (no network image / no video controller), so the preview
    // never leaves a widget test un-settleable.
    const kVideoUrl = 'https://vids.test/clip1';

    List<Override> repoOverride(CustomExerciseRepository repo) => [
      customExerciseRepositoryProvider.overrideWithValue(repo),
    ];

    void stubCreate(_MockCustomExerciseRepository repo) {
      when(
        () => repo.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        ),
      ).thenAnswer(
        (inv) async => CustomExercise(
          id: 'new-ex',
          ownerId: inv.namedArguments[#trainerId] as String,
          name: inv.namedArguments[#name] as String,
          videoUrl: inv.namedArguments[#videoUrl] as String?,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
    }

    List<String?> capturedCreate(_MockCustomExerciseRepository repo) => verify(
      () => repo.create(
        trainerId: captureAny(named: 'trainerId'),
        name: captureAny(named: 'name'),
        muscleGroup: any(named: 'muscleGroup'),
        secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
        description: any(named: 'description'),
        videoUrl: captureAny(named: 'videoUrl'),
        defaultRestSeconds: any(named: 'defaultRestSeconds'),
        equipment: any(named: 'equipment'),
      ),
    ).captured.cast<String?>();

    testWidgets('un link pegado se guarda en videoUrl al crear', (
      tester,
    ) async {
      final repo = _MockCustomExerciseRepository();
      stubCreate(repo);
      await _openPicker(tester, extraOverrides: repoOverride(repo));

      await tester.tap(find.byKey(const Key('create_new_exercise_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Sentadilla',
      );
      await tester.enterText(
        find.byKey(const Key('create_exercise_video_field')),
        kVideoUrl,
      );
      await tester.pumpAndSettle();
      // The video preview makes the form taller than the viewport → scroll the
      // submit button into view before tapping.
      await tester.ensureVisible(
        find.byKey(const Key('create_exercise_submit_button')),
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      expect(capturedCreate(repo), ['u1', 'Sentadilla', kVideoUrl]);
    });

    testWidgets('"Subir mi propio video" sube y guarda la URL devuelta', (
      tester,
    ) async {
      final repo = _MockCustomExerciseRepository();
      stubCreate(repo);
      final uploader = _MockVideoUploader();
      when(
        () => uploader.pickAndUpload(onProgress: any(named: 'onProgress')),
      ).thenAnswer((_) async => 'https://vids.test/uploaded');

      await _openPicker(
        tester,
        extraOverrides: [
          ...repoOverride(repo),
          customExerciseVideoWebUploaderProvider.overrideWithValue(uploader),
        ],
      );

      await tester.tap(find.byKey(const Key('create_new_exercise_button')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('create_exercise_upload_video_button')),
      );
      await tester.tap(
        find.byKey(const Key('create_exercise_upload_video_button')),
      );
      await tester.pumpAndSettle();

      // El campo quedó con la URL subida.
      final field = tester.widget<TextField>(
        find.byKey(const Key('create_exercise_video_field')),
      );
      expect(field.controller?.text, 'https://vids.test/uploaded');

      await tester.enterText(
        find.byKey(const Key('create_exercise_name_field')),
        'Sentadilla',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('create_exercise_submit_button')),
      );
      await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
      await tester.pumpAndSettle();

      verify(
        () => uploader.pickAndUpload(onProgress: any(named: 'onProgress')),
      ).called(1);
      expect(capturedCreate(repo), [
        'u1',
        'Sentadilla',
        'https://vids.test/uploaded',
      ]);
    });

    testWidgets('editar pre-carga el video existente', (tester) async {
      final withVideo = _customBench.copyWith(
        videoUrl: 'https://vids.test/existing',
      );
      final repo = _MockCustomExerciseRepository();
      await _openPicker(
        tester,
        extraOverrides: [
          customExercisesForTrainerStreamProvider(
            'u1',
          ).overrideWith((ref) => Stream.value([withVideo])),
          ...repoOverride(repo),
        ],
      );

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('create_exercise_video_field')),
      );
      expect(field.controller?.text, 'https://vids.test/existing');
    });
  });
}
