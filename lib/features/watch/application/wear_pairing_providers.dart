import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/wear_credential_exchanger.dart';
import '../domain/wear_credential.dart';
import '../presentation/wear/wear_view_models.dart';

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
// Éste es el punto de corte entre A1 y A2, y la razón por la que las dos
// incógnitas se pueden atacar por separado.
//
//   A1 (acá): el token entra por --dart-define. Cero transporte, así que un
//             fallo sólo puede ser del canje. Es lo que se quiere aislar.
//   A2:       este mismo provider se sobreescribe por el adaptador de la Data
//             Layer, que siembra con `receivedApplicationContexts` y mergea
//             `contextStream`. La máquina de estados no se entera.
//
// Para conseguir un token a mano, con los emuladores arriba:
//   firebase emulators:start --only firestore,auth,functions
//   # y desde functions/, mintear para el atleta de prueba con el Admin SDK.

const _tokenInyectado = String.fromEnvironment('WEAR_CUSTOM_TOKEN');
const _uidInyectado = String.fromEnvironment('WEAR_UID');

/// La credencial que llega al reloj.
///
/// En A1 emite a lo sumo UNA vez, y sólo si se pasaron los dos `--dart-define`.
/// Sin ellos el stream queda vacío y el reloj se queda en `waitingForPairing`,
/// que es exactamente lo que tiene que pasar en un reloj sin teléfono.
final wearCredentialSourceProvider = StreamProvider<WearCredential>((ref) {
  if (_tokenInyectado.isEmpty || _uidInyectado.isEmpty) {
    return const Stream<WearCredential>.empty();
  }
  debugPrint('[wear-pairing] credencial inyectada por --dart-define '
      '(uid=$_uidInyectado)');
  return Stream.value(
    const WearCredential(customToken: _tokenInyectado, uid: _uidInyectado),
  );
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
