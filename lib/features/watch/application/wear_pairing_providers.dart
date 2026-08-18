import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wear_credential_exchanger.dart';
import '../data/wear_credential_receiver.dart';
import '../domain/wear_credential.dart';
import '../presentation/wear/wear_view_models.dart';
import 'watch_bridge_provider.dart';

/// Costura sobre `FirebaseAuth`. Se sobreescribe en tests vía overrides.
final wearCredentialExchangerProvider = Provider<WearCredentialExchanger>(
  (ref) => WearCredentialExchanger(),
);

/// El uid de la sesión del reloj a lo largo del tiempo.
final wearAuthUidProvider = StreamProvider<String?>(
  (ref) => ref.watch(wearCredentialExchangerProvider).uidChanges,
);

// ── De dónde sale la credencial ──────────────────────────────────────────────
//
// Éste fue el punto de corte entre A1 y A2, y es la razón por la que las dos
// incógnitas se pudieron atacar por separado: el canje primero, con el token
// entrando a mano, y el transporte después.
//
// Hoy manda la Data Layer. El `--dart-define` sigue existiendo como BANCO DE
// PRUEBAS, no como camino de producción: es lo único que permite ejercitar el
// canje entero en un reloj SIN teléfono al lado — o, al revés, decidir en una
// corrida si lo que falló fue el transporte o el canje. Perderlo sería perder
// la mitad del instrumental de diagnóstico.
//
// Para conseguir un token a mano, con los emuladores arriba:
//   firebase emulators:start --only firestore,auth,functions
//   # y desde functions/, mintear para el atleta de prueba con el Admin SDK.

const _tokenInyectado = String.fromEnvironment('WEAR_CUSTOM_TOKEN');
const _uidInyectado = String.fromEnvironment('WEAR_UID');

/// El adaptador de la Data Layer. Se sobreescribe en tests.
final wearCredentialReceiverProvider = Provider<WearCredentialReceiver>(
  (ref) => WearCredentialReceiver(bridge: ref.watch(watchBridgeProvider)),
);

/// La credencial que llega al reloj.
///
/// Sale de la Data Layer, salvo que se hayan pasado los dos `--dart-define`,
/// en cuyo caso gana el token inyectado y el transporte ni se toca. La
/// inyección es EXPLÍCITA por definición —hay que escribirla en la línea de
/// build— así que respetarla no puede sorprender a nadie, y deja el camino real
/// como default.
///
/// Si no hay ninguno de los dos, el stream no emite y el reloj se queda en
/// `waitingForPairing`, que es exactamente lo que tiene que pasar mientras el
/// teléfono no haya publicado nada.
final wearCredentialSourceProvider = StreamProvider<WearCredential>((ref) {
  if (_tokenInyectado.isNotEmpty && _uidInyectado.isNotEmpty) {
    debugPrint('[wear-pairing] credencial inyectada por --dart-define '
        '(uid=$_uidInyectado) — la Data Layer NO se consulta');
    return Stream.value(
      const WearCredential(customToken: _tokenInyectado, uid: _uidInyectado),
    );
  }
  return ref.watch(wearCredentialReceiverProvider).credentials;
});

/// Estado del emparejamiento. Manda sobre toda la app del reloj.
final wearPairingProvider =
    NotifierProvider<WearPairingNotifier, WearPairingState>(
  WearPairingNotifier.new,
);

/// Decide si el reloj tiene credencial viva, y la consigue si no.
///
/// ## El orden es la regla
///
/// **La sesión de Firebase manda; la credencial que llega es secundaria.**
///
/// Firebase persiste la sesión entre arranques, y el DataItem que transporta el
/// token persiste para SIEMPRE del otro lado. Como el customToken dura una
/// hora, un reloj que canjeara el payload persistido en cada arranque mostraría
/// `failed` cada vez que pasaran 60 minutos desde el último minteo — con una
/// sesión perfectamente válida en la mano.
///
/// Por eso: primero se mira si ya hay sesión, y sólo se canjea si la credencial
/// que llegó es de OTRO atleta.
///
/// ## Un solo escritor para `ready`
///
/// `ready` lo escribe únicamente [_alCambiarUid], nunca el retorno del canje.
/// Es a propósito, y viene de la lección más cara del ciclo de Apple
/// (HANDOFF §4.5, tres bugs seguidos): no preguntarse "¿ya pasó el stream?",
/// sino hacer que el camino sea IDEMPOTENTE. Con un solo escritor, que el canje
/// y el stream de auth lleguen en cualquier orden da lo mismo.
class WearPairingNotifier extends Notifier<WearPairingState> {
  var _muerto = false;

  @override
  WearPairingState build() {
    ref.onDispose(() => _muerto = true);

    ref.listen<AsyncValue<String?>>(
      wearAuthUidProvider,
      (_, next) => next.whenData(_alCambiarUid),
    );

    ref.listen<AsyncValue<WearCredential>>(
      wearCredentialSourceProvider,
      (_, next) => next.whenData(_alLlegarCredencial),
    );

    // Estado inicial SÍNCRONO, sin esperar ningún stream: si Firebase ya tiene
    // sesión de un arranque anterior, el reloj arranca usable en vez de
    // parpadear "abrí la app en el teléfono".
    return ref.read(wearCredentialExchangerProvider).currentUid == null
        ? WearPairingState.waitingForPairing
        : WearPairingState.ready;
  }

  void _alCambiarUid(String? uid) {
    if (_muerto) return;

    if (uid != null) {
      state = WearPairingState.ready;
      return;
    }

    // Se cerró la sesión. Un canje en vuelo no se pisa: su propio resultado
    // manda, y `signInWithCustomToken` emite un null intermedio en algunas
    // versiones del SDK. Pisarlo acá haría parpadear la pantalla de espera en
    // el medio de un canje que va bien.
    if (state != WearPairingState.exchanging) {
      state = WearPairingState.waitingForPairing;
    }
  }

  Future<void> _alLlegarCredencial(WearCredential credencial) async {
    if (_muerto) return;

    final exchanger = ref.read(wearCredentialExchangerProvider);

    // Ya hay sesión de este mismo atleta: el token no aporta nada y lo más
    // probable es que esté vencido. Ver el encabezado de la clase.
    if (exchanger.currentUid == credencial.uid) {
      state = WearPairingState.ready;
      return;
    }

    state = WearPairingState.exchanging;
    try {
      await exchanger.exchange(credencial.customToken);
      // `ready` NO se escribe acá a propósito: lo hace `_alCambiarUid` cuando
      // Firebase confirma la sesión. Ver el encabezado de la clase.
    } catch (e) {
      debugPrint('[wear-pairing] canje rechazado — $e');
      if (!_muerto) state = WearPairingState.failed;
    }
  }
}
