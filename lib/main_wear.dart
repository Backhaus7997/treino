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
/// Funciona en **debug y en profile**: el permiso de HTTP en claro vive en
/// `src/main/res/xml/` y lo referencian los manifests de los dos. El de release
/// NO lo referencia, así que un APK publicable sigue rechazando texto plano.
///
/// Para el reloj conviene **profile**, y no sólo por lo que dice el HANDOFF
/// §4.8 —debug es JIT y en un ARM de 32 bits explica buena parte de cualquier
/// lentitud percibida—: el APK de debug pesa 221 MB contra 57 en profile con
/// `--target-platform android-arm`, y esa transferencia por Wi-Fi al reloj se
/// corta a la mitad.
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

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme/app_theme.dart';
import 'features/watch/application/wear_session_providers.dart';
import 'features/auth/application/auth_providers.dart';
import 'features/watch/application/wear_pairing_providers.dart';
import 'features/watch/application/wear_routine_list_providers.dart';
import 'features/watch/application/wear_today_providers.dart';
import 'features/watch/presentation/wear/wear_root.dart';
import 'features/watch/presentation/wear/wear_view_models.dart';
import 'features/watch/presentation/wear/wear_workout_view_model.dart';
import 'firebase_options.dart';

/// Host de los emuladores visto DESDE el reloj.
///
/// `10.0.2.2` es la Mac vista desde un emulador de Android (incluido el de
/// Wear OS). En un reloj FÍSICO hay que tunelizar con adb y pasar `127.0.0.1`:
///
/// ```
/// adb -s <reloj> reverse tcp:8080 tcp:8080
/// adb -s <reloj> reverse tcp:9099 tcp:9099
/// flutter run ... --dart-define=EMULATOR_HOST=127.0.0.1
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
  runApp(
    ProviderScope(
      overrides: [
        // ── La costura que abre el dominio entero ────────────────────────────
        //
        // Casi TODA la capa de aplicación de workout/home es reusable tal cual:
        // no tiene UI adentro, no toca BuildContext y depende del uid como
        // parámetro. El único acoplamiento estructural al teléfono es este
        // provider, que por defecto pasa por `AuthService` — y ese constructor
        // arrastra google_sign_in y sign_in_with_apple, que en una muñeca no
        // se usan jamás.
        //
        // El reloj lee `FirebaseAuth` derecho. Con esta sola línea,
        // currentUidProvider → assignedRoutines → sessionsByUid →
        // todaysRoutine funcionan sin tocar una línea del dominio.
        authStateChangesProvider.overrideWith(
          (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
        ),
      ],
      child: const TreinoWearApp(),
    ),
  );
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
      // `automaticHostMapping: false` NO es opcional acá, y costó una corrida
      // en el reloj descubrirlo.
      //
      // FlutterFire reescribe el host a `10.0.2.2` cuando vale `localhost` O
      // `127.0.0.1`, y lo hace en TODO Android — no sólo en el emulador
      // (firebase_core/src/port_mapping.dart, `getMappedHost`). En un reloj
      // físico tunelizado con `adb reverse` eso rompe el túnel: la request sale
      // hacia una IP que en la muñeca no existe, y el error que llega no
      // nombra la reescritura, sólo dice
      // `Failed to connect to /10.0.2.2:9099`.
      //
      // Apagándola, [_emulatorHost] significa exactamente lo que dice.
      FirebaseFirestore.instance.useFirestoreEmulator(
        _emulatorHost,
        8080,
        automaticHostMapping: false,
      );
      await FirebaseAuth.instance.useAuthEmulator(
        _emulatorHost,
        9099,
        automaticHostMapping: false,
      );
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

/// La raíz de la app del reloj.
///
/// El foreground service NO se arranca acá: lo enciende `WearSessionNotifier`
/// cuando se abre un entreno, y lo apaga al cerrarlo. Antes arrancaba con el
/// emparejamiento —o sea al abrir la app— y eso dejaba una notificación
/// permanente y Health Services corriendo para mirar la pantalla de HOY, con
/// las calorías acumulando desde antes del entreno.
class _WearHome extends ConsumerStatefulWidget {
  const _WearHome();

  @override
  ConsumerState<_WearHome> createState() => _WearHomeState();
}

class _WearHomeState extends ConsumerState<_WearHome> {
  /// Rutina abierta en el detalle, o null.
  (WearRoutineSummary, WearRoutineListKind)? _selected;

  @override
  Widget build(BuildContext context) {
    final pairing = ref.watch(wearPairingProvider);

    // HOY ya sale de Firestore, y con los cuatro estados distinguibles: sin
    // esto, "no hay plan activo" se veía como un spinner eterno.
    final hoy = ref.watch(wearTodayStateProvider);

    // El entreno también. La pantalla recibe la VISTA del ejercicio actual,
    // proyectada del modelo completo en cada build: por eso el cursor avanza
    // solo y no hay ningún delta que mantener.
    // Las listas laterales, ya desde Firestore. Se componen a mano y NO con
    // `unifiedRoutinesProvider`, que escribe `activeRoutineId` al leerse.
    final planes = ref.watch(wearPlansProvider);
    final plantillas = ref.watch(wearTemplatesProvider);

    final entreno = ref.watch(wearSessionProvider);
    final snapshot = entreno is WearSessionRunning
        ? wearSnapshotFrom(entreno.session)
        : null;

    return WearRoot(
      pairing: pairing,
      session: snapshot,
      today: hoy,
      plans: planes,
      templates: plantillas,
      selectedRoutine: _selected,
      onStartToday: () {
        // Sólo se puede empezar lo que ya está resuelto. `start` adopta el
        // entreno que el teléfono tenga abierto antes de crear uno.
        if (hoy is WearTodayReady) {
          unawaited(
            ref.read(wearSessionProvider.notifier).start(hoy.workout),
          );
        }
      },
      onSelectRoutine: (r, k) => setState(() => _selected = (r, k)),
      onCloseDetail: () => setState(() => _selected = null),
      // TODO(wear): empezar desde una rutina de las listas laterales todavía no
      // resuelve su plan — las listas siguen siendo datos de muestra, así que
      // esas rutinas no existen. Se cablea junto con las listas.
      onStartRoutine: () => setState(() => _selected = null),
      onActivateRoutine: () => setState(() => _selected = null),
      onLogSet: (exerciseId, setNumber) => unawaited(
        ref.read(wearSessionProvider.notifier).logSet(
              exerciseId: exerciseId,
              setNumber: setNumber,
            ),
      ),
      onFinish: () =>
          unawaited(ref.read(wearSessionProvider.notifier).finish()),
      // La pantalla ya pidió confirmación antes de llegar acá.
      onAbandon: () =>
          unawaited(ref.read(wearSessionProvider.notifier).abandon()),
    );
  }
}
