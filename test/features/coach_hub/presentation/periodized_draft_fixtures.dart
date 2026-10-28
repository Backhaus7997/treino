import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/application/plan_pdf_import_providers.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/exercise_repository.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_excel_parser.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import '../data/periodized_test_helpers.dart';

/// Borrador del import armado con el parser REAL a partir de renglones de la
/// hoja `Programa` (después del encabezado del DÍA 1 con [weeks] semanas).
///
/// Cada renglón: `[N°, ejercicio, descanso, semana1, semana2, …]`. Un bloque
/// de día nuevo se agrega con `header(n)`.
///
/// El matcher corre contra [catalog]: lo exacto queda asignado; lo que no
/// está en el catálogo queda sin match. [suggestions] fuerza sugerencias
/// pendientes por nombre crudo (el matcher las produce sólo para nombres
/// parecidos, y estos tests miran la UX, no el fuzzy).
PeriodizedImportDraft draftOf(
  List<List<Object?>> body, {
  int weeks = 4,
  List<MatcherExercise> catalog = const [],
  Map<String, MatcherExercise> suggestions = const {},
  String name = 'Test Plan',
}) {
  final parsed = parsePeriodizedExcel(
    programa([header1(weeks: weeks), ...body]),
  );
  assert(parsed.canImport, 'fixture inválido: ${parsed.errors}');
  final plan = parsed.plan!;
  final match = matchPeriodizedPlan(plan, catalog);
  final draft = PeriodizedImportDraft.fromMatch(
    plan: plan,
    warnings: parsed.warnings,
    name: name,
    match: match,
  );
  if (suggestions.isEmpty) return draft;
  return PeriodizedImportDraft(
    plan: plan,
    warnings: parsed.warnings,
    name: name,
    assignments: draft.assignments,
    suggestions: {
      for (final day in plan.days)
        for (final row in day.rows)
          for (final ex in row.exercises)
            if (suggestions.containsKey(ex.rawName) &&
                !draft.assignments.containsKey(exerciseKeyOf(day, row, ex)))
              exerciseKeyOf(day, row, ex): suggestions[ex.rawName]!,
    },
  );
}

/// Borrador como el que deja `PlanPdfImportService` después de un parse
/// exitoso, SIN dueño (`athleteId` null, como lo arma el Coach Hub): dos
/// semanas, una fila ya resuelta, otra con sugerencia del fuzzy y la
/// alternativa del extractor, el texto del PDF en cada una y un aviso.
final kPdfSentadilla =
    MatcherExercise(id: 'sq', name: 'Sentadilla', muscleGroup: 'quadriceps');
final kPdfRemoBarra =
    MatcherExercise(id: 'rb', name: 'Remo con barra', muscleGroup: 'back');
final kPdfRemoMancuerna =
    MatcherExercise(id: 'rm', name: 'Remo con mancuerna', muscleGroup: 'back');
const kPdfRemoKey = (dayNumber: 1, row: 2, component: 0);
const kPdfWarning = 'No se lee bien la semana 2 del día 1.';

PeriodizedImportDraft pdfDraft() {
  const plan = PeriodizedPlan(numWeeks: 2, days: [
    PeriodizedDay(dayNumber: 1, rows: [
      PeriodizedRow(position: 1, number: 1, restSeconds: 120, exercises: [
        PeriodizedExercise(
          component: 0,
          rawName: 'Sentadilla trasera',
          weeks: [
            [SetSpec(reps: 8), SetSpec(reps: 8)],
            [SetSpec(reps: 6), SetSpec(reps: 6)],
          ],
          sourceText: 'Sentadilla trasera 2x8 / 2x6',
        ),
      ]),
      PeriodizedRow(position: 2, number: 2, restSeconds: 90, exercises: [
        PeriodizedExercise(
          component: 0,
          rawName: 'Remo barra',
          weeks: [
            [SetSpec(reps: 10)],
            [SetSpec(reps: 12)],
          ],
          sourceText: 'Remo barra 1x10 / 1x12',
        ),
      ]),
    ]),
  ]);
  return PeriodizedImportDraft(
    plan: plan,
    warnings: const [
      ImportDiagnostic(
        severity: ImportDiagnosticSeverity.warning,
        code: ImportDiagnosticCode.extractorWarning,
        message: kPdfWarning,
        page: 2,
      ),
    ],
    name: 'plan fuerza',
    assignments: {(dayNumber: 1, row: 1, component: 0): kPdfSentadilla},
    suggestions: {kPdfRemoKey: kPdfRemoBarra},
    alternatives: {kPdfRemoKey: kPdfRemoMancuerna},
  );
}

/// Una celda por semana, iguales: `['3x10', '3x10', …]`.
List<Object?> sameWeeks(String cell, [int weeks = 4]) =>
    List<Object?>.filled(weeks, cell);

/// Superficie de test alta para que toda la vista previa entre sin scroll:
/// la pantalla es una columna larga (meta, avisos, días, alumnos, botón) y
/// los taps por texto necesitan el botón dentro del viewport.
///
/// Se llama una vez al principio de `main()`.
void useTallSurface() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .implicitView!;
    view.physicalSize = const Size(800, 3000);
    view.devicePixelRatio = 1;
  });
  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
}

// ─── Harness de la vista previa ─────────────────────────────────────────────

class MockRoutineRepo extends Mock implements RoutineRepository {}

const kTrainerUid = 'trainer-1';
const kAthleteId = 'ath-1';

UserProfile trainerProfile() => UserProfile(
      uid: kTrainerUid,
      email: 'trainer@test.com',
      role: UserRole.trainer,
      displayName: 'Trainer Test',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Overrides para montar la vista previa con UN alumno activo.
List<Override> previewOverrides(RoutineRepository repo) => [
      userProfileProvider.overrideWith((ref) => Stream.value(trainerProfile())),
      currentUidProvider.overrideWithValue(kTrainerUid),
      routineRepositoryProvider.overrideWithValue(repo),
      trainerLinksStreamProvider.overrideWith(
        (ref) => Stream.value([
          TrainerLink(
            id: 'link-$kAthleteId',
            trainerId: kTrainerUid,
            athleteId: kAthleteId,
            status: TrainerLinkStatus.active,
            requestedAt: DateTime.utc(2026, 1, 1),
          ),
        ]),
      ),
      userPublicProfileProvider(kAthleteId).overrideWith(
        (ref) => Stream.value(
          const UserPublicProfile(uid: kAthleteId, displayName: 'Ana'),
        ),
      ),
    ];

Widget appWith(GoRouter router, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    );

/// Monta SOLO la vista previa con [draft] ya cargado.
Future<void> pumpPreview(
  WidgetTester tester,
  PeriodizedImportDraft draft,
  RoutineRepository repo, {
  List<Override> extra = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/preview',
    routes: [
      GoRoute(
        path: '/preview',
        builder: (_, __) => const Scaffold(body: CoachHubPlanPreviewScreen()),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('DASHBOARD')),
      ),
      GoRoute(
        path: '/upload-plan',
        builder: (_, __) => const Scaffold(body: Text('UPLOAD')),
      ),
    ],
  );
  await tester.pumpWidget(appWith(router, [
    ...previewOverrides(repo),
    periodizedImportProvider.overrideWith((ref) => draft),
    ...extra,
  ]));
  await tester.pumpAndSettle();
}

// ─── Harness de la pantalla de subir ────────────────────────────────────────

/// File picker de test: devuelve siempre el mismo archivo.
class FakeFilePicker extends FilePicker {
  FakeFilePicker(this.file);
  final PlatformFile file;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([file]);
}

class MockExerciseRepo extends Mock implements ExerciseRepository {}

/// Repositorio de ejercicios con [catalog] como catálogo completo.
ExerciseRepository exerciseRepoWith(List<Exercise> catalog) {
  final repo = MockExerciseRepo();
  when(repo.listAll).thenAnswer((_) async => catalog);
  return repo;
}

/// Pantalla de subir + vista previa + dashboard, con el archivo [bytes]
/// ya "elegido" por el picker. Devuelve el repo de rutinas para verificar.
///
/// [pdfGate] es el kill switch del import de PDF; apagado por defecto, que
/// es la pantalla del Excel solo. [extra] suma overrides (el servicio del
/// PDF, el cupo).
Future<void> pumpUploadFlow(
  WidgetTester tester, {
  required Uint8List bytes,
  required List<Exercise> catalog,
  required RoutineRepository routineRepo,
  String fileName = 'mi-plan.xlsx',
  int? fileSize,
  PdfImportGate pdfGate = PdfImportGate.disabled,
  List<Override> extra = const [],
}) async {
  FilePicker.platform = FakeFilePicker(
    PlatformFile(name: fileName, size: fileSize ?? bytes.length, bytes: bytes),
  );
  final router = GoRouter(
    initialLocation: '/upload-plan',
    routes: [
      GoRoute(
        path: '/upload-plan',
        builder: (_, __) => const Scaffold(body: CoachHubUploadPlanScreen()),
        routes: [
          GoRoute(
            path: 'preview',
            builder: (_, __) =>
                const Scaffold(body: CoachHubPlanPreviewScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const Scaffold(body: Text('DASHBOARD')),
      ),
    ],
  );
  await tester.pumpWidget(appWith(router, [
    ...previewOverrides(routineRepo),
    exerciseRepositoryProvider.overrideWithValue(exerciseRepoWith(catalog)),
    pdfImportGateProvider.overrideWithValue(pdfGate),
    ...extra,
  ]));
  await tester.pumpAndSettle();
}

/// Elige el archivo y aprieta PROCESAR PLAN.
Future<void> pickAndProcess(WidgetTester tester) async {
  await tester.tap(find.text('Elegir archivo'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('PROCESAR PLAN'));
  await tester.pumpAndSettle();
}
