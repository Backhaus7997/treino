/// Entrypoint del companion de Wear OS.
///
/// Se construye con el flavor `wear`, que es el que declara el foreground
/// service y `android.hardware.type.watch`:
///
/// ```
/// flutter build apk --flavor wear -t lib/main_wear.dart
/// flutter run   -d <reloj> --flavor wear -t lib/main_wear.dart
/// ```
///
/// ## Qué comparte con el teléfono y qué no
///
/// Comparte el TEMA (`AppTheme.dark` + `AppPalette`) y la capa de dominio
/// Dart — verificado corriendo en el reloj: 22/22 casos del contrato de
/// `conformance/` con cero cambios en `lib/features/workout/domain/`. Ésa es
/// toda la razón de hacer el companion en Flutter y no en Kotlin nativo: una
/// sola implementación de las reglas, cero divergencia posible.
///
/// NO comparte la UI. Una pantalla de reloj no es una pantalla de teléfono
/// achicada: es redonda, se mira de reojo y con una mano ocupada.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme/app_theme.dart';
import 'features/watch/application/wear_rest_providers.dart';
import 'features/watch/presentation/wear/wear_root.dart';
import 'features/watch/presentation/wear/wear_view_models.dart';
import 'features/watch/presentation/wear/wear_workout_view_model.dart';
import 'features/workout/domain/set_spec.dart';

void main() {
  runApp(const ProviderScope(child: TreinoWearApp()));
}

class TreinoWearApp extends StatelessWidget {
  const TreinoWearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Modo oscuro siempre: el producto no tiene light theme, y en un reloj
      // además es lo que cuida la batería en pantallas OLED.
      theme: AppTheme.dark(),
      home: const _WearHome(),
    );
  }
}

/// Arranca el foreground service al montar.
///
/// Va acá y no en `main()` a propósito: la precondición de runtime del
/// foreground service tipo `health` es *while-in-use*, así que tiene que
/// arrancarlo una Activity VISIBLE. Desde un receiver con la app cerrada tira
/// `SecurityException`.
class _WearHome extends ConsumerStatefulWidget {
  const _WearHome();

  @override
  ConsumerState<_WearHome> createState() => _WearHomeState();
}

class _WearHomeState extends ConsumerState<_WearHome> {
  /// Rutina abierta en el detalle, o null.
  (WearRoutineSummary, WearRoutineListKind)? _selected;

  /// Entreno EN CURSO, o null. Arranca en null: el atleta ve HOY primero.
  WearWorkoutSnapshot? _session;

  @override
  void initState() {
    super.initState();
    // Sin esto la app se congela con la muñeca baja: medido, 22.6% de
    // cobertura del tiempo despierto contra 100.0% con el servicio puesto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(wearWorkoutServiceProvider).startWorkout();
    });
  }

  // ── DATOS DE MUESTRA ──────────────────────────────────────────────────────
  //
  // TODO(wear): reemplazar por la cadena real — credencial minteada por el
  // teléfono, Firestore con listeners, resolución del entreno del día. Existen
  // para poder MIRAR cada pantalla y validarla contra la de watchOS antes de
  // invertir en esa cadena.

  static const _muestraHoy = WearTodaysWorkout(
    dayName: 'Empuje',
    routineName: 'Full Body 3 días',
    weekNumber: 1,
    numWeeks: 4,
    exercises: [
      WearExercisePreview(name: 'Sentadilla con barra', setCount: 4),
      WearExercisePreview(name: 'Press de banca', setCount: 4),
      WearExercisePreview(name: 'Remo con barra', setCount: 3),
      WearExercisePreview(name: 'Elevaciones laterales', setCount: 3),
      WearExercisePreview(name: 'Plancha', setCount: 1),
    ],
  );

  static const _muestraPlanes = [
    WearRoutineSummary(
      id: 'p1',
      name: 'Full Body 3 días',
      dayCount: 3,
      numWeeks: 4,
      badge: 'PF',
    ),
    WearRoutineSummary(
        id: 'p2', name: 'Fuerza básica', dayCount: 4, numWeeks: 1),
  ];

  static const _muestraPlantillas = [
    WearRoutineSummary(
        id: 't1', name: 'Push Pull Legs', dayCount: 6, numWeeks: 1),
    WearRoutineSummary(
        id: 't2', name: 'Full Body principiante', dayCount: 3, numWeeks: 1),
  ];

  static const _sesionInicial = WearWorkoutSnapshot(
    exerciseName: 'Sentadilla con barra',
    exerciseIndex: 0,
    exerciseCount: 5,
    dayName: 'Empuje',
    sets: [
      SetSpec(weightKg: 60, reps: 12),
      SetSpec(weightKg: 60, reps: 12),
      SetSpec(weightKg: 70, reps: 10),
      SetSpec(weightKg: 70, repsMin: 8, repsMax: 10),
    ],
    loggedSetNumbers: {1},
  );

  @override
  Widget build(BuildContext context) => WearRoot(
        pairing: WearPairingState.ready,
        session: _session,
        workout: _muestraHoy,
        plans: _muestraPlanes,
        templates: _muestraPlantillas,
        selectedRoutine: _selected,
        onStartToday: () => setState(() => _session = _sesionInicial),
        onSelectRoutine: (r, k) => setState(() => _selected = (r, k)),
        onCloseDetail: () => setState(() => _selected = null),
        onStartRoutine: () => setState(() {
          _selected = null;
          _session = _sesionInicial;
        }),
        onActivateRoutine: () => setState(() => _selected = null),
        // Ésta es la línea que faltaba y hacía que "no funcionaran los
        // botones": el tap arrancaba el descanso y nadie marcaba nunca la
        // serie, así que el círculo era imposible de llenar.
        onLogSet: (n) => setState(() => _session = _session?.withLogged(n)),
      );
}
