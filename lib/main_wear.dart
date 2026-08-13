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
import 'features/watch/presentation/wear/wear_rest_screen.dart';

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

  @override
  Widget build(BuildContext context) => const WearRestScreen();
}
