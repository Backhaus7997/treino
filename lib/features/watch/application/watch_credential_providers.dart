import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../firebase_options.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../data/watch_bridge.dart';
import '../data/watch_credential_service.dart';
import '../data/watch_launcher_service.dart';
import '../data/watch_nudge_service.dart';
import '../data/watch_timer_service.dart';

/// Envoltorio sobre `WatchConnectivity`. Se sobreescribe en tests vía
/// `ProviderScope.overrides`.
final watchBridgeProvider = Provider<WatchBridge>((ref) => WatchBridge());

/// Instancia de Cloud Functions en la región donde vive `mintWatchCredential`.
///
/// Se declara acá y no se reusa `cloudFunctionsProvider` de `coach_hub` a
/// propósito: `watch/` no debe depender de un feature de dominio. Ambos apuntan
/// a la misma región, que es la que usa todo callable del proyecto.
final watchCloudFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
);

/// Servicio que le consigue credencial propia al reloj y se la entrega.
///
/// `apiKey` y `projectId` viajan en el payload porque el reloj habla HTTP
/// directo contra Firebase, sin SDK (Locked Decision #9): sin ellos no puede
/// canjear el token ni renovar después. No son secretos — son identificadores
/// públicos del proyecto; la seguridad la dan las Security Rules y App Check.
final watchCredentialServiceProvider = Provider<WatchCredentialService>((ref) {
  final options = DefaultFirebaseOptions.currentPlatform;
  // Corriendo contra el emulador hay que decirle al reloj dónde autenticarse:
  // por defecto le habla a la Firebase real, y un custom token minteado
  // localmente vuelve 400 desde producción. El lado Swift solo honra este host
  // en builds de debug.
  const useEmulator = bool.fromEnvironment('USE_EMULATOR');
  return WatchCredentialService(
    functions: ref.watch(watchCloudFunctionsProvider),
    bridge: ref.watch(watchBridgeProvider),
    apiKey: options.apiKey,
    projectId: options.projectId,
    authEmulatorHost: useEmulator ? 'http://localhost:9099' : null,
    // Puerto DISTINTO al de Auth. Reusar uno para el otro da 404 mudo.
    firestoreEmulatorHost: useEmulator ? 'http://localhost:8080' : null,
  );
});

/// Entrega credencial al reloj cada vez que hay un usuario autenticado.
///
/// Se lee de forma eager en `app.dart`, mismo patrón que `fcmLifecycleProvider`
/// (ADR-PN-003). Sin ese `ref.read`, todo el handoff es código muerto: el
/// servicio existe pero nadie lo llama, y el reloj se queda esperando para
/// siempre.
///
/// Reenviar en cada arranque es intencional y barato: el servicio corta solo si
/// no hay reloj emparejado, y el lado Swift no re-canjea si ya tiene credencial
/// del mismo uid. Así se cubre el caso de emparejar el reloj DESPUÉS de haber
/// iniciado sesión, que si no quedaría sin credencial hasta el próximo login.
/// Servicio que le avisa al reloj que relea.
final watchNudgeServiceProvider = Provider<WatchNudgeService>(
  (ref) => WatchNudgeService(bridge: ref.watch(watchBridgeProvider)),
);

/// Servicio que ABRE la app del reloj al arrancar un entreno desde el teléfono.
///
/// Separado de [watchNudgeServiceProvider] porque el nudge exige
/// alcanzabilidad y este caso es justo el contrario: el reloj está cerrado.
final watchLauncherServiceProvider = Provider<WatchLauncherService>(
  (ref) => WatchLauncherService(bridge: ref.watch(watchBridgeProvider)),
);

/// Servicio que espeja en el reloj el cronómetro arrancado en el teléfono.
///
/// Separado de [watchNudgeServiceProvider] aunque comparta canal y guardas: un
/// nudge le pide al reloj que RELEA Firestore, y esto le pide que MUESTRE algo
/// que el teléfono ya sabe. Mezclarlos haría que un cambio en la política de
/// recarga arrastrara al cronómetro sin quererlo.
final watchTimerServiceProvider = Provider<WatchTimerService>(
  (ref) => WatchTimerService(bridge: ref.watch(watchBridgeProvider)),
);

/// Avisa al reloj cada vez que cambia la rutina activa del atleta.
///
/// El reloj no tiene listeners de Firestore, así que sin esto un cambio hecho
/// desde el teléfono recién se veía al cambiar de página en la muñeca. El
/// dueño lo notó probando: activar DESDE el reloj era instantáneo y desde el
/// celular no.
///
/// Se engancha al perfil y no a cada botón a propósito: la rutina activa se
/// cambia desde la sección RUTINAS, desde el editor al crear una, y desde la
/// adopción perezosa de `unifiedRoutinesProvider`. Escuchar el campo cubre las
/// tres sin repetir la llamada en cada lugar ni olvidarse de una nueva.
///
/// Se lee de forma eager en `app.dart`, igual que el lifecycle de credencial.
final watchActiveRoutineNudgeProvider = Provider<void>((ref) {
  ref.listen<String?>(
    userProfileProvider.select((a) => a.valueOrNull?.activeRoutineId),
    (previous, next) {
      // La PRIMERA emisión no es un cambio: es el valor que ya estaba cuando
      // se abrió la app. Avisarle al reloj ahí sería un mensaje por arranque
      // sin nada nuevo que contar.
      if (previous == null || previous == next) return;
      if (next == null || next.isEmpty) return;
      unawaited(ref.read(watchNudgeServiceProvider).nudge());
    },
  );
});

/// Si vale la pena volver a intentar la entrega de la credencial.
///
/// `notSupported` es lo único definitivo: la plataforma no soporta relojes y
/// eso no cambia en caliente. `delivered` tampoco se reintenta, obviamente. Los
/// otros TRES son transitorios:
///
/// - `deliveryFailed` es el caso del HANDOFF §8.6:
///   `WCErrorCodeWatchAppNotInstalled` mientras el companion todavía se está
///   instalando en la muñeca. Se resuelve solo en minutos.
/// - `mintFailed` es red, App Check o la CF caída. También pasa.
/// - `noWatchPaired` es el caso NUEVO, y estaba mal clasificado. Ver abajo.
///
/// ⚠️ POR QUÉ `noWatchPaired` PASÓ A REINTENTABLE.
///
/// Antes no lo era, con este motivo escrito: reintentar "sería un viaje a la
/// Cloud Function en cada foreground de la enorme mayoría de usuarios, que no
/// tienen reloj". **Ese motivo es falso.** `WatchCredentialService
/// .deliverCredential` chequea `isPaired` y corta ANTES de tocar
/// `_functions`: un reintento sin reloj emparejado cuesta un MethodChannel, no
/// una invocación de la CF. La política se estaba pagando cara sin recibir
/// nada.
///
/// Y el costo de tenerlo mal clasificado sí era real, por dos lados:
///
/// 1. La race de activación (HANDOFF §8.6). `WCSession.activate()` es
///    asíncrono y el plugin lo dispara en su `init`
///    (`watch_connectivity-0.2.8`, `WatchConnectivityPlugin.swift:15-19`).
///    Antes de que active, `isPaired` devuelve el `?? false` de
///    `Self.session?.isPaired` — o sea false aunque el reloj esté ahí. Si la
///    primera entrega caía en esa ventana, el atleta quedaba sin credencial y
///    **nadie volvía a intentar nunca**.
/// 2. Emparejar el reloj con la app abierta. Volvía a primer plano y seguía sin
///    credencial hasta el próximo arranque en frío.
@visibleForTesting
bool watchCredentialShouldRetry(WatchCredentialOutcome outcome) =>
    outcome == WatchCredentialOutcome.deliveryFailed ||
    outcome == WatchCredentialOutcome.mintFailed ||
    outcome == WatchCredentialOutcome.noWatchPaired;

/// Cuántas veces más se re-chequea el emparejamiento ante `noWatchPaired`
/// ANTES de creerle, en el arranque.
///
/// Existe por la race de activación: en el arranque en frío la primera entrega
/// puede correr antes de que `WCSession` termine de activar, y ahí `isPaired`
/// miente. El reintento por resume no alcanza para cubrirla — en un arranque
/// normal el atleta abre la app y la usa, así que **el resume puede no llegar
/// nunca en toda la sesión**.
///
/// Dos es de sobra: la activación tarda milisegundos. El costo si el atleta
/// realmente no tiene reloj son dos MethodChannel más, repartidos en cuatro
/// segundos y fuera del camino crítico.
@visibleForTesting
const int watchPairingRaceRetries = 2;

/// Cuánto se espera entre re-chequeos del emparejamiento.
@visibleForTesting
const Duration watchPairingRaceDelay = Duration(seconds: 2);

/// Cómo esperar entre reintentos.
///
/// Va por provider por la misma razón que [appResumeHookProvider]: inyectable,
/// el reintento se puede MEDIR. Con un `Future.delayed` clavado, el test de la
/// race tardaría cuatro segundos reales o habría que testear la política en vez
/// de la conducta.
typedef WatchRetryDelay = Future<void> Function(Duration);

final watchRetryDelayProvider = Provider<WatchRetryDelay>(
  (ref) => (espera) => Future<void>.delayed(espera),
);

/// Registra un callback para cuando la app vuelve a primer plano.
typedef AppResumeHook = void Function(void Function() onResume);

/// Cómo engancharse a que la app vuelva a primer plano.
///
/// Va por provider y no con un `AppLifecycleListener` suelto por dos razones,
/// las dos aprendidas al escribir esto:
///
/// 1. `AppLifecycleListener` exige `WidgetsBinding.instance`, así que crearlo
///    dentro del provider lo vuelve ILEGIBLE desde un test unitario — rompía
///    tres tests que ya existían.
/// 2. Inyectable, el reintento se puede MEDIR: el test dispara el resume a mano
///    y verifica que se reintentó. Con el listener real solo se podría testear
///    la política, no la conducta.
final appResumeHookProvider = Provider<AppResumeHook>((ref) {
  return (onResume) {
    final listener = AppLifecycleListener(onResume: onResume);
    ref.onDispose(listener.dispose);
  };
});

final watchCredentialLifecycleProvider = Provider<void>((ref) {
  // Lo último que pasó, para no reintentar cuando no hace falta.
  var ultimo = WatchCredentialOutcome.notSupported;
  var enVuelo = false;

  /// [reintentosDeRace] es cuántas veces se vuelve a chequear el
  /// emparejamiento ante un `noWatchPaired`, para no creerle a un `isPaired`
  /// que respondió antes de que `WCSession` activara.
  ///
  /// Solo el arranque los usa. Al volver a primer plano van en 0: la app lleva
  /// rato viva y la sesión hace rato que activó, así que ahí un `false` es un
  /// `false` de verdad.
  Future<void> entregar(String uid, {int reintentosDeRace = 0}) async {
    if (enVuelo) return;
    enVuelo = true;

    // Se resuelven ANTES del bucle: entre reintento y reintento hay una espera,
    // y leer un `ref` de un container ya dispuesto explota.
    final servicio = ref.read(watchCredentialServiceProvider);
    final esperar = ref.read(watchRetryDelayProvider);

    try {
      var reintentos = 0;
      while (true) {
        try {
          ultimo = await servicio.deliverCredential(uid: uid);
        } catch (_) {
          ultimo = WatchCredentialOutcome.deliveryFailed;
        }

        // El bucle es SOLO para la race de emparejamiento. Los otros fallos
        // transitorios ya tienen su reintento por resume, y machacarlos acá
        // sería pegarle a la CF tres veces seguidas por nada.
        if (ultimo != WatchCredentialOutcome.noWatchPaired) return;
        if (reintentos >= reintentosDeRace) return;

        reintentos++;
        await esperar(watchPairingRaceDelay);
      }
    } finally {
      enVuelo = false;
    }
  }

  ref.listen<AsyncValue<User?>>(
    authStateChangesProvider,
    (prev, next) {
      next.whenData((user) {
        if (user == null) return;
        // Fire-and-forget: esto corre en el camino crítico del arranque, así
        // que no se lo hace esperar ni se le deja tirar. Quedarse sin
        // credencial de reloj es una degradación aceptable; tumbar la app por
        // eso, no.
        //
        // Es el ÚNICO camino que usa los reintentos de race: es acá donde la
        // entrega puede ganarle a `WCSession.activate()`.
        unawaited(
            entregar(user.uid, reintentosDeRace: watchPairingRaceRetries));
      });
    },
    fireImmediately: true,
  );

  // ── Reintento al volver a primer plano (HANDOFF §8.6) ────────────────────
  //
  // La entrega era de UN SOLO DISPARO, atada al cambio de estado de sesión —
  // o sea, en la práctica, al arranque en frío. Si fallaba ahí, el atleta se
  // quedaba sin credencial en el reloj hasta desloguearse o reinstalar, y el
  // companion no podía hacer NADA: sin credencial no habla Firestore.
  //
  // El caso típico es el más frustrante: instalás la app del reloj desde el
  // teléfono, la entrega sale antes de que el companion termine de instalarse,
  // `updateApplicationContext` tira `WatchAppNotInstalled`, y nadie vuelve a
  // intentar. La muñeca queda inservible hasta que se te ocurre reinstalar.
  //
  // El disparador correcto sería un evento de `WCSession` (activación,
  // `sessionWatchStateDidChange`), pero el plugin NO los expone a Dart: su
  // `SessionDelegate` los tiene vacíos. El mejor evento que sí tenemos es
  // volver a primer plano, que además es exactamente cuando el atleta acaba de
  // terminar de instalar la app en el reloj y vuelve al teléfono.
  //
  // Solo reintenta si lo último fue un fallo TRANSITORIO. `noWatchPaired`
  // ahora cuenta como transitorio —ver el porqué en
  // `watchCredentialShouldRetry`— y cubre el caso de emparejar el reloj con la
  // app ya abierta. `notSupported` no: esa plataforma no va a tener reloj
  // nunca, y ahí sí el reintento sería ruido para siempre.
  //
  // Sin reintentos de race acá: la app lleva rato viva, `WCSession` hace rato
  // que activó, y un `isPaired` false en este punto es cierto.
  ref.read(appResumeHookProvider)(() {
    if (!watchCredentialShouldRetry(ultimo)) return;
    final user = ref.read(authStateChangesProvider).valueOrNull;
    if (user == null) return;
    unawaited(entregar(user.uid));
  });
});
