// Tests for RoutineEditorWebScreen — web MVP routine editor (create-only,
// single week, normal sets). Mirrors the mocking pattern of
// routine_editor_athlete_mode_test.dart (mobile).

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:treino/core/widgets/treino_icon.dart';
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
import 'package:treino/features/coach_hub/presentation/widgets/exercise_picker_dialog.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/blocked_students_screen.dart'
    show kBlockedStudentsRoutePath;
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart'
    show routinesAuthoredByProvider;
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
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/coach_hub/application/picker_panel_width_provider.dart';

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
/// [f] pero SÓLO dentro del formulario del editor, nunca en el panel lateral.
///
/// Desde el #860 el panel está siempre abierto en desktop y lista el catálogo
/// completo, así que `find.text('Press de Banca')` matchea dos veces: la fila
/// del panel y la card del día. Lo mismo con los nombres de día, que el panel
/// repite como chips de destino. Todo lo que mire LA RUTINA scopea acá.
Finder enElEditor(Finder f) => find.descendant(
      of: find.byKey(const Key('routine_editor_form')),
      matching: f,
    );

/// Tilda [nombre] en la lista del panel lateral.
///
/// El panel es de alto fijo y la fila puede caer abajo del pliegue: el
/// hit-test sólo AVISA cuando el tap le pega al aire, así que sin el
/// `ensureVisible` la selección no pasa y el test muere más adelante.
Future<void> _elegirEnPanel(WidgetTester tester, String nombre) async {
  final fila = find.descendant(
    of: find.byType(ExercisePickerPanel),
    matching: find.text(nombre),
  );
  await tester.ensureVisible(fila);
  await tester.pumpAndSettle();
  await tester.tap(fila);
  await tester.pumpAndSettle();
}

/// Suma una semana Y le copia la anterior, dejando las dos cargadas.
///
/// Desde que la semana nueva nace PELADA, un `tap('+')` pelado ya no deja un
/// plan de dos semanas con contenido en ambas: deja la segunda vacía. Los
/// tests que necesitan las dos llenas —prescripción por semana, chips de
/// presencia, el dot de validación— pasan por acá, que es el camino que el PF
/// hace ahora: sumar y copiar, dos actos explícitos.
///
/// Sumar auto-navega a la semana nueva, así que el destino de la copia ya es
/// la correcta y la fuente es la única otra (no hay selector con dos semanas).
Future<void> _agregarSemanaCopiandoLaAnterior(WidgetTester tester) async {
  await tester.tap(find.text('+'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('duplicate_week_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('duplicate_week_confirm_button')));
  await tester.pumpAndSettle();
}

/// Stand-in de la sección Rutinas: lo único que hace es WATCHEAR
/// `routinesAuthoredByProvider`, que es lo que esa pantalla hace de verdad.
class _EspiaDelListado extends ConsumerWidget {
  const _EspiaDelListado();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(routinesAuthoredByProvider(_trainerId));
    return const Text('AlumnoDetail');
  }
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  RoutineRepository? repo,
  String? routineId,
  FakeAnalyticsService? analytics,
  BlockedAthletes? blocked,
  List<Override> extraOverrides = const [],
  bool observarListadoDeRutinas = false,
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
        // Con `observarListadoDeRutinas`, la pantalla de atrás WATCHEA
        // `routinesAuthoredByProvider` — igual que la sección Rutinas real.
        // Hace falta que alguien lo watchee para que la invalidación del
        // editor sea observable: es `autoDispose`, y `invalidate` sobre un
        // provider que nadie escucha no hace nada visible.
        builder: (_, __) => observarListadoDeRutinas
            ? const Scaffold(body: _EspiaDelListado())
            : const Scaffold(body: Text('AlumnoDetail')),
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
      overrides: [
        ..._overrides(repo: repo, analytics: analytics, blocked: blocked),
        ...extraOverrides,
      ],
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

  // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
  // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
  await tester.tap(find.text('Press de Banca'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar (1)'));
  await tester.pumpAndSettle();
  // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
  // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
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

/// Aprieta «Guardar cambios» y atraviesa el diálogo de guardar-o-copiar.
///
/// Ese diálogo sale al guardar una rutina que YA EXISTE y tiene cambios: es la
/// metáfora de editar una foto que pidió el PF —«o se te guarda con los
/// cambios, o te crea una copia manteniendo la original»—. Está en el camino de
/// toda edición, así que está en el camino de casi todos los tests de esta
/// suite, y elegir «Guardar» es lo que todos ellos ya asumían.
///
/// El `if` no es defensivo por las dudas: los tests de creación —y los que
/// aprietan Guardar esperando un error de validación— no lo ven, y tienen que
/// seguir funcionando por el mismo camino.
///
/// `find.text` es exacto, así que «Guardar» no matchea «Guardar cambios» del
/// botón de la pantalla. Si algún día matcheara, este helper se comería su
/// propio tap y los tests pasarían sin guardar nada.
Future<void> _tapGuardar(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
  await tester.pumpAndSettle();

  final elegirPisar = find.text('Guardar');
  if (elegirPisar.evaluate().isNotEmpty) {
    await tester.tap(elegirPisar.last);
    await tester.pumpAndSettle();
  }
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);

      // Reps left empty.
      await _tapGuardar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('tiene una serie sin reps'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });
  });

  group('RoutineEditorWebScreen — days', () {
    testWidgets('agregar día adds a new day card', (tester) async {
      await _pumpEditor(tester);

      expect(enElEditor(find.text('Día 1')), findsOneWidget);
      // Cada día es más alto desde que trae RÁPIDO y el estado vacío, así que
      // este botón cae abajo del pliegue. El hit-test sólo AVISA cuando el tap
      // le pega al aire: sin esto el día no se creaba y el test fallaba después
      // buscando "Día 2", que era el síntoma y no la causa.
      final agregarDia = find.byKey(const Key('routine_editor_add_day_button'));
      await tester.ensureVisible(agregarDia);
      await tester.pumpAndSettle();
      await tester.tap(agregarDia);
      await tester.pumpAndSettle();

      await tester.ensureVisible(enElEditor(find.text('Día 2')));
      await tester.pumpAndSettle();
      expect(enElEditor(find.text('Día 2')), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — el lápiz de «Cambiar ejercicio» NO está', () {
    // Lo sacó el PF: «este modal que se abre cuando toco editar ejercicio,
    // vamos a sacar el lápiz de ahí, no me parece 100% útil».
    //
    // Y tenía un motivo visible: en desktop el picker YA vive en el panel
    // lateral, siempre abierto (#860). El lápiz abría el MISMO picker como
    // modal ENCIMA del panel — dos «Elegir ejercicios» en pantalla a la vez,
    // que es lo que muestra su captura.
    //
    // Lo que se va con él: cambiar un ejercicio conservando sus series,
    // descanso, notas y enlace de superserie. Sin el lápiz eso es borrar y
    // volver a agregar, y la configuración se pierde. Queda anotado acá para
    // que la próxima persona sepa que fue una decisión y no un descuido.

    testWidgets('la card no ofrece cambiar el ejercicio', (tester) async {
      await _pumpEditor(tester);
      await _elegirEnPanel(tester, 'Press de Banca');
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
      expect(find.byTooltip('Cambiar ejercicio'), findsNothing);
    });
  });
  group('RoutineEditorWebScreen — borrar ejercicio con scope (Fase 6)', () {
    Future<void> addPressDeBanca(WidgetTester tester) async {
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
    }

    testWidgets('en plan de 1 semana el tacho borra directo, sin diálogo', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();

      expect(find.text('¿Eliminar ejercicio?'), findsNothing);
      expect(enElEditor(find.text('Press de Banca')), findsNothing);
    });

    testWidgets('en multi-semana el tacho abre el diálogo de scope', (
      tester,
    ) async {
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      // Sumar + copiar: la semana nueva nace pelada, así que sin la copia la
      // Semana 2 no tendría el ejercicio y no habría tacho que tocar.
      await _agregarSemanaCopiandoLaAnterior(tester);

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
      await _agregarSemanaCopiandoLaAnterior(tester);

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todas las semanas'));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsNothing);
    });

    testWidgets(
      '"Solo esta semana" lo conserva y guarda con activeWeeks sin la actual',
      (tester) async {
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        // Llena reps en la semana 1 ANTES de sumar, y después COPIA: la
        // semana nueva nace pelada, la copia le lleva ejercicio y prescripción.
        await _fillMinimalValidForm(tester);
        await _agregarSemanaCopiandoLaAnterior(tester);

        // Copiar deja parado en la semana 2; se vuelve a la 1, que es de la
        // que este test saca el ejercicio.
        await tester.tap(find.byKey(const Key('week_tab_0')));
        await tester.pumpAndSettle();

        // Estamos en la semana 1 (índice 0): "Solo esta semana" la saca.
        await tester.tap(find.byTooltip('Quitar ejercicio'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solo esta semana'));
        await tester.pumpAndSettle();

        // Se fue DE ESTA SEMANA. Antes se quedaba atenuado acá y el PF lo leía
        // como «le di borrar y no se fue»; ahora desaparece de la semana de la
        // que se lo sacó, que es lo que la palabra "borrar" promete.
        expect(enElEditor(find.text('Press de Banca')), findsNothing);

        // Pero sigue en la rutina: en la semana 2 está intacto. Esta mitad es
        // la que separa "lo saqué de una semana" de "lo borré de todas".
        await tester.tap(find.byKey(const Key('week_tab_1')));
        await tester.pumpAndSettle();
        expect(enElEditor(find.text('Press de Banca')), findsOneWidget);

        await _tapGuardar(tester);
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
        await _agregarSemanaCopiandoLaAnterior(tester);
        await tester.tap(find.byKey(const Key('week_tab_0')));
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

        expect(enElEditor(find.text('Press de Banca')), findsNothing);
      },
    );
  });

  group('RoutineEditorWebScreen — validación en vivo (Fase 6)', () {
    Future<void> addPressDeBanca(WidgetTester tester) async {
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
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

      // 2 semanas con el MISMO ejercicio, ambas en blanco (reps vacías) → dot
      // en las dos pestañas. Se copia porque la semana nueva nace pelada: sin
      // la copia, el dot de la Semana 2 sería por estar vacía y este test
      // mide otra cosa, que le falten las reps.
      await _agregarSemanaCopiandoLaAnterior(tester);
      expect(find.byKey(const Key('week_tab_warning_0')), findsOneWidget);
      expect(find.byKey(const Key('week_tab_warning_1')), findsOneWidget);

      // Cargar la semana 1 apaga su dot; la semana 2 sigue marcada y el motivo
      // del ejercicio nombra la semana que falta.
      await tester.tap(find.byKey(const Key('week_tab_0')));
      await tester.pumpAndSettle();
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

    testWidgets('una semana SIN ejercicios también marca el dot',
        (tester) async {
      // Causa nueva del dot. Antes no podía pasar —la semana nueva heredaba el
      // plan entero—, pero desde que nace pelada es el estado inicial de toda
      // semana agregada, y una semana en la que el alumno no tiene nada que
      // hacer no puede pasar desapercibida.
      await _pumpEditor(tester);
      await addPressDeBanca(tester);
      await tester.enterText(
        find.ancestor(
          of: find.text('reps'),
          matching: find.byType(TextFormField),
        ),
        '10',
      );
      await tester.pumpAndSettle();
      // Semana 1 completa: sin dot.
      expect(find.byKey(const Key('week_tab_warning_0')), findsNothing);

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      // La 1 sigue limpia; la 2 nace pelada y avisa.
      expect(find.byKey(const Key('week_tab_warning_0')), findsNothing);
      expect(find.byKey(const Key('week_tab_warning_1')), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — la semana nueva nace PELADA', () {
    // El PF: «cuando agrego una semana nueva, automáticamente viene copiada de
    // la anterior y siempre se mueven en conjunto — si agrego un ejercicio en
    // una, se agrega solo en la otra».
    //
    // Las dos mitades tenían la misma causa: una máscara de presencia VACÍA
    // significa "en todas las semanas", y tanto los slots viejos al crecer el
    // plan como los slots recién dados de alta la tenían vacía. Ahora la
    // semana nueva nace sin nadie, y un alta entra sólo donde se la agrega.

    testWidgets('sumar una semana no arrastra los ejercicios', (tester) async {
      await _pumpEditor(tester);
      await _fillMinimalValidForm(tester);
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);

      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      // Sumar salta a la semana nueva, que está vacía.
      expect(find.text('2 semanas'), findsOneWidget);
      expect(enElEditor(find.text('Press de Banca')), findsNothing);

      // Y la semana 1 quedó intacta: pelada no es "se borró".
      await tester.tap(find.byKey(const Key('week_tab_0')));
      await tester.pumpAndSettle();
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('un alta entra SÓLO en la semana que se está mirando',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.createAssigned(any()),
      ).thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await _fillMinimalValidForm(tester); // Press de Banca en la Semana 1
      await tester.tap(find.text('+')); // salta a la Semana 2, pelada
      await tester.pumpAndSettle();

      // Agrega OTRO ejercicio, parado en la Semana 2.
      await _elegirEnPanel(tester, 'Peso Muerto');
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      expect(enElEditor(find.text('Peso Muerto')), findsOneWidget);

      // La Semana 1 NO se enteró. Ésta es la queja textual del PF.
      await tester.tap(find.byKey(const Key('week_tab_0')));
      await tester.pumpAndSettle();
      expect(enElEditor(find.text('Peso Muerto')), findsNothing);
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('con más de dos semanas, copiar PREGUNTA de cuál',
        (tester) async {
      await _pumpEditor(tester);
      await _fillMinimalValidForm(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+')); // 3 semanas, parado en la 3
      await tester.pumpAndSettle();
      expect(find.text('3 semanas'), findsOneWidget);

      // Con tres semanas el botón ya no puede prometer la fuente.
      expect(find.text('Copiar otra semana acá'), findsOneWidget);
      await tester.tap(find.byKey(const Key('duplicate_week_button')));
      await tester.pumpAndSettle();

      // Selector con las OTRAS dos, y sin la actual: copiarse a sí misma no
      // es una opción.
      expect(find.text('¿Copiar a la Semana 3 desde cuál?'), findsOneWidget);
      expect(find.byKey(const Key('copy_source_week_0')), findsOneWidget);
      expect(find.byKey(const Key('copy_source_week_1')), findsOneWidget);
      expect(find.byKey(const Key('copy_source_week_2')), findsNothing);

      // Elegir la Semana 1 la trae.
      await tester.tap(find.byKey(const Key('copy_source_week_0')));
      await tester.pumpAndSettle();
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('con DOS semanas no pregunta: la fuente es forzosa',
        (tester) async {
      // El selector es para elegir, y con una sola opción no hay elección.
      await _pumpEditor(tester);
      await _fillMinimalValidForm(tester);
      await tester.tap(find.text('+'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('duplicate_week_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('desde cuál'), findsNothing);
      expect(find.byKey(const Key('duplicate_week_confirm_button')),
          findsOneWidget);
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

        await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      expect(enElEditor(find.text('Día A')), findsOneWidget); // day name
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget); // slot
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
        await _tapGuardar(tester);
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

  // «Que pueda modificarlas y cuando toca guardar, que le salga un cartel
  // diciendo algo como: ¿desea crear una copia con las modificaciones o no?,
  // cumpliendo la misma función que al editar una foto en el teléfono.»
  group('RoutineEditorWebScreen — guardar o guardar como copia', () {
    Future<_MockRoutineRepository> editando(WidgetTester tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.updateAssigned(
                uid: any(named: 'uid'),
                draft: any(named: 'draft'),
              ))
          .thenAnswer((i) => Future.value(i.namedArguments[#draft] as Routine));
      when(() => repo.createTemplate(any())).thenAnswer(
          (i) => Future.value(i.positionalArguments.first as Routine));
      await _pumpEditor(tester, repo: repo, routineId: 'r1');
      return repo;
    }

    Future<void> cambiarAlgo(WidgetTester tester) async {
      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza v2',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sin cambios no pregunta nada: guarda y listo', (tester) async {
      // El cartel sale sólo si hay algo que decidir. Uno que sale SIEMPRE
      // —incluso cuando no tocaste nada— enseña a apretar el primer botón sin
      // leer, y ahí se pierde el peso de todas las confirmaciones de esta
      // pantalla, incluida la de descartar cambios.
      final repo = await editando(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Guardar como copia'), findsNothing);
      verify(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).called(1);
    });

    testWidgets('con cambios pregunta antes de escribir nada', (tester) async {
      final repo = await editando(tester);
      await cambiarAlgo(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Guardar como copia'), findsOneWidget);
      // Lo importante: con el cartel abierto todavía NO se escribió nada. Si
      // el guardado saliera antes de la respuesta, «como copia» terminaría
      // haciendo las dos cosas.
      verifyNever(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
      verifyNever(() => repo.createTemplate(any()));
    });

    testWidgets('«Guardar» pisa el documento y no crea ninguna plantilla',
        (tester) async {
      final repo = await editando(tester);
      await cambiarAlgo(tester);
      await _tapGuardar(tester);

      final draft = verify(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          )).captured.single as Routine;
      expect(draft.id, 'r1');
      expect(draft.name, 'Fuerza v2');
      verifyNever(() => repo.createTemplate(any()));
    });

    // EL test de este grupo. Toda la promesa de «mantener la original en la
    // galería» es que esta rama NO llame a update.
    testWidgets('«Guardar como copia» NO toca la rutina original',
        (tester) async {
      final repo = await editando(tester);
      await cambiarAlgo(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pumpAndSettle();

      verify(() => repo.createTemplate(any())).called(1);
      verifyNever(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
      verifyNever(() => repo.updateTemplate(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
    });

    testWidgets('la copia nace como PLANTILLA sin alumno, con «(copia)»',
        (tester) async {
      // Aunque se esté editando el plan de un alumno. Es el caso que el PF
      // describió —«esto me quedó bueno, lo quiero para otros»— y el único que
      // construye biblioteca. Una copia asignada al mismo alumno le suma una
      // tarjeta a esa persona y no le sirve a nadie más.
      final repo = await editando(tester);
      await cambiarAlgo(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pumpAndSettle();

      final copia = verify(() => repo.createTemplate(captureAny()))
          .captured
          .single as Routine;
      expect(copia.id, isEmpty); // documento NUEVO
      expect(copia.name, 'Fuerza v2 (copia)');
      expect(copia.source, RoutineSource.trainerTemplate);
      expect(copia.assignedTo, isNull);
      // Las reglas sólo aceptan 'private' en un trainer-template.
      expect(copia.visibility, RoutineVisibility.private);
    });

    // CANDADO de la §7 del doc de biblioteca: «invalidar los DOS listados
    // después de cualquier mutación. Olvidar uno no falla ni compila mal: la
    // card se queda en pantalla hasta recargar.»
    //
    // Al editor le faltaba el de la sección Rutinas para TODOS sus caminos de
    // escritura, no sólo para la copia — `routinesAuthoredByProvider` es un
    // `autoDispose` que esa pantalla watchea, y el editor llega por `push`, así
    // que la ruta de abajo sigue montada y el provider nunca se dispone.
    testWidgets('guardar refresca el listado de la sección Rutinas',
        (tester) async {
      var fetches = 0;
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.updateAssigned(
                uid: any(named: 'uid'),
                draft: any(named: 'draft'),
              ))
          .thenAnswer((i) => Future.value(i.namedArguments[#draft] as Routine));

      await _pumpEditor(
        tester,
        repo: repo,
        routineId: 'r1',
        observarListadoDeRutinas: true,
        extraOverrides: [
          routinesAuthoredByProvider(_trainerId).overrideWith((ref) async {
            fetches++;
            return const <Routine>[];
          }),
        ],
      );
      expect(fetches, 1, reason: 'la pantalla de atrás ya lo pidió una vez');

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza v2',
      );
      await tester.pumpAndSettle();
      await _tapGuardar(tester);

      expect(fetches, 2,
          reason: 'volvió a pedirlo: la sección Rutinas ve el cambio sin '
              'recargar la página');
    });

    // Codex marcó los tres de acá abajo en la review de #1097, y los tres eran
    // el MISMO fix hecho a medias: se corrigieron `athleteId` y `operation`
    // para que describan la escritura y no la pantalla, y quedaron sin
    // corregir el `source` de analytics y el copy de la denegación.

    testWidgets('la copia se reporta como PLANTILLA en analytics',
        (tester) async {
      // `_analyticsSource` sale de `widget.isTemplate`, que sigue en false
      // cuando la copia se hizo desde el editor de un plan. Reportarla como
      // `trainer_assigned` ensucia justo el corte que separa planes de
      // plantillas reutilizables — el que este cambio existe para alimentar.
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.createTemplate(any())).thenAnswer(
          (i) => Future.value(i.positionalArguments.first as Routine));
      final analytics = FakeAnalyticsService();
      await _pumpEditor(tester,
          repo: repo, analytics: analytics, routineId: 'r1');

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza v2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pumpAndSettle();

      final params = analytics.paramsOf('routine_created').single;
      expect(params['source'], 'trainer_template');
      await tester.pump(const Duration(seconds: 6)); // drenar el SnackBar
    });

    // El aviso es cosmético; la invalidación no. Si el snackbar sale ANTES,
    // basta con que el State se haya dispuesto durante el `await` para que
    // `ScaffoldMessenger.of(context)` tire, el catch vuelva por `!mounted`, y
    // la sección Rutinas quede stale con la copia YA escrita.
    testWidgets('la copia refresca el listado de la sección Rutinas',
        (tester) async {
      var fetches = 0;
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.createTemplate(any())).thenAnswer(
          (i) => Future.value(i.positionalArguments.first as Routine));

      await _pumpEditor(
        tester,
        repo: repo,
        routineId: 'r1',
        observarListadoDeRutinas: true,
        extraOverrides: [
          routinesAuthoredByProvider(_trainerId).overrideWith((ref) async {
            fetches++;
            return const <Routine>[];
          }),
        ],
      );
      expect(fetches, 1);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza v2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pumpAndSettle();

      expect(fetches, 2,
          reason: 'la plantilla nueva tiene que aparecer sin recargar');
      await tester.pump(const Duration(seconds: 6)); // drenar el SnackBar
    });

    testWidgets('si deniegan la copia, el cartel NO habla del alumno',
        (tester) async {
      // La copia escribe una PLANTILLA. Decir «no pudimos escribir sobre este
      // alumno» y mandar a mirar su cupo sería inventarle una causa a una
      // escritura que no lo tocó — una advertencia falsa (AGENTS.md §11.1).
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.createTemplate(any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Fuerza v2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pumpAndSettle();

      final texto = tester
          .widget<Text>(find.byKey(const Key('routine_editor_error_message')))
          .data!;
      expect(texto, isNot(contains('este alumno')));
      expect(texto, isNot(contains('cupo de tu plan')));
      expect(texto, contains('Reintentar no lo va a cambiar'));
    });

    testWidgets(
        'avisa dónde quedó la copia, que si no el editor se cierra '
        'y el PF no sabe qué pasó', (tester) async {
      final repo = await editando(tester);
      await cambiarAlgo(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar como copia'));
      await tester.pump();

      expect(find.textContaining('Fuerza v2 (copia)'), findsWidgets);
      // `findsWidgets`: el SnackBar en vuelo puede aparecer más de una vez en
      // el árbol durante su animación de entrada.
      expect(
          find.textContaining('La original quedó como estaba'), findsWidgets);
      expect(repo, isNotNull);

      // Drenar el auto-dismiss del SnackBar. Sin esto queda un Timer vivo al
      // terminar el test y el que corre después arranca sucio — el «Rango» de
      // más abajo se ponía rojo por esto y pasaba en aislamiento, que es la
      // firma de una contaminación entre tests, no de un bug.
      await tester.pump(const Duration(seconds: 6));
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
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
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
      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
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

      await _tapGuardar(tester);
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
      // El panel lateral está SIEMPRE abierto en desktop (#860): el botón
      // "Agregar ejercicio" del día no existe ahí, lo reemplaza el panel.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // El panel NO se cierra: es el punto del #860 y ya no tiene con qué.
      // Lo que sigue mira el EDITOR, así que scopea con [enElEditor].
      // La card nace PLEGADA desde que la web usa `ExerciseCard`: los campos
      // de sets no están en el árbol hasta abrirla.
      await expandirEjercicios(tester);
      await tester.tap(find.text('Tiempo'));
      await tester.pumpAndSettle();

      // Seconds left empty.
      await _tapGuardar(tester);
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

        await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
      expect(enElEditor(find.text('Aperturas con Cable')), findsOneWidget);
      // The link is reconstructed and shown as active on the first slot.
      expect(find.text('En superserie con el siguiente'), findsOneWidget);

      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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

      // Se carga la semana 1 y RECIÉN AHÍ se suma la 2, copiándola: desde que
      // la semana nueva nace pelada, sumar primero dejaría la 2 sin ejercicio
      // y sin campo de reps que editar.
      await _fillMinimalValidForm(tester);
      await _agregarSemanaCopiandoLaAnterior(tester);
      expect(find.text('2 semanas'), findsOneWidget);

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

      await _tapGuardar(tester);
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

        await _tapGuardar(tester);
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

        // Se carga la semana 1 y se COPIA a la 2, así el ejercicio arranca
        // presente en ambas y el chip tiene algo real que apagar. (Sumar sin
        // copiar dejaría la máscara en {0} de entrada y el test probaría el
        // default en vez del chip.)
        await _fillMinimalValidForm(tester);
        await _agregarSemanaCopiandoLaAnterior(tester);
        expect(find.text('2 semanas'), findsOneWidget);
        await tester.tap(find.byKey(const Key('week_tab_0')));
        await tester.pumpAndSettle();

        // Exclude week 2 (0-based index 1) via its presence chip.
        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1')));
        await tester.pumpAndSettle();

        await _tapGuardar(tester);
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
        // El PF carga la semana 1 y suma una semana que —desde este cambio—
        // nace PELADA y se queda así. Guardar tiene que funcionar igual: los
        // sets en blanco de una semana donde el ejercicio no está nunca se
        // ejecutan, y exigir reps para ellos bloqueaba un plan válido.
        //
        // También fija la decisión de que una semana vacía AVISA (dot en la
        // pestaña) pero NO bloquea: ya hay planes así en producción, y
        // bloquear le sacaría el guardar a quien abrió uno viejo.
        final repo = _MockRoutineRepository();
        when(
          () => repo.createAssigned(any()),
        ).thenAnswer((i) async => i.positionalArguments.first as Routine);
        await _pumpEditor(tester, repo: repo);

        // Bump FIRST → the exercise added below gets 2 BLANK weeks.
        // Carga la semana 1 y suma la 2, que queda pelada.
        await _fillMinimalValidForm(tester);
        await tester.tap(find.text('+'));
        await tester.pumpAndSettle();
        expect(find.text('2 semanas'), findsOneWidget);

        // La Semana 2 no tiene ejercicios y AVISA con el dot...
        expect(find.byKey(const Key('week_tab_warning_1')), findsOneWidget);

        // ...pero se guarda igual.
        await _tapGuardar(tester);
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
        // Copiar deja el ejercicio en las DOS semanas, o sea máscara vacía:
        // el estado desde el que apagar y volver a prender tiene sentido.
        await _agregarSemanaCopiandoLaAnterior(tester);
        expect(find.text('2 semanas'), findsOneWidget);
        await tester.tap(find.byKey(const Key('week_tab_0')));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
        await tester.tap(find.byKey(const Key('presence_chip_1'))); // exclude
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('presence_chip_1')),
        ); // re-include
        await tester.pumpAndSettle();

        await _tapGuardar(tester);
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

        await _tapGuardar(tester);
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

  group('RoutineEditorWebScreen — plegar el dia', () {
    // El editor web dibuja TODOS los dias a la vez —a diferencia del mobile,
    // que muestra uno por pestana—, asi que una rutina de 4 dias por 5
    // ejercicios es una pagina que no termina mas. `_EditorSlot.expandido` ya
    // resolvia esto para el EJERCICIO; faltaba la misma pieza para el DIA.

    testWidgets('arranca abierto: cerrar por default esconderia trabajo',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
      expect(find.byKey(const Key('day_collapse_toggle_1')), findsOneWidget);
    });

    testWidgets('el chevron cierra el dia y deja el conteo en su lugar',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      await tester.tap(find.byKey(const Key('day_collapse_toggle_1')));
      await tester.pumpAndSettle();

      // Los ejercicios se van del formulario. El `enElEditor` importa: el
      // panel lateral lista el catalogo completo y matchearia igual.
      expect(enElEditor(find.text('Press de Banca')), findsNothing);
      // Sin el conteo, una card cerrada no se distingue de un dia vacio.
      expect(find.text('1 ejercicio'), findsOneWidget);
    });

    testWidgets('vuelve a abrir con el mismo chevron', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      await tester.tap(find.byKey(const Key('day_collapse_toggle_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('day_collapse_toggle_1')));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
      expect(find.text('1 ejercicio'), findsNothing);
    });

    testWidgets('un dia con error MUESTRA su punto aunque este cerrado',
        (tester) async {
      // Un ejercicio recien agregado viene sin reps: el dia queda invalido y
      // bloquea el guardado. Si al plegarlo se escondiera el aviso, el PF
      // buscaria el problema en cualquier otro lado.
      await _pumpEditor(tester);
      // Se agrega desde el panel lateral, que en desktop esta siempre abierto
      // (#860) y reemplaza al boton "Agregar ejercicio" del dia.
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('day_error_dot_1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('day_collapse_toggle_1')));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsNothing);
      expect(find.byKey(const Key('day_error_dot_1')), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — «solo esta semana» dice que hizo', () {
    // El PF, dos veces: «si lo estoy borrando, para qué lo dejás ahí; quiero
    // que si lo borro de una de las semanas se borre de esa semana». Ahora la
    // card DESAPARECE de esa semana.
    //
    // Y por eso el cartel importa MÁS que antes, no menos: desaparecer sin
    // decir nada es indistinguible de haberlo borrado de todas las semanas,
    // que es la otra opción del mismo diálogo.

    /// Crea una rutina de 2 semanas con un ejercicio y lo saca de la semana
    /// que se esta mirando — el camino exacto que reporto el PF.
    Future<void> borrarSoloEstaSemana(WidgetTester tester) async {
      await _pumpEditor(tester);
      // El panel lateral esta siempre abierto en desktop (#860).
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      // Sumar + copiar: la semana nueva nace pelada, y este test necesita el
      // ejercicio presente en las dos para que «Solo esta semana» tenga la
      // otra rama (si estuviera en una sola, el borrado sería estructural).
      await _agregarSemanaCopiandoLaAnterior(tester);

      await tester.tap(find.byTooltip('Quitar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solo esta semana'));
      await tester.pumpAndSettle();
    }

    testWidgets('el cartel nombra el ejercicio y la semana', (tester) async {
      await borrarSoloEstaSemana(tester);

      expect(find.textContaining('sale de la Semana'), findsOneWidget);
      // Y dice por dónde vuelve. El texto viejo prometía «Queda atenuado»,
      // que describía un estado que ya no existe: no queda nada en pantalla.
      expect(find.textContaining('Podés volver a agregarlo'), findsOneWidget);
      expect(find.textContaining('Queda atenuado'), findsNothing);
    });

    testWidgets('«Deshacer» lo devuelve a la semana', (tester) async {
      await borrarSoloEstaSemana(tester);

      // Se fue de la semana — eso es lo que se pidió.
      expect(enElEditor(find.text('Press de Banca')), findsNothing);

      expect(find.text('Deshacer'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();

      // Y vuelve entero: Deshacer restaura la máscara ANTERIOR, no un `add`
      // de la semana — la anterior podía ser vacía («en todas»).
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('el cartel se va SOLO, no se queda hasta recargar',
        (tester) async {
      // El PF: «llega esta notificación y no desaparece hasta que recargo la
      // página». No era timing: `SnackBar` hace
      // `persist = persist ?? action != null`, o sea que CUALQUIER cartel con
      // acción es eterno por default y `ScaffoldMessenger` ni le agenda el
      // timer. Éste trae «Deshacer», así que se quedaba para siempre.
      await borrarSoloEstaSemana(tester);
      expect(find.textContaining('sale de la Semana'), findsOneWidget);

      // Sigue estando a los 5 s: la ventana para tocar Deshacer es real.
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('sale de la Semana'), findsOneWidget);

      // Y se va solo a los 6.
      await tester.pump(const Duration(seconds: 2));
      await tester
          .pump(const Duration(milliseconds: 500)); // animación de salida
      expect(find.textContaining('sale de la Semana'), findsNothing);
    });

    testWidgets('el cartel NO sobrevive a irse de la pantalla', (tester) async {
      // En la captura del PF el cartel del editor aparece sobre la sección de
      // CHAT: se fue de la pantalla y el aviso lo siguió. Un `SnackBar` vive
      // en el `ScaffoldMessenger` de la app, no en la ruta, así que sobrevive
      // al pop — y su «Deshacer» apunta a un editor que ya no está.
      await borrarSoloEstaSemana(tester);
      expect(find.textContaining('sale de la Semana'), findsOneWidget);

      // Se va del editor. Está sucio, así que el PopScope pregunta.
      await tester.tap(find.byIcon(TreinoIcon.arrowLeft));
      await tester.pumpAndSettle();
      // El editor está sucio: el PopScope pregunta antes de dejar salir.
      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('sale de la Semana'),
        findsNothing,
        reason: 'el aviso es de ESTA pantalla: no puede seguirte a otra',
      );
    });

    testWidgets('apagar el chip de la semana en curso avisa igual',
        (tester) async {
      // La segunda puerta al mismo estado. Sin esto la card se desvanecía bajo
      // el cursor sin decir qué pasó: la queja original, servida de nuevo.
      await _pumpEditor(tester);
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      await _agregarSemanaCopiandoLaAnterior(tester);
      // Los chips viven DENTRO de la card, que nace colapsada.
      await expandirEjercicios(tester);

      // Copiar deja parado en la Semana 2: apaga el chip de ESA, la que se
      // está mirando.
      await tester.ensureVisible(find.byKey(const Key('presence_chip_1')));
      await tester.tap(find.byKey(const Key('presence_chip_1')));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsNothing);
      expect(find.textContaining('sale de la Semana 2'), findsOneWidget);
      expect(find.text('Deshacer'), findsOneWidget);
    });

    testWidgets('apagar el chip de OTRA semana no avisa: nada se movió',
        (tester) async {
      // Control del test de arriba. Si el cartel saliera también acá, estaría
      // avisando de algo que el PF no ve pasar — ruido sobre una edición que
      // no cambió la pantalla.
      await _pumpEditor(tester);
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();
      await _agregarSemanaCopiandoLaAnterior(tester);
      await expandirEjercicios(tester);

      // Parado en la Semana 2, apaga la 1: es OTRA semana, nada se mueve acá.
      await tester.ensureVisible(find.byKey(const Key('presence_chip_0')));
      await tester.tap(find.byKey(const Key('presence_chip_0')));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
      expect(find.textContaining('sale de la Semana'), findsNothing);
    });
  });

  group('RoutineEditorWebScreen — el ejercicio ausente NO ESTÁ', () {
    // Antes esta pantalla ATENUABA la card ausente en vez de esconderla, y
    // había una razón real: la web no tenía forma de volver a agregar el
    // ejercicio, así que esconderlo lo habría dejado inalcanzable. Los chips
    // de «Semanas:» eran ese único camino de vuelta, y por eso vivían afuera
    // de los `IgnorePointer` que apagaban el resto de la card.
    //
    // Esconder recién se puede una vez que el picker lo vuelve a ofrecer. Ese
    // es el test que sostiene todo este grupo, y va abajo.
    //
    // `_presenceRoutine` es `numWeeks: 2` con el slot presente SOLO en la
    // semana 0: pararse en la semana 2 es exactamente ese estado.
    Future<_MockRoutineRepository> abrirEnLaSemanaSinElEjercicio(
      WidgetTester tester,
    ) async {
      final repo = _MockRoutineRepository();
      when(
        () => repo.getById(any()),
      ).thenAnswer((_) async => _presenceRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r7');
      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('no se dibuja nada suyo en esa semana', (tester) async {
      await abrirEnLaSemanaSinElEjercicio(tester);

      expect(enElEditor(find.text('Press de Banca')), findsNothing);
      // Y no queda un esqueleto: ni la prescripción ni los chips sobreviven.
      // Con el atenuado, TODO esto seguía en el árbol.
      expect(enElEditor(find.text('Descanso (seg)')), findsNothing);
      expect(enElEditor(find.text('Semanas:')), findsNothing);
    });

    testWidgets('sigue intacto en la semana donde SÍ está', (tester) async {
      await abrirEnLaSemanaSinElEjercicio(tester);
      await tester.tap(find.byKey(const Key('week_tab_0')));
      await tester.pumpAndSettle();

      // Esconderlo de una semana no puede ser borrarlo de la rutina: son las
      // dos ramas del mismo diálogo y tienen que seguir distinguiéndose.
      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('el picker lo vuelve a OFRECER — el camino de vuelta',
        (tester) async {
      // ESTE es el test que habilita esconder. Sin él, sacar un ejercicio de
      // una semana lo volvía inalcanzable: filtrado de la lista Y descartado
      // por el picker como «ya está en el día», porque `alreadySelectedIds`
      // miraba el día entero en vez de la semana. Es el agujero que el editor
      // del teléfono tenía y que este cambio cierra en los dos.
      await abrirEnLaSemanaSinElEjercicio(tester);

      await _elegirEnPanel(tester, 'Press de Banca');
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();

      expect(enElEditor(find.text('Press de Banca')), findsOneWidget);
    });

    testWidgets('el picker no lo da por puesto en la semana que no lo tiene',
        (tester) async {
      // La otra mitad del camino de vuelta, y la que casi se me escapa: que
      // `_agregarAlDia` sepa restaurar no alcanza si el picker ya lo cuenta
      // como puesto. `alreadySelectedIds` arranca TILDANDO lo que recibe, así
      // que mirando el día entero el ejercicio aparecía marcado en una semana
      // que no lo tiene, y el botón decía «Agregar (1)» sin haber tocado nada.
      //
      // Va por el MODAL y no por el panel a propósito. El panel lee
      // `alreadySelectedIds` UNA vez, en su `initState`: después de cambiar de
      // semana sigue mostrando los tildes de la anterior, así que ahí la
      // afirmación no se puede probar. El modal monta fresco en cada apertura.
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any()))
          .thenAnswer((_) async => _presenceRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r7');
      // `compact` (768–1279): sin panel lateral, el alta vuelve al modal.
      tester.view.physicalSize = const Size(1100, 1100);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();

      final agregar = find.text('Agregar ejercicio');
      await tester.ensureVisible(agregar.first);
      await tester.pumpAndSettle();
      await tester.tap(agregar.first);
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(
        find.text('Agregar (1)'),
        findsNothing,
        reason: 'en esta semana el ejercicio NO está: nada pre-tildado',
      );
      expect(find.text('Agregar'), findsOneWidget);
    });

    testWidgets('al volver es el MISMO slot, no uno nuevo en blanco',
        (tester) async {
      final repo = await abrirEnLaSemanaSinElEjercicio(tester);
      when(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((i) async => i.namedArguments[#draft] as Routine);

      await _elegirEnPanel(tester, 'Press de Banca');
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();

      await _tapGuardar(tester);
      await tester.pumpAndSettle();

      final draft = verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;

      final slots = draft.days.single.slots;
      // UN slot, no dos. Un ejercicio por día es invariante del dominio
      // (QA-WKT-004): dar de alta uno nuevo dejaría dos «Press de Banca» en el
      // mismo día, que es lo que pasaría si el regreso fuera un alta común.
      expect(slots, hasLength(1));
      // Máscara vacía = presente en TODAS: volvió a la semana 2 sin perder la
      // 1, y `[0, 1]` se canonicaliza a "sin máscara".
      expect(slots.single.activeWeeks, isEmpty);
      // Y con su prescripción: 8 reps a 60 kg, no un set en blanco.
      expect(slots.single.weeklySets[1].single.reps, 8);
      expect(slots.single.weeklySets[1].single.weightKg, 60);
    });
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
      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
      await tester.pumpAndSettle();
      return verify(
        () => repo.updateAssigned(
          uid: any(named: 'uid'),
          draft: captureAny(named: 'draft'),
        ),
      ).captured.single as Routine;
    }

    testWidgets('está en TODA semana y nombra la fuente cuando hay una sola', (
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

      // Antes el botón se escondía en la Semana 1: la fuente era siempre «la
      // anterior», y la primera no tiene. Con la fuente elegible cualquier
      // semana puede RECIBIR una copia, así que la 1 puede tomar de la 2.
      //
      // Y no es un detalle de simetría: desde que la semana nueva nace pelada,
      // copiar dejó de ser un rescate ocasional y es LA forma de replicar un
      // bloque.
      expect(find.byKey(const Key('duplicate_week_button')), findsOneWidget);
      // Con dos semanas la fuente es forzosa, así que el botón la nombra.
      expect(find.text('Copiar Sem 2 acá'), findsOneWidget);

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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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

      await _tapGuardar(tester);
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
      await _tapGuardar(tester);
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
          (w) => w is TreinoIconButton && w.tooltip == copyTooltip,
        );

    List<TreinoIconButton> copyButtonsOf(WidgetTester tester) =>
        tester.widgetList<TreinoIconButton>(copyButtons()).toList();

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
      await _tapGuardar(tester);
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

    testWidgets('ni siquiera existe sobre un ejercicio ausente de la semana',
        (tester) async {
      // Antes la web atenuaba las cards ausentes en vez de esconderlas, así
      // que el botón se dibujaba igual y había que deshabilitarlo a mano. Al
      // ocultarlas (como mobile) la pregunta cambia de "¿está apagado?" a "¿no
      // está?": no hay card, no hay botón, no hay prescripción que pisar.
      //
      // `Press Inclinado` es `activeWeeks: [1]`: falta en la semana 1 y está
      // en la 2.
      await pump(tester, _copyPerWeekRoutine());
      expect(find.text('Press Inclinado'), findsNothing);
      expect(
        copyButtonsOf(tester),
        hasLength(1),
        reason: 'un solo ejercicio a la vista → un solo botón de copiar',
      );

      await tester.tap(find.byKey(const Key('week_tab_1')));
      await tester.pumpAndSettle();
      expect(find.text('Press Inclinado'), findsOneWidget);
      final botones = copyButtonsOf(tester);
      expect(botones, hasLength(2));
      expect(botones[1].onPressed, isNotNull);
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
      // La sugerencia de RÁPIDO, no la fila del panel lateral: `.last` a
      // secas agarraba el panel y la elección nunca llegaba al parser.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('quick_entry_results')),
              matching: find.text('Press de Banca'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quick_entry_confirm')));
      await tester.pumpAndSettle();

      await _tapGuardar(tester);
      await tester.pumpAndSettle();
      final draft = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slot = draft.days.single.slots.single;
      expect(slot.exerciseName, 'Press de Banca');
      expect(slot.sets, hasLength(4), reason: '4x10 son CUATRO series, no una');
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

  group('RoutineEditorWebScreen — picker como panel lateral (#860)', () {
    testWidgets('en desktop abre el PANEL y no un modal', (tester) async {
      await _pumpEditor(tester);

      // Sin tocar NADA: el panel ya está abierto al entrar al editor. Eso es
      // el pedido — el PF entra a armar la rutina y la plantilla de
      // ejercicios ya está ahí.
      expect(find.byType(ExercisePickerPanel), findsOneWidget);
      expect(find.byType(Dialog), findsNothing,
          reason: 'el modal es justo lo que este issue viene a sacar');
    });

    testWidgets('el panel NO se cierra al agregar', (tester) async {
      await _pumpEditor(tester);

      final panel = find.byType(ExercisePickerPanel);
      final fila =
          find.descendant(of: panel, matching: find.text('Press de Banca'));
      await tester.ensureVisible(fila);
      await tester.pumpAndSettle();
      await tester.tap(fila);
      await tester.pumpAndSettle();
      await tester
          .tap(find.descendant(of: panel, matching: find.text('Agregar (1)')));
      await tester.pumpAndSettle();

      // El corazón del #860: el loop "miro qué puse → elijo el que sigue →
      // miro cómo quedó" no se rompe porque el panel sigue abierto y la
      // plantilla sigue visible.
      expect(panel, findsOneWidget, reason: 'sigue abierto para el siguiente');
      expect(
        enElEditor(find.text('Press de Banca')),
        findsOneWidget,
        reason: 'y lo agregado aterrizó en el día',
      );
    });

    testWidgets(
        'abajo de 1280 no hay panel: el día conserva sus botones y el modal',
        (tester) async {
      await _pumpEditor(tester);
      // `compact`: 768-1279. Ahí el sidebar ya está forzado a colapsar
      // (ADR-CHW-004) y un panel de 400 px sería el mismo error.
      tester.view.physicalSize = const Size(1100, 1100);
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();

      expect(find.byType(ExercisePickerPanel), findsNothing);
      // Y por eso mismo los botones del día NO se pueden sacar acá: sin panel
      // y sin ellos no habría forma de cargar un ejercicio.
      final agregar = find.text('Agregar ejercicio');
      expect(agregar, findsWidgets,
          reason: 'única entrada que queda abajo de 1280');

      await tester.ensureVisible(agregar.first);
      await tester.pumpAndSettle();
      await tester.tap(agregar.first);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    // ── El panel se puede ensanchar ───────────────────────────────────────
    //
    // El PF: «no se adapta bien la lista de ejercicios a la pantalla y sus
    // diferentes tamaños». El panel estaba clavado en 400 px, así que un
    // monitor más grande no le sumaba nada — ni al panel ni a la rutina.
    Finder asaDelPanel() => find.descendant(
          of: find.byType(ExercisePickerPanel),
          matching: find.byWidgetPredicate(
            (w) =>
                w is MouseRegion &&
                w.cursor == SystemMouseCursors.resizeLeftRight,
          ),
        );

    double anchoPanel(WidgetTester tester) =>
        tester.getSize(find.byType(ExercisePickerPanel)).width;

    testWidgets('arrastrar el asa ensancha el panel', (tester) async {
      await _pumpEditor(tester);
      final antes = anchoPanel(tester);

      // El asa vive en el borde IZQUIERDO, el que da contra la rutina, así que
      // tirar hacia la izquierda agranda.
      await tester.drag(asaDelPanel(), const Offset(-80, 0));
      await tester.pumpAndSettle();

      expect(anchoPanel(tester), antes + 80);
    });

    testWidgets('y se frena donde la rutina dejaría de entrar', (tester) async {
      await _pumpEditor(tester);

      // Un tirón imposible: sin tope el panel se comería la pantalla y la
      // rutina quedaría en cero.
      await tester.drag(asaDelPanel(), const Offset(-5000, 0));
      await tester.pumpAndSettle();

      final panel = anchoPanel(tester);
      final total = tester.getSize(find.byType(RoutineEditorWebScreen)).width;
      expect(
        total - panel,
        greaterThanOrEqualTo(kAnchoMinimoRutina),
        reason: 'la rutina no cede nunca sus $kAnchoMinimoRutina px: el panel '
            'quedó en $panel sobre $total',
      );
    });

    testWidgets('"En superserie" sólo aparece con 2 o más elegidos',
        (tester) async {
      await _pumpEditor(tester);
      final panel = find.byType(ExercisePickerPanel);
      final boton = find.byKey(const Key('picker_agregar_superserie'));

      // Con cero y con uno no hay superserie posible: una superserie de un
      // ejercicio no es una superserie.
      expect(boton, findsNothing);
      await _elegirEnPanel(tester, 'Press de Banca');
      expect(boton, findsNothing, reason: 'uno solo no agrupa nada');

      await _elegirEnPanel(tester, 'Aperturas con Cable');
      expect(boton, findsOneWidget);

      await tester.tap(boton);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget,
          reason: 'sigue abierto, como cualquier alta');
    });

    testWidgets('"En superserie" los agrega YA enlazados', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => null);
      when(() => repo.createAssigned(any()))
          .thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Plan superserie',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'Full body',
      );
      await _elegirEnPanel(tester, 'Press de Banca');
      await _elegirEnPanel(tester, 'Aperturas con Cable');
      await tester.tap(find.byKey(const Key('picker_agregar_superserie')));
      await tester.pumpAndSettle();
      await expandirEjercicios(tester);
      // Los dos slots necesitan reps o el submit no pasa la validación. El
      // campo se ubica por su hint 'reps': `.first` sobre TextFormField vacío
      // agarraría también el 'kg' de al lado.
      for (var i = 0; i < 2; i++) {
        await tester.enterText(
          find
              .ancestor(
                of: find.text('reps'),
                matching: find.byType(TextFormField),
              )
              .at(i),
          '10',
        );
      }
      await tester.pumpAndSettle();

      await _tapGuardar(tester);
      await tester.pumpAndSettle();

      final draft = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slots = draft.days.single.slots;
      expect(slots, hasLength(2));
      // El enlace va en todos MENOS el último: la corrida la define el enlace
      // del anterior, así que marcar el último engancharía al que venga
      // después. Y el grupo se reconstruye igual que si se hubiera tildado a
      // mano — el alta agrupada no es una segunda forma de armar superseries.
      expect(slots[0].supersetGroup, isNotNull);
      expect(slots[1].supersetGroup, slots[0].supersetGroup);
    });

    testWidgets('en desktop el día NO repite los botones de alta',
        (tester) async {
      await _pumpEditor(tester);

      // Dos entradas para lo mismo, una al lado de la otra, es ruido: el panel
      // ya es la superficie para cargar. Y "+ Superserie" sobra del todo — esa
      // decisión ahora se toma en el panel, donde se hace la selección.
      expect(find.text('Agregar ejercicio'), findsNothing);
      expect(find.text('+ Superserie'), findsNothing);
    });

    testWidgets('el panel NO ofrece "Cancelar"', (tester) async {
      await _pumpEditor(tester);

      // En el panel no hay ruta que cerrar: `Navigator.pop()` saldría del
      // editor entero, o sea lo contrario de lo que el botón promete. El
      // modal sí lo tiene, y ahí está bien.
      expect(
        find.descendant(
          of: find.byType(ExercisePickerPanel),
          matching: find.text('Cancelar'),
        ),
        findsNothing,
      );
    });

    testWidgets('"Crear ejercicio nuevo" está al pie, debajo de la lista',
        (tester) async {
      await _pumpEditor(tester);

      // Arriba de la lista competía por el alto con lo único que importa acá.
      // Al pie es alto fijo: no se scrollea y sigue siempre visible.
      final crear = find.text('Crear ejercicio nuevo');
      final unEjercicio = find.text('Press de Banca');
      expect(crear, findsOneWidget);
      expect(
        tester.getCenter(crear).dy,
        greaterThan(tester.getCenter(unEjercicio.last).dy),
        reason: 'tiene que estar DEBAJO de la lista, no arriba',
      );
    });

    testWidgets('los filtros arrancan colapsados', (tester) async {
      await _pumpEditor(tester);

      // 23 chips desplegados eran 4 filas y dejaban 3 ejercicios visibles
      // sobre un catálogo de cientos: la mitad del problema de alto del #860.
      expect(find.text('PECHO'), findsNothing);
      expect(find.byKey(const Key('picker_filtros_toggle')), findsOneWidget);

      await tester.tap(find.byKey(const Key('picker_filtros_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('PECHO'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — entrada rápida: elegir una variante', () {
    testWidgets(
        'elegir un ejercicio de nombre MÁS LARGO que lo tipeado queda '
        'seleccionado', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => null);
      when(() => repo.createAssigned(any()))
          .thenAnswer((i) async => i.positionalArguments.first as Routine);
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
        find.byKey(const Key('routine_editor_name_field')),
        'Plan',
      );
      await tester.enterText(
        find.byKey(const Key('routine_editor_split_field')),
        'Full body',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('RÁPIDO'));
      await tester.pumpAndSettle();

      // "press" trae varias variantes. Reportado en device: NINGUNA se podía
      // elegir.
      //
      // La causa: `sigueElegido` exige que el texto CONTENGA el nombre, y
      // "press" no contiene "Press Inclinado con Mancuerna" — el elegido se
      // limpiaba en el frame siguiente. El `onSelect` tiene que REESCRIBIR el
      // texto con el nombre completo, que es lo que el editor mobile ya hacía
      // y esta versión no había copiado.
      await tester.enterText(
        find.byKey(const Key('quick_entry_field')),
        'press 3x12 40',
      );
      await tester.pumpAndSettle();
      // La sugerencia de RÁPIDO, no la fila del panel lateral.
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const Key('quick_entry_results')),
              matching: find.text('Press Inclinado con Mancuerna'),
            )
            .last,
      );
      await tester.pumpAndSettle();

      // Sigue elegido: el confirmar está disponible y agrega ESE ejercicio.
      await tester.tap(find.byKey(const Key('quick_entry_confirm')));
      await tester.pumpAndSettle();

      await _tapGuardar(tester);
      await tester.pumpAndSettle();
      final draft = verify(() => repo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      final slot = draft.days.single.slots.single;
      expect(slot.exerciseName, 'Press Inclinado con Mancuerna');
      // Y la prescripción que se tipeó ANTES de elegir no se perdió: el
      // `onSelect` conserva los números y sólo saca las palabras de búsqueda.
      expect(slot.sets, hasLength(3));
      expect(slot.sets.every((s) => s.reps == 12), isTrue);
      expect(slot.sets.every((s) => s.weightKg == 40), isTrue);
    });
  });
}
