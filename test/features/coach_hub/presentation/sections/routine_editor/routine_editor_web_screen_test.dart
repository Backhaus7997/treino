// Tests for RoutineEditorWebScreen — web MVP routine editor (create-only,
// single week, normal sets). Mirrors the mocking pattern of
// routine_editor_athlete_mode_test.dart (mobile).

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';
import 'package:treino/features/workout/presentation/widgets/superset_block.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/application/blocked_athletes_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart'
    show kBlockedStudentsRoutePath;
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import '../../../../../fixtures/routine_editor_ui.dart';
import '../../../../../fixtures/exercises.dart';
import '../../../../../helpers/fake_analytics_service.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';

// ── Helpers ───────────────────────────────────────────────────────────────────

List<Override> _overrides({
  RoutineRepository? repo,
  FakeAnalyticsService? analytics,
  BlockedAthletes? blocked,
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(_trainerId),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    // Sin override el provider real queda en AsyncError (no hay app de
    // Firebase en `flutter test`), que es lo que quieren los tests que no
    // miran el paywall: nadie lee su valor. Los que sí lo miran pasan el
    // estado explícito — incluido `BlockedAthletes.unpublished`, que NO es lo
    // mismo que una lista vacía.
    if (blocked != null)
      blockedAthletesProvider.overrideWith((ref) => Stream.value(blocked)),
    if (analytics != null)
      analyticsServiceProvider.overrideWithValue(analytics),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(
      _trainerId,
    ).overrideWith((ref) => Stream<List<CustomExercise>>.value(const [])),
    userPublicProfileProvider(_athleteId).overrideWith(
      (ref) => Stream.value(
        const UserPublicProfile(uid: _athleteId, displayName: 'Juan Pérez'),
      ),
    ),
  ];
}

/// Pumps the editor. With [routineId] the edit route is pushed (edit mode);
/// without it, the create route (as before).
Future<void> _pumpEditor(
  WidgetTester tester, {
  RoutineRepository? repo,
  String? routineId,
  FakeAnalyticsService? analytics,
  BlockedAthletes? blocked,
}) async {
  // Desktop viewport — Coach Hub web dialogs (exercise picker) assume it.
  // Raised 900 → 1100 when the RESUMEN field (#648) landed above DÍAS: the
  // form is a SingleChildScrollView, so a short viewport leaves the day and
  // set controls in the tree but under the pinned footer, where tap() misses.
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // initialLocation is the alumno-detail stand-in, THEN we push the editor —
  // context.pop() needs real prior history to return to, not just a bare
  // initialLocation (which go_router can't pop past).
  final router = GoRouter(
    initialLocation: '/alumnos/$_athleteId',
    routes: [
      GoRoute(
        path: '/alumnos/:id',
        builder: (_, __) => const Scaffold(body: Text('AlumnoDetail')),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId',
        // CoachHubScaffold (the real shell) provides the Material ancestor —
        // this test stands in for it, matching other section-screen tests.
        builder: (_, state) => Scaffold(
          body: RoutineEditorWebScreen(
            athleteId: state.pathParameters['athleteId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, state) => Scaffold(
          body: RoutineEditorWebScreen(
            athleteId: state.pathParameters['athleteId']!,
            routineId: state.pathParameters['routineId'],
          ),
        ),
      ),
      // Stand-in de la pantalla de solo-lectura: el banner de denegación
      // ofrece esta salida y sin la ruta el push moriría contra go_router.
      // Va con la constante COMPARTIDA y no con el literal: que la ruta exista
      // de verdad lo prueba `routes_test.dart` contra
      // `facturacionPlanesRoutes`; lo que este stub tiene que garantizar es
      // que el destino sea el MISMO, no uno paralelo que el test se inventa.
      GoRoute(
        path: kBlockedStudentsRoutePath,
        builder: (_, __) => const Scaffold(body: Text('SOLO_LECTURA')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        repo: repo,
        analytics: analytics,
        blocked: blocked,
      ),
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        // Los delegates que el root real del Coach Hub ya provee
        // (`coach_hub_app.dart`) y este harness no tenía, porque la pantalla
        // tiene prohibido llamar a `AppL10n` (constraint C-6) y hasta ahora
        // ningún widget del árbol lo hacía.
        //
        // `QuickEntryPanel` sí lo llama — es compartido con el teléfono. C-6
        // aplica a la PANTALLA, no a los widgets que usa: en producción esto
        // funciona porque el root los inyecta. Sin ellos acá, el panel crashea
        // con "Null check operator used on a null value" desde `AppL10n.of`.
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  router.push(
    routineId == null
        ? '/routine-editor/$_athleteId'
        : '/routine-editor/$_athleteId/$routineId',
  );
  await tester.pumpAndSettle();

  // La card del ejercicio pasó a ser `ExerciseCard`, la MISMA del editor del
  // teléfono, y nace COLAPSADA: los campos de sets no están en el árbol hasta
  // que alguien abre la card. Sin esto, 42 de estos tests fallaban con
  // "Found 0 widgets" sobre campos que sí existen.
  //
  // El helper es el del mobile sin adaptar: busca las keys de `ExerciseCard`,
  // que ahora las dos pantallas dibujan. Es el primer beneficio concreto de
  // compartir el widget en vez de tener dos implementaciones.
  await expandirEjercicios(tester);

  // Y volver ARRIBA. `expandirEjercicios` usa `ensureVisible` para alcanzar
  // cada cabecera, así que deja el viewport corrido donde estaba la última
  // card. Cualquier test que después tapee algo de la parte de arriba —las
  // pestañas de semana, el botón de duplicar— fallaba con "Found 0 widgets"
  // sobre un widget que existe.
  //
  // Se resuelve acá y no en cada test a propósito: es un efecto de este
  // helper, no un problema de los tests.
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  if (vertical.evaluate().isNotEmpty) {
    tester.state<ScrollableState>(vertical.first).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
}

/// A web-editable (simple, single-week, reps) routine — the kind edit mode
/// accepts.
Routine _simpleRoutine({String id = 'r1', String name = 'Fuerza base'}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 90,
              sets: [SetSpec(reps: 8, weightKg: 60)],
            ),
          ],
        ),
      ],
    );

/// A trainer TEMPLATE (no athlete) — `RoutineSource.trainerTemplate`,
/// `assignedTo` null. The shape edit-mode template loading must accept.
Routine _templateRoutine({String id = 't1'}) => Routine(
      id: id,
      name: 'Plantilla PPL',
      split: 'PPL',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerTemplate,
      assignedBy: _trainerId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              targetReps: [8],
              targetWeightKg: 60,
              restSeconds: 90,
              sets: [SetSpec(reps: 8, weightKg: 60)],
            ),
          ],
        ),
      ],
    );

/// A web-editable routine that uses a rep RANGE + a coaching note (Fase 1).
Routine _rangeRoutine({String id = 'r2'}) => Routine(
      id: id,
      name: 'Hipertrofia',
      split: 'PPL',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
              repMode: RepMode.range,
              notes: 'Controlá la bajada',
              sets: [SetSpec(repsMin: 8, repsMax: 12, weightKg: 60)],
            ),
          ],
        ),
      ],
    );

/// A web-editable routine that uses a DURATION exercise (Fase 2).
Routine _durationRoutine({String id = 'r3'}) => Routine(
      id: id,
      name: 'Core',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'plank',
              exerciseName: 'Plancha',
              muscleGroup: 'core',
              targetSets: 1,
              targetRepsMin: 0,
              targetRepsMax: 0,
              restSeconds: 30,
              exerciseMode: ExerciseMode.duration,
              durationSeconds: 60,
              sets: [SetSpec(durationSeconds: 60)],
            ),
          ],
        ),
      ],
    );

/// A web-editable routine with a 2-exercise superset (shared supersetGroup).
Routine _supersetRoutine({String id = 'r4'}) => Routine(
      id: id,
      name: 'PPL',
      split: 'PPL',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 10,
              targetRepsMax: 10,
              restSeconds: 60,
              supersetGroup: 1,
              sets: [SetSpec(reps: 10, weightKg: 40)],
            ),
            RoutineSlot(
              exerciseId: 'cable-fly',
              exerciseName: 'Aperturas con Cable',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 12,
              targetRepsMax: 12,
              restSeconds: 60,
              supersetGroup: 1,
              sets: [SetSpec(reps: 12, weightKg: 15)],
            ),
          ],
        ),
      ],
    );

/// A web-editable multi-week routine: N weeks sharing one prescription
/// (weeklySets stays empty) — the Fase 4a shape.
Routine _multiWeekRoutine({String id = 'r5'}) =>
    _simpleRoutine(id: id).copyWith(numWeeks: 4);

/// A per-week PERIODIZED routine (weeklySets populated, 2 weeks with
/// DIFFERENT prescriptions) — web-editable since Fase 4b. Used by the
/// edit-round-trip test to confirm weeklySets survives a save unchanged.
Routine _perWeekRoutine({String id = 'r6'}) => Routine(
      id: id,
      name: 'Periodizada',
      split: 'PPL',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 90,
              sets: [SetSpec(reps: 8, weightKg: 60)],
              weeklySets: [
                [SetSpec(reps: 10, weightKg: 55)],
                [SetSpec(reps: 8, weightKg: 60)],
              ],
            ),
          ],
        ),
      ],
    );

/// A per-week PRESENCE-masked routine (activeWeeks populated: present only in
/// week 0 of 2) — web-editable since Fase 4c. Used by the edit round-trip
/// test to confirm activeWeeks survives a save unchanged.
/// Two NORMAL sets (reps 8, 60kg), single week — for exercising set-type
/// assignment and the running-number relabel.
Routine _twoNormalSetsRoutine({String id = 'r13'}) => Routine(
      id: id,
      name: 'Dos series',
      split: 'Full Body',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 2,
              targetRepsMin: 8,
              targetRepsMax: 8,
              targetReps: [8, 8],
              targetWeightKg: 60,
              restSeconds: 90,
              sets: [
                SetSpec(reps: 8, weightKg: 60),
                SetSpec(reps: 8, weightKg: 60),
              ],
            ),
          ],
        ),
      ],
    );

/// A single FAILURE set with NO reps — the mobile-authored shape web must
/// accept on save (a failure set works to failure; reps are optional).
Routine _failureSetRoutine({String id = 'r14'}) => Routine(
      id: id,
      name: 'Al fallo',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 0,
              targetRepsMax: 0,
              restSeconds: 90,
              sets: [SetSpec(type: SetType.failure, weightKg: 70)],
            ),
          ],
        ),
      ],
    );

/// Single week: Press+Sentadilla are ONE superset, Dominadas stands alone —
/// the shape a reorder must never silently re-group.
Routine _supersetOrderRoutine({String id = 'r12'}) => Routine(
      id: id,
      name: 'Orden con superserie',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              targetReps: [8],
              targetWeightKg: 60,
              restSeconds: 90,
              supersetGroup: 1,
              sets: [SetSpec(reps: 8, weightKg: 60)],
            ),
            RoutineSlot(
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              muscleGroup: 'legs',
              targetSets: 1,
              targetRepsMin: 10,
              targetRepsMax: 10,
              targetReps: [10],
              targetWeightKg: 80,
              restSeconds: 120,
              supersetGroup: 1,
              sets: [SetSpec(reps: 10, weightKg: 80)],
            ),
            RoutineSlot(
              exerciseId: 'pull-up',
              exerciseName: 'Dominadas',
              muscleGroup: 'back',
              targetSets: 1,
              targetRepsMin: 6,
              targetRepsMax: 6,
              targetReps: [6],
              restSeconds: 60,
              sets: [SetSpec(reps: 6)],
            ),
          ],
        ),
      ],
    );

/// 2-week plan whose week 1 carries typed sets and whose week 2 is plain —
/// duplicating week 1 onto week 2 must carry the types across.
Routine _twoWeekTypedRoutine({String id = 'r10'}) => Routine(
      id: id,
      name: 'Tipada 2 semanas',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 2,
              targetRepsMin: 8,
              targetRepsMax: 12,
              targetReps: [12, 8],
              targetWeightKg: 20,
              restSeconds: 90,
              sets: [
                SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                SetSpec(reps: 8, weightKg: 60),
              ],
              weeklySets: [
                [
                  SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                  SetSpec(reps: 8, weightKg: 60),
                ],
                [
                  SetSpec(reps: 10, weightKg: 50),
                  SetSpec(reps: 10, weightKg: 50)
                ],
              ],
            ),
          ],
        ),
      ],
    );

/// 2-week plan with a superset (Press+Sentadilla) followed by a standalone
/// Dominadas, where the SECOND superset member lives only in week 2. Copying
/// week 1 over week 2 evicts it — and must not leave Press linked to
/// Dominadas.
Routine _presenceDropRoutine({String id = 'r11'}) => Routine(
      id: id,
      name: 'Drop de presencia',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              targetReps: [8],
              targetWeightKg: 60,
              restSeconds: 90,
              supersetGroup: 1,
              sets: [SetSpec(reps: 8, weightKg: 60)],
              weeklySets: [
                [SetSpec(reps: 8, weightKg: 60)],
                [SetSpec(reps: 8, weightKg: 60)],
              ],
            ),
            // Superset partner — scheduled ONLY in week 2.
            RoutineSlot(
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              muscleGroup: 'legs',
              targetSets: 1,
              targetRepsMin: 10,
              targetRepsMax: 10,
              targetReps: [10],
              targetWeightKg: 80,
              restSeconds: 120,
              supersetGroup: 1,
              sets: [SetSpec(reps: 10, weightKg: 80)],
              weeklySets: [
                [SetSpec(reps: 10, weightKg: 80)],
                [SetSpec(reps: 10, weightKg: 80)],
              ],
              activeWeeks: [1],
            ),
            RoutineSlot(
              exerciseId: 'pull-up',
              exerciseName: 'Dominadas',
              muscleGroup: 'back',
              targetSets: 1,
              targetRepsMin: 6,
              targetRepsMax: 6,
              targetReps: [6],
              restSeconds: 60,
              sets: [SetSpec(reps: 6)],
              weeklySets: [
                [SetSpec(reps: 6)],
                [SetSpec(reps: 6)],
              ],
            ),
          ],
        ),
      ],
    );

/// A mobile-authored plan exercising every axis at once: 2 weeks with distinct
/// per-week loads, a superset pair, typed sets, a rep range, coaching notes and
/// a presence mask. Its legacy fields are filled exactly as mobile's
/// `buildRoutineSlot` derives them, so a faithful web round-trip is an
/// identity — any diff is a field web silently drops or rewrites.
Routine _kitchenSinkRoutine({String id = 'r9'}) => Routine(
      id: id,
      name: 'Periodizada completa',
      split: 'PPL',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            // Superset member 1: reps/single, typed sets, present every week.
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 6,
              targetRepsMax: 12,
              targetReps: [12, 8, 6],
              targetWeightKg: 20,
              restSeconds: 90,
              supersetGroup: 1,
              notes: 'Controlá la bajada',
              sets: [
                SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                SetSpec(reps: 8, weightKg: 60),
                SetSpec(type: SetType.failure, reps: 6, weightKg: 70),
              ],
              weeklySets: [
                [
                  SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                  SetSpec(reps: 8, weightKg: 60),
                  SetSpec(type: SetType.failure, reps: 6, weightKg: 70),
                ],
                [
                  SetSpec(type: SetType.warmup, reps: 12, weightKg: 25),
                  SetSpec(reps: 8, weightKg: 65),
                  SetSpec(type: SetType.failure, reps: 5, weightKg: 75),
                ],
              ],
            ),
            // Superset member 2: reps/RANGE, dropped from week 2.
            RoutineSlot(
              exerciseId: 'squat',
              exerciseName: 'Sentadilla',
              muscleGroup: 'legs',
              targetSets: 2,
              targetRepsMin: 8,
              targetRepsMax: 12,
              targetWeightKg: 80,
              restSeconds: 120,
              supersetGroup: 1,
              repMode: RepMode.range,
              sets: [
                SetSpec(repsMin: 8, repsMax: 12, weightKg: 80),
                SetSpec(repsMin: 8, repsMax: 10, weightKg: 85),
              ],
              weeklySets: [
                [
                  SetSpec(repsMin: 8, repsMax: 12, weightKg: 80),
                  SetSpec(repsMin: 8, repsMax: 10, weightKg: 85),
                ],
                [
                  SetSpec(repsMin: 8, repsMax: 12, weightKg: 80),
                  SetSpec(repsMin: 8, repsMax: 10, weightKg: 85),
                ],
              ],
              activeWeeks: [0],
            ),
          ],
        ),
      ],
    );

/// A mobile-authored routine whose sets carry non-default [SetType]s — the
/// shape web must not damage when it opens and re-saves someone else's plan.
Routine _typedSetsRoutine({String id = 'r8'}) => Routine(
      id: id,
      name: 'Con series tipadas',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 90,
              sets: [
                SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                SetSpec(reps: 8, weightKg: 60),
                SetSpec(type: SetType.failure, reps: 6, weightKg: 70),
              ],
            ),
          ],
        ),
      ],
    );

Routine _presenceRoutine({String id = 'r7'}) => Routine(
      id: id,
      name: 'Con máscara de presencia',
      split: 'PPL',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 90,
              sets: [SetSpec(reps: 8, weightKg: 60)],
              activeWeeks: [0],
            ),
          ],
        ),
      ],
    );

/// Two exercises in ONE day with deliberately different prescriptions — the
/// shape "copiar sets del anterior" acts on (#655). The source carries a
/// warm-up so the copy has a set TYPE to prove it moved, and a different rest
/// so the test can prove rest does NOT move.
Routine _copyPrescriptionRoutine({String id = 'r20'}) => Routine(
      id: id,
      name: 'Copiar prescripción',
      split: 'Full Body',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 2,
              targetRepsMin: 8,
              targetRepsMax: 12,
              targetReps: [12, 8],
              targetWeightKg: 20,
              restSeconds: 90,
              sets: [
                SetSpec(type: SetType.warmup, reps: 12, weightKg: 20),
                SetSpec(reps: 8, weightKg: 60),
              ],
            ),
            RoutineSlot(
              exerciseId: 'incline-press',
              exerciseName: 'Press Inclinado',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 5,
              targetRepsMax: 5,
              targetReps: [5],
              targetWeightKg: 30,
              restSeconds: 60,
              sets: [SetSpec(reps: 5, weightKg: 30)],
            ),
          ],
        ),
      ],
    );

/// Source is a DURATION exercise, target is plain reps — copying must re-mode
/// the target, not paste seconds into a REPS/KG grid (#655).
Routine _copyModeRoutine({String id = 'r21'}) => Routine(
      id: id,
      name: 'Copiar modo',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'plank',
              exerciseName: 'Plancha',
              muscleGroup: 'core',
              targetSets: 1,
              targetRepsMin: 0,
              targetRepsMax: 0,
              restSeconds: 30,
              exerciseMode: ExerciseMode.duration,
              durationSeconds: 45,
              sets: [SetSpec(durationSeconds: 45)],
            ),
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 5,
              targetRepsMax: 5,
              targetReps: [5],
              targetWeightKg: 30,
              restSeconds: 60,
              sets: [SetSpec(reps: 5, weightKg: 30)],
            ),
          ],
        ),
      ],
    );

/// 2-week plan whose TARGET exercise is scheduled only in week 2 and carries a
/// different prescription per week — so a copy on week 2 can be proved to leave
/// week 1 and the presence mask alone (#655, ADR-WPRES).
Routine _copyPerWeekRoutine({String id = 'r22'}) => Routine(
      id: id,
      name: 'Copiar por semana',
      split: 'Full Body',
      level: ExperienceLevel.advanced,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      numWeeks: 2,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 10,
              targetRepsMax: 10,
              targetReps: [10],
              targetWeightKg: 55,
              restSeconds: 90,
              sets: [SetSpec(reps: 10, weightKg: 55)],
              weeklySets: [
                [SetSpec(reps: 10, weightKg: 55)],
                [SetSpec(reps: 8, weightKg: 60)],
              ],
            ),
            RoutineSlot(
              exerciseId: 'incline-press',
              exerciseName: 'Press Inclinado',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 5,
              targetRepsMax: 5,
              targetReps: [5],
              targetWeightKg: 30,
              restSeconds: 60,
              sets: [SetSpec(reps: 5, weightKg: 30)],
              weeklySets: [
                [SetSpec(reps: 5, weightKg: 30)],
                [SetSpec(reps: 6, weightKg: 35)],
              ],
              activeWeeks: [1],
            ),
          ],
        ),
      ],
    );

/// Fills name + split and adds one exercise (via the mocked exercise picker
/// data) to the first day, then sets valid reps on its single default set.
Future<void> _fillMinimalValidForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('routine_editor_name_field')),
    'Fuerza 4x semana',
  );
  await tester.enterText(
    find.byKey(const Key('routine_editor_split_field')),
    'Push/Pull/Legs',
  );

  // El botón RÁPIDO agregó alto arriba de éste y lo empuja abajo del pliegue.
  // Sin traerlo a la vista, el tap "encuentra" el widget y le pega al aire —
  // el hit-test sólo AVISA, no falla, así que el test seguía y explotaba
  // después, en el picker que nunca se abrió.
  await tester.ensureVisible(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar (1)'));
  await tester.pumpAndSettle();
  // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
  // de sets no están en el árbol hasta abrirla.
  await expandirEjercicios(tester);

  // Reps field for the single default set — located via its 'reps' hint
  // (not '.first' on any empty TextFormField, which would also match the
  // adjacent 'kg' weight field).
  await tester.enterText(
    find.ancestor(of: find.text('reps'), matching: find.byType(TextFormField)),
    '10',
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.trainerAssigned,
      ),
    );
  });

  group('RoutineEditorWebScreen — header', () {
    testWidgets('shows the athlete display name', (tester) async {
      await _pumpEditor(tester);
      expect(find.textContaining('Juan Pérez'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — validation', () {
    testWidgets('empty name blocks submit and shows an error', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ponele un nombre a la rutina.'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('empty split blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza',
      );
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Contanos el split (ej: Push/Pull/Legs).'),
        findsOneWidget,
      );
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('a day with no exercise blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'PPL',
      );
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('necesita al menos un ejercicio'),
        findsOneWidget,
      );
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('a set without reps blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'PPL',
      );
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);

      // Reps left empty.
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('tiene una serie sin reps'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });
  });

  group('RoutineEditorWebScreen — days', () {
    testWidgets('agregar día adds a new day card', (tester) async {
      await _pumpEditor(tester);

      expect(find.text('Día 1'), findsOneWidget);
      // Cada día es más alto desde que trae RÁPIDO y el estado vacío, así que
      // este botón cae abajo del pliegue. El hit-test sólo AVISA cuando el tap
      // le pega al aire: sin esto el día no se creaba y el test fallaba después
      // buscando "Día 2", que era el síntoma y no la causa.
      final agregarDia = find.byKey(const Key('routine_editor_add_day_button'));
      await tester.ensureVisible(agregarDia);
      await tester.pumpAndSettle();
      await tester.tap(agregarDia);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Día 2'));
      await tester.pumpAndSettle();
      expect(find.text('Día 2'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — reemplazar ejercicio (in-place)', () {
    // Picks [name] inside the open picker dialog. [query] is a SUBSTRING of the
    // name typed into the search field so the row is on-screen regardless of
    // seed size — it must differ from the full name, otherwise find.text([name])
    // would also match the text the search field now holds. The tap is scoped
    // to the Dialog so it never hits the slot card behind it.
    Future<void> pickInDialog(
      WidgetTester tester,
      String name,
      String query,
    ) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        ),
        query,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text(name)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
    }

    testWidgets('cambia el ejercicio conservando las series ya cargadas', (
      tester,
    ) async {
      await _pumpEditor(tester);

      // Agrega "Press de Banca" y le carga reps 10.
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await pickInDialog(tester, 'Press de Banca', 'Banca');
      await tester.enterText(
        find.ancestor(
          of: find.text('reps'),
          matching: find.byType(TextFormField),
        ),
        '10',
      );
      await tester.pumpAndSettle();

      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);

      // "Cambiar ejercicio" → elegir "Sentadilla con Barra".
      await tester.tap(find.byTooltip('Cambiar ejercicio'));
      await tester.pumpAndSettle();
      await pickInDialog(tester, 'Sentadilla con Barra', 'Sentadilla');

      // El ejercicio cambió en el mismo slot (no se agregó otro) y las reps
      // siguen cargadas: la config sobrevive al swap.
      expect(find.text('Sentadilla con Barra'), findsOneWidget);
      expect(find.text('Press de Banca'), findsNothing);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('elegir el mismo ejercicio es un no-op', (tester) async {
      await _pumpEditor(tester);

      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await pickInDialog(tester, 'Press de Banca', 'Banca');

      await tester.tap(find.byTooltip('Cambiar ejercicio'));
      await tester.pumpAndSettle();
      await pickInDialog(tester, 'Press de Banca', 'Banca');

      // Sigue habiendo un único slot con el mismo ejercicio.
      expect(find.text('Press de Banca'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — borrar ejercicio con scope (Fase 6)', () {
    Future<void> addPressDeBanca(WidgetTester tester) async {
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
    }

    testWidgets('en plan de 1 semana el tacho borra directo, sin diálogo', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      expect(find.text('Press de Banca'), findsOneWidget);

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar ejercicio?'), findsNothing);
      expect(find.text('Press de Banca'), findsNothing);
    });

    testWidgets('en multi-semana el tacho abre el diálogo de scope', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      await tester.tap(find.text('+')); // 2 semanas
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar ejercicio?'), findsOneWidget);
      expect(find.text('Solo esta semana'), findsOneWidget);
      expect(find.text('Todas las semanas'), findsOneWidget);
    });

    testWidgets('"Todas las semanas" elimina el ejercicio por completo', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas las semanas'));
      await tester.pumpAndSettle();

      expect(find.text('Press de Banca'), findsNothing);
    });

    testWidgets(
      '"Solo esta semana" lo conserva y guarda con activeWeeks sin la actual',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        // Llena reps en la semana 1 ANTES de sumar semanas, así la semana 2
        // se siembra con esa prescripción válida (_normalizeSlotWeeks).
        await _fillMinimalValidForm(tester);
        await tester.tap(find.text('+')); // 2 semanas
        await tester.pumpAndSettle();

        // Estamos en la semana 1 (índice 0): "Solo esta semana" la saca.
        await tester.tap(find.byTooltip('Quitar ejercicio'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solo esta semana'));
        await tester.pumpAndSettle();

        // Sigue estando (ahora solo en la semana 2).
        expect(find.text('Press de Banca'), findsOneWidget);

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final routine = verify(() => repo.createAssigned(captureAny()))
            .captured
            .single as Routine;
        expect(routine.days.single.slots.single.activeWeeks, [1]);
      },
    );

    testWidgets(
      '"Solo esta semana" en la última semana presente borra el slot entero',
      (tester) async {
        await _pumpEditor(tester);
        await _fillMinimalValidForm(tester);
        await tester.tap(find.text('+')); // 2 semanas
        await tester.pumpAndSettle();

        // Saca la semana 2 → el ejercicio queda presente SOLO en la semana 1.
        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1')));
        await tester.pumpAndSettle();

        // "Solo esta semana" sobre la única semana presente → borrado real.
        await tester.tap(find.byTooltip('Quitar ejercicio'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solo esta semana'));
        await tester.pumpAndSettle();

        expect(find.text('Press de Banca'), findsNothing);
      },
    );
  });

  group('RoutineEditorWebScreen — validación en vivo (Fase 6)', () {
    Future<void> addPressDeBanca(WidgetTester tester) async {
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
    }

    testWidgets(
      'un ejercicio sin reps muestra el motivo y el hint, y se limpian al cargar',
      (tester) async {
        await _pumpEditor(tester);
        await addPressDeBanca(tester);

        // En vivo, sin apretar Guardar: motivo bajo el ejercicio + hint arriba.
        expect(
          find.text('Falta cargar las reps de una serie.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('invalid_week_hint')), findsOneWidget);

        // Al cargar las reps, ambos desaparecen solos.
        await tester.enterText(
          find.ancestor(
            of: find.text('reps'),
            matching: find.byType(TextFormField),
          ),
          '10',
        );
        await tester.pumpAndSettle();

        expect(find.text('Falta cargar las reps de una serie.'), findsNothing);
        expect(find.byKey(const Key('invalid_week_hint')), findsNothing);
      },
    );

    testWidgets('la pestaña de la semana incompleta muestra el dot de aviso', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);

      // 2 semanas, ambas en blanco (reps vacías) → dot en las dos pestañas.
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('week_tab_warning_0')), findsOneWidget);
      expect(find.byKey(const Key('week_tab_warning_1')), findsOneWidget);

      // Cargar la semana 1 apaga su dot; la semana 2 sigue marcada y el motivo
      // del ejercicio nombra la semana que falta.
      await tester.enterText(
        find.ancestor(
          of: find.text('reps'),
          matching: find.byType(TextFormField),
        ),
        '10',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('week_tab_warning_0')), findsNothing);
      expect(find.byKey(const Key('week_tab_warning_1')), findsOneWidget);
      expect(
        find.text('Falta cargar las reps de una serie (Semana 2).'),
        findsOneWidget,
      );
    });
  });

  group('RoutineEditorWebScreen — submit', () {
    testWidgets(
      'valid form calls createAssigned with a well-formed single-week Routine',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);
        await _fillMinimalValidForm(tester);

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final captured = verify(
          () => repo.createAssigned(captureAny()),
        ).captured;
        final routine = captured.single as Routine;

        expect(routine.name, 'Fuerza 4x semana');
        expect(routine.split, 'Push/Pull/Legs');
        expect(routine.source, RoutineSource.trainerAssigned);
        expect(routine.assignedBy, _trainerId);
        expect(routine.assignedTo, _athleteId);
        // firestore.rules rejects 'public' on a trainer-assigned create — the
        // plan must be private (the model default 'public' would be denied).
        expect(routine.visibility, RoutineVisibility.private);
        expect(routine.numWeeks, 1);
        expect(routine.days, hasLength(1));

        final slot = routine.days.single.slots.single;
        expect(slot.exerciseId, 'bench-press');
        expect(slot.sets, hasLength(1));
        expect(slot.sets.single.reps, 10);
        expect(slot.weeklySets, isEmpty); // single-week → no periodization data
        expect(slot.activeWeeks, isEmpty); // present in all (the only) week
        expect(slot.supersetGroup, isNull);
      },
    );

    testWidgets('repository failure surfaces a retry-friendly error message', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenThrow(Exception('boom'));
      await _pumpEditor(tester, repo: repo);
      await _fillMinimalValidForm(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos guardar la rutina. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });

  // -- Paywall: escritura denegada -----------------------------------------
  //
  // Bajo enforcement, «No pudimos guardar la rutina. Probá de nuevo.» pasa a
  // ser ACTIVAMENTE falso: le pide al PF repetir algo que va a fallar siempre.
  // Estos tests pinean las tres cosas que no pueden romperse — que no se pida
  // reintentar, que no se afirme una causa que no se puede probar, y que el
  // copy no diga nunca que el ALUMNO perdió algo.
  group('RoutineEditorWebScreen — permission-denied al guardar', () {
    /// La denegación real de Firestore, no un `Exception` genérico:
    /// `isPermissionDenied` mira `FirebaseException.code`, así que un doble
    /// más flojo probaría la rama equivocada.
    FirebaseException denied() =>
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

    /// Guarda con el repo tirando `permission-denied`.
    Future<FakeAnalyticsService> pumpAndDeny(
      WidgetTester tester, {
      required BlockedAthletes blocked,
      double textScale = 1.0,
      Size? shrinkTo,
    }) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenThrow(denied());
      final analytics = FakeAnalyticsService();
      await _pumpEditor(
        tester,
        repo: repo,
        analytics: analytics,
        blocked: blocked,
      );
      await _fillMinimalValidForm(tester);
      // El form se llena SIEMPRE en escritorio y a escala 1: el picker de
      // ejercicios es un diálogo que asume ventana ancha, y con el texto al
      // doble su lista deja de ser manejable desde el test. Las condiciones
      // adversas se aplican recién acá, que es cuando importan — lo que se
      // mide es el BANNER, no el picker.
      if (textScale != 1.0) {
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      }
      if (shrinkTo != null) tester.view.physicalSize = shrinkTo;
      if (textScale != 1.0 || shrinkTo != null) await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      return analytics;
    }

    /// EL MENSAJE del banner, por su propia key.
    ///
    /// Antes esto aplanaba todos los `Text` descendientes del banner, y el
    /// texto del link («Ver mis alumnos en solo lectura») entraba en la bolsa.
    /// Con eso, `contains('solo lectura')` lo satisfacía el LINK y
    /// `contains('fuera del cupo de tu plan')` lo satisfacía el FALLBACK: se
    /// podía borrar la rama de causa probada entera y los tests seguían
    /// verdes. El mensaje se mira solo.
    String bannerText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const Key('routine_editor_error_message')))
        .data!;

    testWidgets(
      'con el alumno fuera del cupo, nombra la causa y no pide reintentar',
      (tester) async {
        await pumpAndDeny(
          tester,
          blocked: const BlockedAthletes.published({_athleteId}),
        );

        final text = bannerText(tester);
        // Frases EXCLUSIVAS de la rama probada. La afirmación («este alumno
        // quedó fuera») sólo se hace cuando el backend lo publicó, así que
        // tiene que ser distinguible del hedge del fallback («fijate si quedó
        // fuera»), no un substring compartido con él.
        expect(text, contains('Este alumno quedó fuera del cupo de tu plan'));
        expect(text, contains('Él sigue con sus rutinas'));
        // Y NO el hedge: si las dos ramas dijeran lo mismo, la decisión
        // central del slice sería decorativa.
        expect(text, isNot(contains('Fijate si')));
        // El pecado original: pedir un reintento que no puede funcionar.
        expect(text, isNot(contains('Probá de nuevo')));
      },
    );

    testWidgets(
      'sin el alumno en la lista, NO afirma que la causa sea el plan',
      (tester) async {
        // `isPermissionDenied` no es exclusivo del paywall. Si el backend no
        // publicó a este alumno como fuera de cupo, decirle al PF que es su
        // plan sería inventarle una causa — y lo mandaría a pagar por un bug.
        await pumpAndDeny(
          tester,
          blocked: const BlockedAthletes.published(<String>{}),
        );

        final text = bannerText(tester);
        expect(text, isNot(contains('Este alumno quedó fuera del cupo')));
        expect(text, contains('no tiene permiso'));
        expect(text, contains('Reintentar no lo va a cambiar'));
        // Pero sí lo invita a VERIFICARLO, que es lo único honesto que se
        // puede ofrecer sin saber la causa.
        expect(text, contains('Fijate si quedó fuera del cupo de tu plan'));
      },
    );

    testWidgets('con la lista SIN PUBLICAR tampoco afirma la causa', (
      tester,
    ) async {
      // El backend nunca escribió `blockedAthleteIds` para este PF, así que no
      // se sabe si el alumno está afuera. Es el estado de cualquier PF cuyo
      // padrón y suscripción no se movieron todavía, y colapsarlo en
      // `entitled` diría dos cosas falsas a la vez: al PF, que la causa no es
      // su cupo; y al on-call, que hay una regla rota.
      final analytics = await pumpAndDeny(
        tester,
        blocked: BlockedAthletes.unpublished,
      );

      expect(
        bannerText(tester),
        isNot(contains('Este alumno quedó fuera del cupo')),
      );
      expect(
        analytics.lastPaywallWriteDenied?['athlete_entitlement'],
        'unknown',
      );
    });

    for (final blocked in [
      const BlockedAthletes.published({_athleteId}),
      const BlockedAthletes.published(<String>{}),
    ]) {
      testWidgets(
        'el copy nunca dice que el alumno perdió algo '
        '(blocked: ${blocked.ids.isNotEmpty})',
        (tester) async {
          // La regla de producto: la fricción la come el entrenador, NUNCA el
          // alumno. El alumno conserva rutinas, historial y chat, así que
          // cualquier formulación que sugiera lo contrario es falsa — y es el
          // error más fácil de cometer escribiendo este copy.
          await pumpAndDeny(tester, blocked: blocked);

          final text = bannerText(tester).toLowerCase();
          for (final lie in [
            'sin acceso',
            'perdió',
            'perdio',
            'alumno bloqueado',
            'se elimina',
            'dado de baja',
          ]) {
            expect(text, isNot(contains(lie)), reason: 'copy dice "$lie"');
          }
        },
      );
    }

    testWidgets('emite paywall_write_denied con los campos del incidente', (
      tester,
    ) async {
      final analytics = await pumpAndDeny(
        tester,
        blocked: const BlockedAthletes.published({_athleteId}),
      );

      // Se assertea el MAPA COMPLETO a propósito. Este evento es la única
      // señal server-visible del enforcement (Firestore no loguea las
      // denegaciones de reglas y el Coach Hub web no tiene Crashlytics), así
      // que un campo que se cae en silencio no lo agarra nadie hasta el día
      // del incidente — que es tarde.
      expect(analytics.lastPaywallWriteDenied, {
        // Explícito porque la app nunca llama a setUserId: sin esto no se
        // pueden contar PF únicos ni cruzar contra su subscription.
        'trainer_id': _trainerId,
        'athlete_id': _athleteId,
        'collection': 'routines',
        'operation': 'create',
        'surface': 'routine_editor_web',
        'athlete_entitlement': 'blocked',
      });
    });

    testWidgets(
      "athlete_entitlement es 'entitled' cuando el cupo no lo explica",
      (tester) async {
        final analytics = await pumpAndDeny(
          tester,
          blocked: const BlockedAthletes.published(<String>{}),
        );

        // Es EL campo que separa «problema de cobro» de «regla rota». Si
        // siempre valiera lo mismo, el evento no respondería nada. Y sólo vale
        // `entitled` cuando el backend SÍ publicó la lista y el alumno no
        // figura: ahí la afirmación está probada.
        expect(
          analytics.lastPaywallWriteDenied?['athlete_entitlement'],
          'entitled',
        );
      },
    );

    testWidgets("operation distingue 'update' de 'create'", (tester) async {
      // No es lo mismo no poder tomar trabajo nuevo que no poder tocar lo que
      // ya tenías; lo segundo es mucho más grave.
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'))).thenThrow(denied());
      final analytics = FakeAnalyticsService();
      await _pumpEditor(
        tester,
        repo: repo,
        routineId: 'r1',
        analytics: analytics,
        blocked: const BlockedAthletes.published({_athleteId}),
      );

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(analytics.lastPaywallWriteDenied?['operation'], 'update');
    });

    testWidgets('un fallo genérico no emite el evento ni ofrece la salida', (
      tester,
    ) async {
      // Contra-prueba del gate: si cualquier error disparara el evento, la
      // métrica quedaría inservible el día que haya que leerla.
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenThrow(Exception('boom'));
      final analytics = FakeAnalyticsService();
      await _pumpEditor(
        tester,
        repo: repo,
        analytics: analytics,
        blocked: const BlockedAthletes.published({_athleteId}),
      );
      await _fillMinimalValidForm(tester);
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(analytics.lastPaywallWriteDenied, isNull);
      expect(
        find.text('No pudimos guardar la rutina. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Ver mis alumnos en solo lectura'), findsNothing);
    });

    testWidgets('un error de validación posterior NO arrastra la salida', (
      tester,
    ) async {
      // El doc-comment de `_errorIsDenial` advierte exactamente esto: todo
      // setState que escriba `_errorMessage` tiene que fijar la bandera, o el
      // banner sigue ofreciendo «Ver mis alumnos en solo lectura» para un
      // error que no tiene nada que ver con el cupo — ruido justo en el
      // momento en que el PF necesita leer el error real.
      await pumpAndDeny(
        tester,
        blocked: const BlockedAthletes.published({_athleteId}),
      );
      expect(find.text('Ver mis alumnos en solo lectura'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        '',
      );
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(bannerText(tester), 'Ponele un nombre a la rutina.');
      expect(find.text('Ver mis alumnos en solo lectura'), findsNothing);
    });

    testWidgets('la salida lleva a la pantalla de alumnos en solo lectura', (
      tester,
    ) async {
      await pumpAndDeny(
        tester,
        blocked: const BlockedAthletes.published({_athleteId}),
      );

      await tester.tap(find.text('Ver mis alumnos en solo lectura'));
      await tester.pumpAndSettle();

      expect(find.text('SOLO_LECTURA'), findsOneWidget);
    });

    testWidgets('el banner entra en ventana angosta con textScale 2.0', (
      tester,
    ) async {
      // Hay precedente en este repo de un overflow que ningún test agarró
      // porque todos fijaban un viewport de escritorio. El mensaje de la
      // denegación son tres frases MÁS un link: es el texto más largo que este
      // banner mostró nunca.
      await pumpAndDeny(
        tester,
        blocked: const BlockedAthletes.published({_athleteId}),
        textScale: 2.0,
        shrinkTo: const Size(800, 700),
      );

      expect(
        find.byKey(const Key('routine_editor_error_banner')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // -- Paywall: LECTURA denegada -------------------------------------------
  //
  // La asimetría deliberada del slice, y la rama que más fácil se pierde en un
  // refactor que «unifica el copy de error»: el enforcement frena ESCRITURAS,
  // no lecturas, así que darle copy de paywall a un `permission-denied` de
  // lectura sería inventarle la causa al PF.
  group('RoutineEditorWebScreen — permission-denied al CARGAR', () {
    Future<FakeAnalyticsService> pumpDeniedLoad(WidgetTester tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      final analytics = FakeAnalyticsService();
      await _pumpEditor(
        tester,
        repo: repo,
        routineId: 'r1',
        analytics: analytics,
        blocked: const BlockedAthletes.published({_athleteId}),
      );
      return analytics;
    }

    testWidgets('dice que reintentar no sirve, y no nombra el plan', (
      tester,
    ) async {
      await pumpDeniedLoad(tester);

      expect(
        find.textContaining('no tiene permiso para verla'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reintentar no lo va a cambiar'),
        findsOneWidget,
      );
      // Lo único que se sabe es que el permiso no está. Nombrar el cupo, el
      // plan o facturación sobre una LECTURA sería fabricar la causa.
      for (final invented in ['cupo', 'plan', 'facturación', 'suscripción']) {
        expect(
          find.textContaining(invented),
          findsNothing,
          reason: 'el copy de lectura menciona "$invented"',
        );
      }
      expect(find.text('Ver mis alumnos en solo lectura'), findsNothing);
    });

    testWidgets('no emite paywall_write_denied', (tester) async {
      // Es un evento de ESCRITURA. Contaminarlo con lecturas arruina la
      // métrica el día que haya que leerla, y hoy es la única que existe.
      final analytics = await pumpDeniedLoad(tester);

      expect(analytics.lastPaywallWriteDenied, isNull);
    });

    testWidgets('un fallo genérico de carga sí pide reintentar', (
      tester,
    ) async {
      // Contra-prueba: el mensaje viejo sigue siendo el correcto cuando el
      // reintento SÍ puede funcionar.
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenThrow(Exception('boom'));
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(
        find.text('No pudimos cargar la rutina. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });

  group('RoutineEditorWebScreen — discard guard', () {
    testWidgets('dirty form + back tap shows the discard confirmation', (
      tester,
    ) async {
      await _pumpEditor(tester);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    });

    testWidgets('confirming discard navigates back', (tester) async {
      await _pumpEditor(tester);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza',
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      expect(find.text('AlumnoDetail'), findsOneWidget);
    });

    testWidgets('a pristine form pops immediately without a dialog', (
      tester,
    ) async {
      await _pumpEditor(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('AlumnoDetail'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — edit mode', () {
    testWidgets('loads and populates an existing web-editable routine', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(find.text('Editar rutina'), findsOneWidget); // header
      expect(find.text('Fuerza base'), findsOneWidget); // name field
      expect(find.text('Día A'), findsOneWidget); // day name
      expect(find.text('Press de Banca'), findsOneWidget); // slot
      expect(find.text('Guardar cambios'), findsOneWidget); // submit label
    });

    testWidgets(
      'saving calls updateAssigned on the same doc, not createAssigned',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.getById(any()),
        ).thenAnswer((_) async => _simpleRoutine());
        when(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ),
        ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
        await _pumpEditor(tester, repo: repo, routineId: 'r1');

        await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')),
          'Fuerza v2',
        );
        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final draft = verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ).captured.single as Routine;
        expect(draft.id, 'r1'); // UPDATE on the same document, not a new one
        expect(draft.name, 'Fuerza v2');
        expect(draft.numWeeks, 1);
        verifyNever(() => repo.createAssigned(any()));
      },
    );

    testWidgets('shows a not-found message when the routine is missing', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => null);
      await _pumpEditor(tester, repo: repo, routineId: 'ghost');

      expect(find.text('No encontramos la rutina.'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsNothing);
    });
  });

  group('RoutineEditorWebScreen — rep ranges + notes (Fase 1)', () {
    testWidgets('switching to "Rango" saves a min-max range routine', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Hipertrofia',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'PPL',
      );
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);

      // Toggle to range mode → the set row swaps its 'reps' field for mín/máx.
      await tester.tap(find.text('Rango'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('mín'),
          matching: find.byType(TextFormField),
        ),
        '8',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('máx'),
          matching: find.byType(TextFormField),
        ),
        '12',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final routine = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slot = routine.days.single.slots.single;
      expect(slot.repMode, RepMode.range);
      expect(slot.sets.single.repsMin, 8);
      expect(slot.sets.single.repsMax, 12);
      expect(slot.sets.single.reps, isNull);
    });

    testWidgets('a coaching note is persisted on the slot', (tester) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);
      await _fillMinimalValidForm(tester);

      await tester.enterText(
        find.ancestor(
          of: find.text('Notas para el alumno (opcional)'),
          matching: find.byType(TextFormField),
        ),
        'Bajá despacio la barra',
      );
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final routine = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(routine.days.single.slots.single.notes, 'Bajá despacio la barra');
    });

    testWidgets('invalid range (mín > máx) blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Hipertrofia',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'PPL',
      );
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
      await tester.tap(find.text('Rango'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.ancestor(
          of: find.text('mín'),
          matching: find.byType(TextFormField),
        ),
        '12',
      );
      await tester.enterText(
        find.ancestor(
          of: find.text('máx'),
          matching: find.byType(TextFormField),
        ),
        '8',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('rango de reps inválido'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('edit mode loads a range routine and re-saves it as a range', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _rangeRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r2');

      expect(find.text('Controlá la bajada'), findsOneWidget); // notes loaded
      expect(find.text('12'), findsWidgets); // range max loaded into a field

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      final slot = draft.days.single.slots.single;
      expect(slot.repMode, RepMode.range);
      expect(slot.sets.single.repsMin, 8);
      expect(slot.sets.single.repsMax, 12);
      expect(slot.notes, 'Controlá la bajada');
    });
  });

  group('RoutineEditorWebScreen — duración (Fase 2)', () {
    testWidgets('"Tiempo" saves a duration exercise (seconds, no reps)', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Core',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'Full Body',
      );
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);

      await tester.tap(find.text('Tiempo'));
      await tester.pumpAndSettle();

      // 'seg' (exact) matches only the duration field hint, not 'Descanso (seg)'.
      await tester.enterText(
        find.ancestor(
          of: find.text('seg'),
          matching: find.byType(TextFormField),
        ),
        '60',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final routine = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slot = routine.days.single.slots.single;
      expect(slot.exerciseMode, ExerciseMode.duration);
      expect(slot.sets.single.durationSeconds, 60);
      expect(slot.sets.single.reps, isNull);
    });

    testWidgets('a duration set without seconds blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Core',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'Full Body',
      );
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
      await tester.tap(find.text('Tiempo'));
      await tester.pumpAndSettle();

      // Seconds left empty.
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('sin duración'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets(
      'edit mode loads a duration routine and re-saves it as duration',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.getById(any()),
        ).thenAnswer((_) async => _durationRoutine());
        when(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ),
        ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
        await _pumpEditor(tester, repo: repo, routineId: 'r3');

        expect(find.text('60'), findsWidgets); // seconds loaded into the field
        expect(find.text('reps'), findsNothing); // not in reps mode

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final draft = verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ).captured.single as Routine;
        final slot = draft.days.single.slots.single;
        expect(slot.exerciseMode, ExerciseMode.duration);
        expect(slot.sets.single.durationSeconds, 60);
      },
    );
  });

  group('RoutineEditorWebScreen — supersets (Fase 3)', () {
    testWidgets('unlinking a superset saves both exercises as standalone', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _supersetRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r4');

      // Loaded as a linked superset → toggle it off. ensureVisible because the
      // toggle sits low in a tall form (scrolls off the test viewport).
      await tester.ensureVisible(find.text('En superserie con el siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En superserie con el siguiente'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      final slots = draft.days.single.slots;
      // A lone (unlinked) slot normalizes to a standalone (null group).
      expect(slots[0].supersetGroup, isNull);
      expect(slots[1].supersetGroup, isNull);
    });

    testWidgets('edit mode loads a superset and re-saves it linked', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _supersetRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r4');

      expect(find.text('Press de Banca'), findsOneWidget);
      expect(find.text('Aperturas con Cable'), findsOneWidget);
      // The link is reconstructed and shown as active on the first slot.
      expect(find.text('En superserie con el siguiente'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      final slots = draft.days.single.slots;
      expect(slots[0].supersetGroup, isNotNull);
      expect(slots[0].supersetGroup, slots[1].supersetGroup);
    });
  });

  group('RoutineEditorWebScreen — semanas (Fase 4a)', () {
    testWidgets('the weeks stepper sets numWeeks on create (shared sets)', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      // Fill week 1 FIRST, then bump 1 → 3 weeks: each new week is seeded
      // with a deep copy of the last week's sets (_normalizeSlotWeeks,
      // Fase 4b), so all 3 weeks end up sharing the same reps without
      // touching "Sem 2"/"Sem 3" — every week must carry a valid prescription
      // to save (REQ-PERIOD-016 parity), so bumping weeks before filling any
      // exercise would leave weeks 2-3 blank and block submit.
      await _fillMinimalValidForm(tester);

      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      expect(find.text('3 semanas'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final routine = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(routine.numWeeks, 3);
      // Same prescription every week (copied by the padding above) — still
      // written to weeklySets since numWeeks > 1 (Fase 4b, ADR-PB-03 parity).
      final weeklySets = routine.days.single.slots.single.weeklySets;
      expect(weeklySets, hasLength(3));
      for (final week in weeklySets) {
        expect(week.single.reps, 10);
      }
    });

    testWidgets('the "−" stepper does not go below 1 week', (tester) async {
      await _pumpEditor(tester);

      expect(find.text('1 semana'), findsOneWidget);
      await tester.tap(find.text('−'));
      await tester.pumpAndSettle();
      expect(find.text('1 semana'), findsOneWidget); // clamped at 1
    });

    testWidgets('edit mode loads numWeeks and re-saves it', (tester) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _multiWeekRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r5');

      expect(find.text('4 semanas'), findsOneWidget); // loaded

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      expect(draft.numWeeks, 4);
    });
  });

  group('RoutineEditorWebScreen — prescripción por semana (Fase 4b)', () {
    testWidgets('different reps per week saves weeklySets with 2 entries', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      // Bump 1 → 2 weeks (stepper is near the top, before adding exercises).
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      expect(find.text('2 semanas'), findsOneWidget);

      // Fills the form and sets week 1's (Sem 1) reps to 10.
      await _fillMinimalValidForm(tester);

      // Switch to week 2 and give it a DIFFERENT rep count — only that
      // week's (empty) field renders while "Sem 2" is selected, so the
      // 'reps' hint match stays unique (mirrors _fillMinimalValidForm).
      await tester.ensureVisible(find.text('Sem 2'));
      await tester.tap(find.text('Sem 2'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('reps'),
          matching: find.byType(TextFormField),
        ),
        '6',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final routine = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(routine.numWeeks, 2);
      final slot = routine.days.single.slots.single;
      expect(slot.weeklySets, hasLength(2));
      expect(slot.weeklySets[0].single.reps, 10);
      expect(slot.weeklySets[1].single.reps, 6);
      // Legacy fallback mirrors week 0, mirroring mobile's buildRoutineSlot.
      expect(slot.sets.single.reps, 10);
    });

    testWidgets(
      'edit mode loads a per-week routine and re-saves weeklySets preserved',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.getById(any()),
        ).thenAnswer((_) async => _perWeekRoutine());
        when(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ),
        ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
        await _pumpEditor(tester, repo: repo, routineId: 'r6');

        expect(find.text('2 semanas'), findsOneWidget); // loaded
        expect(find.text('Sem 1'), findsOneWidget);
        expect(find.text('Sem 2'), findsOneWidget);

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final draft = verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ).captured.single as Routine;
        final slot = draft.days.single.slots.single;
        expect(slot.weeklySets, hasLength(2));
        expect(slot.weeklySets[0].single.reps, 10);
        expect(slot.weeklySets[0].single.weightKg, 55);
        expect(slot.weeklySets[1].single.reps, 8);
        expect(slot.weeklySets[1].single.weightKg, 60);
      },
    );
  });

  group('RoutineEditorWebScreen — presencia por semana (Fase 4c)', () {
    testWidgets(
      'excluding week 2 via its presence chip saves activeWeeks: [0]',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        // Fill week 1 FIRST, then bump to 2 weeks — the new week is seeded with
        // a deep copy of week 1's (now-filled) sets (_normalizeSlotWeeks, Fase
        // 4b), so both weeks start with a valid prescription; only the
        // presence mask changes below (bumping first would leave week 2 blank
        // and block submit, mirroring the Fase 4a stepper test).
        await _fillMinimalValidForm(tester);

        await tester.tap(find.text('+'));
        await tester.pumpAndSettle();
        expect(find.text('2 semanas'), findsOneWidget);

        // Exclude week 2 (0-based index 1) via its presence chip.
        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final routine = verify(() => repo.createAssigned(captureAny()))
            .captured
            .single as Routine;
        expect(routine.days.single.slots.single.activeWeeks, [0]);
      },
    );

    testWidgets(
      'a blank week does NOT block submit when the exercise is absent from it',
      (tester) async {
        // Regression: the trainer bumps the week count FIRST and then adds the
        // exercise, so weeks 2..N start blank. Excluding week 2 via its presence
        // chip must let the plan save — those rows are never executed, so
        // demanding reps for them blocked a perfectly valid routine.
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        // Bump FIRST → the exercise added below gets 2 BLANK weeks.
        await tester.tap(find.text('+'));
        await tester.pumpAndSettle();
        expect(find.text('2 semanas'), findsOneWidget);

        // Adds the exercise and fills ONLY week 1's reps — week 2 stays blank.
        await _fillMinimalValidForm(tester);

        // Exclude week 2 (0-based 1): its blank sets must not be validated.
        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final routine = verify(() => repo.createAssigned(captureAny()))
            .captured
            .single as Routine;
        expect(routine.days.single.slots.single.activeWeeks, [0]);
      },
    );

    testWidgets(
      'toggling a week off then back on canonicalizes the mask back to empty (all weeks)',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        await _fillMinimalValidForm(tester);
        await tester.tap(find.text('+'));
        await tester.pumpAndSettle();
        expect(find.text('2 semanas'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1'))); // exclude
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('presence_chip_1')),
        ); // re-include
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final routine = verify(() => repo.createAssigned(captureAny()))
            .captured
            .single as Routine;
        // Covering every week again is canonically "no mask", not [0, 1].
        expect(routine.days.single.slots.single.activeWeeks, isEmpty);
      },
    );

    testWidgets(
      'edit mode loads a presence-masked routine (gate is gone) and re-saves it unchanged',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.getById(any()),
        ).thenAnswer((_) async => _presenceRoutine());
        when(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ),
        ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
        await _pumpEditor(tester, repo: repo, routineId: 'r7');

        // Loads successfully now — the isRoutineWebEditable gate is gone.
        expect(find.textContaining('periodización'), findsNothing);
        expect(find.text('Editar rutina'), findsOneWidget);
        expect(find.text('Con máscara de presencia'), findsOneWidget);
        expect(find.text('Guardar cambios'), findsOneWidget);

        await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
        await tester.pumpAndSettle();

        final draft = verify(
          () => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          ),
        ).captured.single as Routine;
        expect(draft.days.single.slots.single.activeWeeks, [0]);
      },
    );
  });

  group('RoutineEditorWebScreen — SetType round-trip', () {
    testWidgets('re-saving a mobile-authored routine preserves each set type', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _typedSetsRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r8');

      // Touch nothing — just open the plan and hit save, the way a trainer
      // would after glancing at it.
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;

      expect(
        draft.days.single.slots.single.sets.map((s) => s.type).toList(),
        const [SetType.warmup, SetType.normal, SetType.failure],
        reason: 'Opening and re-saving a plan must not silently downgrade '
            'warm-up/failure sets to normal working sets.',
      );
    });

    testWidgets('re-saving a full mobile-authored plan changes nothing at all',
        (
      tester,
    ) async {
      // This is what justifies dropping the isRoutineWebEditable gate: web may
      // open ANY routine only if a no-op edit is provably a no-op on the wire.
      final original = _kitchenSinkRoutine();
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => original);
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r9');

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;

      expect(draft.days, original.days);
    });
  });

  group('RoutineEditorWebScreen — reordenar sin romper superseries', () {
    Future<_MockRoutineRepository> pumpOrderRoutine(WidgetTester tester) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _supersetOrderRoutine());
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r12');
      return repo;
    }

    Future<Routine> save(
      WidgetTester tester,
      _MockRoutineRepository repo,
    ) async {
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      return verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
    }

    testWidgets(
      'moving the last superset member down moves the WHOLE superset',
      (tester) async {
        // Press+Sentadilla are supersetted; Dominadas is alone. A naive
        // position swap would leave Press linked to Dominadas — dragging an
        // unrelated exercise into the superset and evicting Sentadilla.
        final repo = await pumpOrderRoutine(tester);

        final btn = find.byTooltip('Bajar').at(1); // Sentadilla
        await tester.ensureVisible(btn); // 900px-tall viewport: a
        // missed tap only WARNS, it does not fail — the test would
        // silently assert on an untouched routine.
        await tester.tap(btn);
        await tester.pumpAndSettle();

        final slots = (await save(tester, repo)).days.single.slots;

        expect(slots.map((s) => s.exerciseName).toList(), const [
          'Dominadas',
          'Press de Banca',
          'Sentadilla',
        ]);
        expect(
          slots.map((s) => s.supersetGroup).toList(),
          const [null, 1, 1],
          reason: 'Dominadas must stay standalone and the superset intact.',
        );
      },
    );

    testWidgets(
        'moving a standalone exercise up does not absorb it into the '
        'superset above', (tester) async {
      final repo = await pumpOrderRoutine(tester);

      final btn = find.byTooltip('Subir').at(2); // Dominadas
      await tester.ensureVisible(btn); // 900px-tall viewport: a
      // missed tap only WARNS, it does not fail — the test would
      // silently assert on an untouched routine.
      await tester.tap(btn);
      await tester.pumpAndSettle();

      final slots = (await save(tester, repo)).days.single.slots;

      expect(slots.map((s) => s.exerciseName).toList(), const [
        'Dominadas',
        'Press de Banca',
        'Sentadilla',
      ]);
      expect(
        slots.map((s) => s.supersetGroup).toList(),
        const [null, 1, 1],
        reason: 'Dominadas jumped the whole superset, not into it.',
      );
    });

    testWidgets('moving a member INSIDE a superset just reorders it', (
      tester,
    ) async {
      final repo = await pumpOrderRoutine(tester);

      final btn = find.byTooltip('Bajar').at(0); // Press, inside {1}
      await tester.ensureVisible(btn); // 900px-tall viewport: a
      // missed tap only WARNS, it does not fail — the test would
      // silently assert on an untouched routine.
      await tester.tap(btn);
      await tester.pumpAndSettle();

      final slots = (await save(tester, repo)).days.single.slots;

      expect(slots.map((s) => s.exerciseName).toList(), const [
        'Sentadilla',
        'Press de Banca',
        'Dominadas',
      ]);
      expect(
        slots.map((s) => s.supersetGroup).toList(),
        const [1, 1, null],
        reason: 'Swapping two members keeps the group; nothing joins it.',
      );
    });
  });

  group('RoutineEditorWebScreen — copiar semana anterior (Fase 5)', () {
    /// Opens [routine] in edit mode, jumps to week 2, and returns the mock so
    /// the caller can capture the saved draft.
    Future<_MockRoutineRepository> pumpOnWeek2(
      WidgetTester tester,
      Routine routine,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => routine);
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: routine.id);
      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();
      return repo;
    }

    Future<Routine> saveAndCapture(
      WidgetTester tester,
      _MockRoutineRepository repo,
    ) async {
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      return verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
    }

    testWidgets('the button is hidden on week 1 and labelled with the source', (
      tester,
    ) async {
      await _pumpEditor(
        tester,
        repo: (() {
          final r = _MockRoutineRepository();
          when(
            () => r.getById(any()),
          ).thenAnswer((_) async => _twoWeekTypedRoutine());
          return r;
        })(),
        routineId: 'r10',
      );

      // Week 1 is selected by default — nothing to copy from.
      expect(find.byKey(const Key('duplicate_week_button')), findsNothing);

      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('duplicate_week_button')), findsOneWidget);
      expect(find.text('Copiar Sem 1 acá'), findsOneWidget);
    });

    testWidgets('copying carries the set TYPES, not just the numbers', (
      tester,
    ) async {
      final repo = await pumpOnWeek2(tester, _twoWeekTypedRoutine());

      await tester.tap(find.byKey(const Key('duplicate_week_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate_week_confirm_button')));
      await tester.pumpAndSettle();

      final draft = await saveAndCapture(tester, repo);
      final week2 = draft.days.single.slots.single.weeklySets[1];

      expect(week2.map((s) => s.type).toList(), const [
        SetType.warmup,
        SetType.normal,
      ]);
      expect(week2.map((s) => s.reps).toList(), const [12, 8]);
      expect(week2.map((s) => s.weightKg).toList(), const [20.0, 60.0]);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final original = _twoWeekTypedRoutine();
      final repo = await pumpOnWeek2(tester, original);

      await tester.tap(find.byKey(const Key('duplicate_week_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate_week_cancel_button')));
      await tester.pumpAndSettle();

      final draft = await saveAndCapture(tester, repo);
      expect(draft.days, original.days);
    });

    testWidgets(
      'an exercise scheduled ONLY in the target week is dropped, not spread '
      'to every week',
      (tester) async {
        // The deviation from mobile. Mobile empties the mask here, and an empty
        // mask reads as "present in EVERY week" — so a once-scheduled exercise
        // silently lands in the whole plan. Week 1 has no Sentadilla, so after
        // copying week 1 over week 2 nothing does: drop it.
        final repo = await pumpOnWeek2(tester, _presenceDropRoutine());

        await tester.tap(find.byKey(const Key('duplicate_week_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('duplicate_week_confirm_button')),
        );
        await tester.pumpAndSettle();

        final draft = await saveAndCapture(tester, repo);
        final slots = draft.days.single.slots;

        expect(
          slots.map((s) => s.exerciseName).toList(),
          const ['Press de Banca', 'Dominadas'],
          reason: 'Sentadilla lived only in week 2; copying week 1 over it '
              'leaves it scheduled nowhere.',
        );
        expect(
          slots.every((s) => s.activeWeeks.isEmpty),
          isTrue,
          reason: 'No survivor should have inherited a stale mask.',
        );
      },
    );

    testWidgets('dropping a superset member does not re-link the survivors', (
      tester,
    ) async {
      // Press+Sentadilla were the superset; Dominadas stood alone. Evicting
      // Sentadilla must leave Press alone too — NOT supersetted with
      // Dominadas, which `linkedToNext` would do since it links by position.
      final repo = await pumpOnWeek2(tester, _presenceDropRoutine());

      await tester.tap(find.byKey(const Key('duplicate_week_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate_week_confirm_button')));
      await tester.pumpAndSettle();

      final draft = await saveAndCapture(tester, repo);

      expect(
        draft.days.single.slots.map((s) => s.supersetGroup).toList(),
        const [null, null],
      );
    });
  });

  group('RoutineEditorWebScreen — series tipadas (warm-up/drop/al-fallo)', () {
    Future<_MockRoutineRepository> pump(
      WidgetTester tester,
      Routine routine,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => routine);
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: routine.id);
      return repo;
    }

    Future<Routine> save(
      WidgetTester tester,
      _MockRoutineRepository repo,
    ) async {
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      return verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
    }

    testWidgets(
      'tapping the chip and picking "Entrada en calor" saves warmup',
      (tester) async {
        final repo = await pump(tester, _simpleRoutine());

        await tester.tap(find.byType(PopupMenuButton<SetType>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Entrada en calor (W)'));
        await tester.pumpAndSettle();

        final slot = (await save(tester, repo)).days.single.slots.single;
        expect(slot.sets.single.type, SetType.warmup);
      },
    );

    testWidgets('a warm-up does not consume a set number (running relabel)', (
      tester,
    ) async {
      // Two normal sets show "1" and "2". Marking the first as warm-up must
      // renumber the second to "1" — the glyph replaces the count, it doesn't
      // shift it.
      final repo = await pump(tester, _twoNormalSetsRoutine());
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<SetType>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Al fallo (F)'));
      await tester.pumpAndSettle();

      // First chip now shows 'F'; the second normal set is renumbered to '1'.
      expect(find.text('F'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      // And it round-trips.
      final sets = (await save(tester, repo)).days.single.slots.single.sets;
      expect(sets.map((s) => s.type).toList(), const [
        SetType.failure,
        SetType.normal,
      ]);
    });

    testWidgets('a failure set with no reps still saves (reps are optional)', (
      tester,
    ) async {
      // The whole point of "al fallo": the athlete works to failure, so the
      // reps-completeness validation must skip it instead of blocking submit.
      final repo = await pump(tester, _failureSetRoutine());

      final slot = (await save(tester, repo)).days.single.slots.single;
      expect(slot.sets.single.type, SetType.failure);
      expect(slot.sets.single.reps, isNull);
    });
  });

  group('RoutineEditorWebScreen — modo plantilla', () {
    // Pumps the editor in TEMPLATE mode (no athlete). With [templateId] the
    // edit route is pushed; without it, the create route.
    Future<void> pumpTemplate(
      WidgetTester tester, {
      RoutineRepository? repo,
      String? templateId,
      FakeAnalyticsService? analytics,
      BlockedAthletes? blocked,
    }) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/biblioteca',
        routes: [
          GoRoute(
            path: '/biblioteca',
            builder: (_, __) => const Scaffold(body: Text('Biblioteca')),
          ),
          GoRoute(
            path: '/template-editor',
            builder: (_, __) =>
                const Scaffold(body: RoutineEditorWebScreen.template()),
          ),
          GoRoute(
            path: '/template-editor/:templateId',
            builder: (_, state) => Scaffold(
              body: RoutineEditorWebScreen.template(
                routineId: state.pathParameters['templateId'],
              ),
            ),
          ),
          // Registrada para que el test de denegación pueda probar que el
          // banner NO ofrece esta salida en modo plantilla: sin la ruta, un
          // push accidental moriría contra go_router y el fallo se leería como
          // un problema de routing en vez de como lo que es.
          GoRoute(
            path: kBlockedStudentsRoutePath,
            builder: (_, __) => const Scaffold(body: Text('SOLO_LECTURA')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides:
              _overrides(repo: repo, analytics: analytics, blocked: blocked),
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.push(
        templateId == null
            ? '/template-editor'
            : '/template-editor/$templateId',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('una denegación en plantilla no inventa un alumno', (
      tester,
    ) async {
      // Una plantilla no es de nadie: el paywall es POR ALUMNO, así que el
      // cupo no puede ser la causa. Si esta rama se cae, la denegación de una
      // plantilla pasa a decir «tu cuenta no tiene permiso para escribir sobre
      // este alumno» y «fijate si quedó fuera del cupo de tu plan» — sobre un
      // alumno que no existe. Es exactamente la causa inventada que el slice
      // dice no cometer, en el único lugar donde no hay ningún dato que la
      // pueda sostener.
      final repo = _MockRoutineRepository();
      when(() => repo.createTemplate(any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      final analytics = FakeAnalyticsService();
      await pumpTemplate(tester, repo: repo, analytics: analytics);

      await _fillMinimalValidForm(tester);
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final text = tester
          .widget<Text>(find.byKey(const Key('routine_editor_error_message')))
          .data!;
      expect(text, contains('no tiene permiso para escribirla'));
      expect(text, contains('Reintentar no lo va a cambiar'));
      expect(text, isNot(contains('alumno')));
      expect(text, isNot(contains('cupo')));
      // Y sin salida a una pantalla que lista alumnos: acá no hay ninguno.
      expect(find.text('Ver mis alumnos en solo lectura'), findsNothing);

      // `not_applicable` y no `unknown`: no es que no se sepa el entitlement,
      // es que el campo no aplica. Un pico de `unknown` significa otra cosa
      // (el backend no publicó la lista) y confundirlos arruina la lectura.
      expect(
        analytics.lastPaywallWriteDenied?['athlete_entitlement'],
        'not_applicable',
      );
      expect(analytics.lastPaywallWriteDenied?['athlete_id'], 'none');
    });

    testWidgets('header reads "Nueva plantilla" and names no athlete', (
      tester,
    ) async {
      await pumpTemplate(tester);

      expect(find.text('Nueva plantilla'), findsOneWidget);
      expect(find.text('Plantilla reutilizable, sin alumno'), findsOneWidget);
      expect(find.textContaining('Para '), findsNothing);
    });

    testWidgets('creating saves via createTemplate with the template shape', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createTemplate(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await pumpTemplate(tester, repo: repo);

      await _fillMinimalValidForm(tester);
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final t = verify(() => repo.createTemplate(captureAny())).captured.single
          as Routine;
      expect(t.source, RoutineSource.trainerTemplate);
      expect(t.assignedTo, isNull);
      expect(t.visibility, RoutineVisibility.private);
      expect(t.assignedBy, _trainerId);
      // Never the assigned path.
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('editing saves via updateTemplate, never updateAssigned', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _templateRoutine());
      when(
        () => repo.updateTemplate(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await pumpTemplate(tester, repo: repo, templateId: 't1');

      expect(find.text('Editar plantilla'), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateTemplate(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      expect(draft.id, 't1');
      expect(draft.source, RoutineSource.trainerTemplate);
      verifyNever(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      );
    });
  });

  // ── Resumen en criollo (#648) ────────────────────────────────────────────
  //
  // Both modes of this screen are PF modes, so unlike mobile there is no
  // "the athlete must not see it" case to assert here — that gate lives in
  // test/features/workout/presentation/routine_editor_summary_test.dart,
  // against RoutineEditorScreen.
  group('RoutineEditorWebScreen — resumen (#648)', () {
    const resumen =
        'Empujar, tirar y piernas: cada día trabajás un tipo de movimiento '
        'distinto.';
    final summaryField = find.byKey(const Key('routine_editor_summary_field'));

    testWidgets('renders with a label and a plain-language explanation',
        (tester) async {
      await _pumpEditor(tester);

      expect(summaryField, findsOneWidget);
      expect(find.text('RESUMEN'), findsOneWidget);
      expect(
        find.text(
          'Una frase que explique qué es la rutina, para alguien que nunca '
          'pisó un gimnasio.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('caps input at 280 characters and shows a live counter',
        (tester) async {
      await _pumpEditor(tester);

      expect(find.text('0/280'), findsOneWidget);

      await tester.enterText(summaryField, 'A' * 400);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(summaryField);
      expect(field.maxLength, 280);
      expect(field.controller!.text.length, 280);
      expect(find.text('280/280'), findsOneWidget);
    });

    testWidgets('saves the trimmed resumen on a new assigned routine',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer(
        (i) async => (i.positionalArguments.first as Routine).copyWith(id: 'x'),
      );
      await _pumpEditor(tester, repo: repo);

      await _fillMinimalValidForm(tester);
      await tester.enterText(summaryField, '  $resumen  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final saved = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(saved.summary, resumen);
    });

    testWidgets(
        'is OPTIONAL — a routine saved with the field blank persists '
        'summary: null, not an empty string', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer(
        (i) async => (i.positionalArguments.first as Routine).copyWith(id: 'x'),
      );
      await _pumpEditor(tester, repo: repo);

      // Resumen deliberately left untouched — the save must still go through.
      await _fillMinimalValidForm(tester);
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final saved = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(saved.summary, isNull);
      expect(saved.name, 'Fuerza 4x semana');
    });

    testWidgets('whitespace-only input saves as null', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer(
        (i) async => (i.positionalArguments.first as Routine).copyWith(id: 'x'),
      );
      await _pumpEditor(tester, repo: repo);

      await _fillMinimalValidForm(tester);
      await tester.enterText(summaryField, '   ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final saved = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(saved.summary, isNull);
    });

    testWidgets('hydrates an existing resumen and round-trips it on save',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r1')).thenAnswer(
        (_) async => _simpleRoutine().copyWith(summary: resumen),
      );
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);

      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      final field = tester.widget<TextField>(summaryField);
      expect(field.controller!.text, resumen);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      expect(draft.summary, resumen);
    });

    testWidgets('an emptied field clears the resumen on an existing routine',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r1')).thenAnswer(
        (_) async => _simpleRoutine().copyWith(summary: resumen),
      );
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);

      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      await tester.enterText(summaryField, '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
      expect(draft.summary, isNull);
    });
  });

  // Issue #655 — el editor web gana "copiar prescripción entre ejercicios",
  // el único de los tres atajos de #640 que rinde igual con teclado físico.
  //
  // Cubre el contrato (copia profunda de la semana visible, arrastra el modo,
  // NO toca presencia ni otras semanas ni el descanso) y —lo que en web es
  // propio— que los campos EN PANTALLA muestren lo copiado: las filas de set
  // son stateless con `TextFormField(initialValue:)`, así que sin la
  // ObjectKey la copia se vería como un no-op hasta guardar.
  group('RoutineEditorWebScreen — copiar prescripción entre ejercicios (#655)',
      () {
    const copyTooltip = 'Copiar sets del anterior';

    Finder copyButtons() => find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == copyTooltip,
        );

    List<IconButton> copyButtonsOf(WidgetTester tester) =>
        tester.widgetList<IconButton>(copyButtons()).toList();

    /// Text the trainer actually SEES in the n-th field carrying [hint] —
    /// read off the controller of the [TextField] that [TextFormField] builds,
    /// not off the model.
    String fieldText(WidgetTester tester, String hint, int n) => tester
        .widget<TextField>(
          find
              .byWidgetPredicate(
                (w) => w is TextField && w.decoration?.hintText == hint,
              )
              .at(n),
        )
        .controller!
        .text;

    Future<_MockRoutineRepository> pump(
      WidgetTester tester,
      Routine routine,
    ) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => routine);
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: routine.id);
      // Every fixture here has TWO exercises, and the second card's header —
      // where the copy button lives — sits past 1100px. The form scrolls in
      // the real app; in the harness a taller viewport is cheaper than
      // scrolling before every tap. `_pumpEditor` already registered the
      // teardown that resets this.
      tester.view.physicalSize = const Size(1400, 1800);
      await tester.pumpAndSettle();
      return repo;
    }

    Future<Routine> saveAndCapture(
      WidgetTester tester,
      _MockRoutineRepository repo,
    ) async {
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      return verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
    }

    Future<void> copyInto(WidgetTester tester, int slotIndex) async {
      await tester.tap(copyButtons().at(slotIndex));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('copy_prescription_confirm_button')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'el botón se ofrece en todos los ejercicios y está deshabilitado en '
        'el primero del día', (tester) async {
      await pump(tester, _copyPrescriptionRoutine());

      final buttons = copyButtonsOf(tester);
      expect(buttons, hasLength(2), reason: 'siempre visible = descubrible');
      expect(
        buttons[0].onPressed,
        isNull,
        reason: 'no hay ejercicio anterior del cual copiar',
      );
      expect(buttons[1].onPressed, isNotNull);
    });

    testWidgets('copia los sets del anterior, con sus tipos', (tester) async {
      final repo = await pump(tester, _copyPrescriptionRoutine());

      await copyInto(tester, 1);

      final slots = (await saveAndCapture(tester, repo)).days.single.slots;
      expect(slots[1].sets.map((s) => s.reps).toList(), const [12, 8]);
      expect(slots[1].sets.map((s) => s.weightKg).toList(), const [20.0, 60.0]);
      expect(
        slots[1].sets.map((s) => s.type).toList(),
        const [SetType.warmup, SetType.normal],
      );
      expect(slots[0].sets.map((s) => s.reps).toList(), const [12, 8],
          reason: 'la fuente no se toca');
    });

    testWidgets('no copia identidad, descanso ni notas — sólo la grilla',
        (tester) async {
      final repo = await pump(tester, _copyPrescriptionRoutine());

      await copyInto(tester, 1);

      final target = (await saveAndCapture(tester, repo)).days.single.slots[1];
      expect(target.exerciseName, 'Press Inclinado');
      expect(target.restSeconds, 60, reason: 'el descanso del destino sigue');
      expect(target.notes, isNull);
    });

    testWidgets(
        'los campos en pantalla muestran lo copiado, no los valores viejos',
        (tester) async {
      // La regresión propia de web: la fila de set es stateless y su
      // TextFormField siembra el texto UNA sola vez. Si la fila no se
      // reconstruye, el modelo cambia y la pantalla miente.
      await pump(tester, _copyPrescriptionRoutine());
      expect(fieldText(tester, 'reps', 2), '5');
      expect(fieldText(tester, 'kg', 2), '30.0');

      await copyInto(tester, 1);

      expect(fieldText(tester, 'reps', 2), '12');
      expect(fieldText(tester, 'reps', 3), '8');
      expect(fieldText(tester, 'kg', 2), '20.0');
      expect(fieldText(tester, 'kg', 3), '60.0');
    });

    testWidgets('cancelar no cambia nada', (tester) async {
      final repo = await pump(tester, _copyPrescriptionRoutine());

      await tester.tap(copyButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('copy_prescription_cancel_button')),
      );
      await tester.pumpAndSettle();

      expect(fieldText(tester, 'reps', 2), '5');
      final target = (await saveAndCapture(tester, repo)).days.single.slots[1];
      expect(target.sets.map((s) => s.reps).toList(), const [5]);
    });

    testWidgets('arrastra el modo de medición (TIEMPO) al destino',
        (tester) async {
      final repo = await pump(tester, _copyModeRoutine());

      await copyInto(tester, 1);

      // El destino dejó de mostrar REPS/KG: ahora pide segundos.
      expect(fieldText(tester, 'seg', 1), '45');

      final target = (await saveAndCapture(tester, repo)).days.single.slots[1];
      expect(target.exerciseMode, ExerciseMode.duration);
      expect(target.sets.single.durationSeconds, 45);
    });

    testWidgets('no toca la presencia semanal ni las otras semanas',
        (tester) async {
      final repo = await pump(tester, _copyPerWeekRoutine());
      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();

      await copyInto(tester, 1);

      final target = (await saveAndCapture(tester, repo)).days.single.slots[1];
      expect(target.weeklySets[1].map((s) => s.reps).toList(), const [8]);
      expect(
        target.weeklySets[0].map((s) => s.reps).toList(),
        const [5],
        reason: 'copiar actúa sobre la semana visible, como "Copiar Sem N acá"',
      );
      expect(
        target.activeWeeks,
        const [1],
        reason: 'la presencia es ortogonal a la prescripción (ADR-WPRES)',
      );
    });

    testWidgets(
        'está deshabilitado sobre un ejercicio ausente de la semana vista',
        (tester) async {
      // Web atenúa las tarjetas ausentes en vez de esconderlas como mobile,
      // así que el botón es alcanzable sobre un ejercicio que esa semana no
      // tiene prescripción visible que pisar.
      await pump(tester, _copyPerWeekRoutine());
      expect(copyButtonsOf(tester)[1].onPressed, isNull);

      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();
      expect(copyButtonsOf(tester)[1].onPressed, isNotNull);
    });
  });

  group('RoutineEditorWebScreen — entrada rápida', () {
    testWidgets('escribir la línea entra con la prescripción parseada',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => null);
      when(() => repo.createAssigned(any()))
          .thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Plan rápido',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'Full body',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RÁPIDO'));
      await tester.pumpAndSettle();

      // La sintaxis REAL del parser, la misma que el onboarding enseña:
      // 4 series de 10 con 55 kg, escrito en una línea.
      await tester.enterText(
        find.byKey(const Key('quick_entry_field')),
        'Press de Banca 4x10 55',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_entry_confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      final draft = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slot = draft.days.single.slots.single;
      expect(slot.exerciseName, 'Press de Banca');
      expect(slot.sets, hasLength(4),
          reason: '4x10 son CUATRO series, no una');
      expect(slot.sets.every((s) => s.reps == 10), isTrue);
      expect(slot.sets.every((s) => s.weightKg == 55), isTrue);
    });
  });

  group('RoutineEditorWebScreen — la superserie se ve como un grupo', () {
    testWidgets('dos ejercicios enlazados quedan dentro de UN bloque',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any()))
          .thenAnswer((_) async => _supersetRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      // Este test no existía, y su ausencia dejó pasar una regresión real: al
      // mover la card a `ExerciseCard` desapareció el borde teñido que era la
      // ÚNICA marca de agrupación en la web. Compiló y pasaron 3133 tests.
      expect(
        find.byKey(const Key('superset_block_header')),
        findsOneWidget,
        reason: 'un grupo, un encabezado',
      );
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      expect(
        find
            .descendant(
              of: find.byType(SupersetBlock),
              matching: find.byType(ExerciseCard),
            )
            .evaluate()
            .length,
        2,
        reason: 'los DOS miembros van adentro del bloque',
      );
    });

    testWidgets('un ejercicio suelto NO queda en un bloque', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(find.byType(SupersetBlock), findsNothing);
      expect(find.text('A1'), findsNothing);
    });
  });
}
