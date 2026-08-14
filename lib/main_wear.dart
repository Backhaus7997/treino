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
/// Contra los emuladores de Firebase, y forzando el App Check de debug:
///
/// ```
/// flutter run -d <reloj> --flavor wear -t lib/main_wear.dart \
///   --dart-define=USE_EMULATOR=true \
///   --dart-define=EMULATOR_HOST=10.0.2.2 \
///   --dart-define=APPCHECK_DEBUG=true
/// ```
///
/// ⚠️ Ese combo sólo funciona en **debug**. El permiso de HTTP en claro vive en
/// `android/app/src/debug/`, así que un build de PROFILE no llega a los
/// emuladores: `src/profile/AndroidManifest.xml` declara INTERNET y nada más.
/// Para probar en profile —que es lo que pide el HANDOFF §4.8— hay que ir
/// contra PRODUCCIÓN, y ahí `APPCHECK_DEBUG=true` deja de ser opcional.
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

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme/app_theme.dart';
import 'features/watch/application/wear_rest_providers.dart';
import 'features/watch/presentation/wear/wear_root.dart';
import 'features/watch/presentation/wear/wear_view_models.dart';
import 'features/watch/presentation/wear/wear_workout_view_model.dart';
import 'features/workout/domain/set_spec.dart';
import 'firebase_options.dart';

/// Host de los emuladores visto DESDE el reloj.
///
/// `10.0.2.2` es la Mac vista desde un emulador de Android (incluido el de
/// Wear OS). En un reloj FÍSICO hay que tunelizar y pasar `localhost`:
///
/// ```
/// adb -s <reloj> reverse tcp:8080 tcp:8080
/// adb -s <reloj> reverse tcp:9099 tcp:9099
/// flutter run ... --dart-define=EMULATOR_HOST=localhost
/// ```
///
/// El túnel no es capricho: `network_security_config.xml` habilita HTTP en
/// claro para `10.0.2.2`, `127.0.0.1` y `localhost`, y para NADA más. Apuntar a
/// la IP LAN de la Mac se bloquea igual, y el error que llega
/// (`[firebase_auth/unknown] Cleartext HTTP traffic ... not permitted`) no dice
/// que el problema es la lista.
const _emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: '10.0.2.2',
);

const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// Fuerza el proveedor de App Check de DEBUG aunque el build no sea debug.
///
/// Hace falta porque el reloj se prueba en PROFILE (HANDOFF §4.8) y profile es
/// release-mode: `kDebugMode` da false, así que el reloj elegiría Play
/// Integrity — que NO puede atestar un APK sideloadeado con debug keys, y
/// `android/key.properties` no existe en esta máquina (HANDOFF §7.3).
const _appCheckDebug = bool.fromEnvironment('APPCHECK_DEBUG');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _arrancarFirebase();
  runApp(const ProviderScope(child: TreinoWearApp()));
}

/// Deja el reloj listo para hablar con Firebase por su cuenta.
///
/// Hasta ahora este entrypoint no inicializaba NADA: la UI corría con datos de
/// muestra y el único Firebase del feature vivía del lado teléfono. El camino
/// de acá ya está medido en un reloj físico (mediana de push 206 ms,
/// `fromCache=false`), pero se midió en `main_wear_spike.dart`, que es
/// throwaway. Esto lo muda al entrypoint que se buildea.
///
/// No tumba la app si falla: hoy nadie consume Firebase todavía y la pantalla
/// de muestra tiene que seguir viéndose igual. Pero grita, porque un arranque
/// mudo es exactamente lo que hizo indebuggeable la cadena del teléfono.
Future<void> _arrancarFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Antes que cualquier otra llamada a un servicio, para que todas las
    // requests lleven token. Sin esto el reloj manda CERO atestación en
    // cualquier modo, y como Firestore tiene enforcement activo en treino-dev
    // el síntoma sería: firma bien y después TODA lectura vuelve rechazada.
    //
    // La primera corrida imprime el debug token en logcat; hay que registrarlo
    // una vez por dispositivo en Firebase Console → App Check → Manage debug
    // tokens. El reloj y el emulador tienen tokens DISTINTOS.
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode || _appCheckDebug
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
    );

    if (_useEmulator) {
      // Los mismos puertos que `lib/main.dart`. El host se pasa explícito y no
      // se delega en la reescritura de FlutterFire (`localhost` → `10.0.2.2`)
      // porque esa reescritura sólo ocurre en el EMULADOR: en un reloj físico
      // `localhost` es el reloj y la request no sale nunca.
      FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
      await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
      debugPrint('[wear-boot] emuladores en $_emulatorHost (8080/9099)');
    }

    debugPrint(
      '[wear-boot] Firebase listo — appCheck='
      '${kDebugMode || _appCheckDebug ? 'debug' : 'playIntegrity'}, '
      'emulador=$_useEmulator',
    );
  } catch (e, stack) {
    debugPrint('[wear-boot] FALLÓ el arranque de Firebase — $e');
    debugPrint('$stack');
  }
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
