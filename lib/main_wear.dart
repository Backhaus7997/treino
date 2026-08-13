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
import 'features/watch/presentation/wear/wear_workout_screen.dart';
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
  @override
  void initState() {
    super.initState();
    // Sin esto la app se congela con la muñeca baja: medido, 22.6% de
    // cobertura del tiempo despierto contra 100.0% con el servicio puesto.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(wearWorkoutServiceProvider).startWorkout();
    });
  }

  /// Entreno de muestra.
  ///
  /// TODO(wear): reemplazar por la sesión real. Falta la cadena entera —
  /// credencial minteada por el teléfono, Firestore, resolución del entreno del
  /// día. Existe para poder MIRAR la pantalla y validar el diseño contra la de
  /// watchOS antes de invertir en esa cadena.
  static const _muestra = WearWorkoutSnapshot(
    exerciseName: 'Sentadilla con barra',
    exerciseIndex: 0,
    exerciseCount: 5,
    dayName: 'Día 3',
    sets: [
      SetSpec(weightKg: 60, reps: 12),
      SetSpec(weightKg: 60, reps: 12),
      SetSpec(weightKg: 70, reps: 10),
      SetSpec(weightKg: 70, repsMin: 8, repsMax: 10),
    ],
    loggedSetNumbers: {1},
  );

  @override
  Widget build(BuildContext context) => const WearWorkoutScreen(
        snapshot: _muestra,
        // Sin ExerciseClient todavía: los dos en null, así que la fila de
        // esfuerzo NO se dibuja. Es el comportamiento correcto, no un bug.
        effort: WearEffort(),
      );
}
