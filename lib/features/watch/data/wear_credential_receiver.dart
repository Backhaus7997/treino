import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../domain/watch_credential_payload.dart';
import '../domain/wear_credential.dart';
import 'watch_bridge.dart';

/// De dónde saca el reloj la credencial que le mintea el teléfono.
///
/// Es el transporte de la fase A2: traduce lo que llega por la Data Layer API
/// a [WearCredential] y se lo entrega a la máquina de emparejamiento, que no se
/// entera de que existe un cable.
///
/// ── Por qué SIEMBRA antes de escuchar ─────────────────────────────────────
///
/// Es la decisión que hace o rompe el arranque en frío, y no es simetría
/// estética: los dos lados corren en momentos distintos. El teléfono publica la
/// credencial en cuanto el atleta inicia sesión, o sea MUCHO antes de que nadie
/// abra la app del reloj. Ese DataItem persiste.
///
/// Pero `contextStream` no reproduce el pasado: el plugin sólo reenvía eventos
/// `TYPE_CHANGED` que le llegan con el listener ya enganchado
/// (`onDataChanged` en `WatchConnectivityPlugin.kt`). Un reloj que sólo
/// escuchara el stream se quedaría esperando PARA SIEMPRE una credencial que ya
/// estaba escrita — y el síntoma sería el peor: la pantalla "abrí TREINO en el
/// teléfono", con el teléfono abierto y todo funcionando del otro lado.
///
/// Por eso primero se lee [WatchBridge.receivedApplicationContexts], que sí
/// devuelve lo que ya está, y recién después se sigue con el vivo.
///
/// ── Por qué se engancha al vivo ANTES de sembrar ──────────────────────────
///
/// Sembrar es un `await`, y en esa ventana puede llegar un contexto nuevo. Si
/// el `listen` viniera después, ese evento se perdería sin dejar rastro. Se
/// engancha primero y se BUFFEREA en un controller de una sola suscripción, que
/// guarda lo que llegue hasta que alguien lo consuma.
///
/// ── Por qué nada de esto tira ─────────────────────────────────────────────
///
/// Cada falla se loguea y se sigue. Un payload roto, o una semilla que no se
/// pudo leer, NO pueden terminar el stream: si terminara, el reloj perdería la
/// única vía por la que puede conseguir sesión, y encima en silencio. Un
/// intento perdido se recupera con el próximo evento; un stream cerrado, no.
class WearCredentialReceiver {
  const WearCredentialReceiver({
    required WatchBridge bridge,
    this.seedTimeout = const Duration(seconds: 5),
  }) : _bridge = bridge;

  final WatchBridge _bridge;

  /// Cuánto se espera a que la semilla conteste antes de seguir sin ella.
  ///
  /// No es paranoia genérica: el plugin desreferencia `localNode` —un
  /// `lateinit` que se resuelve async— DENTRO del `addOnSuccessListener` de
  /// esta misma llamada. Si todavía no resolvió, la excepción se lanza después
  /// de que `onMethodCall` retornó, o sea que nadie llama a `result`: el
  /// `Future` de Dart no completa NUNCA.
  ///
  /// El tope no salva ese caso del todo —cuando la excepción llega al main
  /// looper sin handler, el proceso muere y no hay Dart que valga—, pero sí
  /// salva el otro: una semilla que se cuelga sin matar nada dejaría el canal
  /// EN VIVO sin consumir, y ahí el reloj se quedaría esperando una credencial
  /// que está entrando. Cinco segundos de arranque en frío contra eso es
  /// barato.
  final Duration seedTimeout;

  /// Las credenciales que va publicando el teléfono, la primera ya sembrada.
  ///
  /// No repite la última emitida: el mismo DataItem puede llegar por la semilla
  /// y por el stream, y canjear dos veces el mismo token es pedirle a Firebase
  /// una sesión que ya se está creando.
  /// Se compone con transformadores y NO con un `await for` dentro de un
  /// `async*`. Medido con un control: un generador suspendido en el `moveNext()`
  /// de un `await for` **no se puede cancelar** —el `cancel()` espera a que ese
  /// await complete, y en un stream vivo nunca completa—, así que descartar el
  /// provider dejaría la suscripción colgada para siempre. La cadena de
  /// transformadores sí propaga la cancelación.
  Stream<WearCredential> get credentials {
    WearCredential? ultima;
    return _contextos().map(_traducir).where((credencial) {
      // Filtra y recuerda en el mismo paso: el "ésta ya la vi" necesita estado,
      // y partirlo en dos closures sobre la misma variable no lo aclara.
      if (credencial == null || credencial == ultima) return false;
      ultima = credencial;
      debugPrint('[wear-pairing] credencial recibida por la Data Layer '
          '(uid=${credencial.uid})');
      return true;
    }).cast<WearCredential>();
  }

  /// Lo ya escrito y después lo que vaya llegando, sin agujero entre medio.
  Stream<Map<String, dynamic>> _contextos() async* {
    // El buffer es de UNA suscripción a propósito: así retiene todo lo que
    // llegue mientras se lee la semilla, en vez de descartarlo por no tener
    // oyente todavía.
    final buffer = StreamController<Map<String, dynamic>>();
    final suscripcion = _bridge.contextStream.listen(
      buffer.add,
      // Un error del EventChannel no puede matar el emparejamiento: se anota y
      // el canal sigue vivo para el próximo evento.
      onError: (Object e) =>
          debugPrint('[wear-pairing] el canal de contexto se quejó — $e'),
      onDone: () => unawaited(buffer.close()),
    );

    try {
      List<Map<String, dynamic>> semilla;
      try {
        semilla =
            await _bridge.receivedApplicationContexts.timeout(seedTimeout);
      } catch (e) {
        // Sospechoso número uno si esto aparece: el plugin desreferencia
        // `localNode` acá adentro, y es un `lateinit` que se resuelve async.
        // Si además el proceso se murió, buscá `UninitializedPropertyAccess`
        // en logcat antes de culpar al transporte.
        debugPrint('[wear-pairing] no se pudo leer la semilla — $e');
        semilla = const [];
      }
      debugPrint('[wear-pairing] semilla: ${semilla.length} contexto(s) ya '
          'publicados por el teléfono');

      yield* Stream.fromIterable(semilla);
      yield* buffer.stream;
    } finally {
      await suscripcion.cancel();
      // El `close()` NO se espera, y no es descuido. `StreamController.close()`
      // devuelve `done`, que sólo completa cuando alguien RECIBE el evento de
      // cierre — y acá se llega justo después de que el consumidor canceló, o
      // sea sin nadie del otro lado. Esperarlo cuelga para siempre: medido, los
      // siete tests del receiver se quedaban 30 s cada uno en el teardown, con
      // la lógica funcionando perfecto.
      unawaited(buffer.close());
    }
  }

  /// Traduce el contrato de cable a lo único que Wear necesita.
  ///
  /// `apiKey`, `projectId` y los hosts de emulador se DESCARTAN: existen para
  /// el companion de watchOS, que habla HTTP crudo. Acá el SDK los saca de
  /// `google-services.json`, y los hosts encima serían dañinos — vienen como
  /// `localhost`, que en un reloj físico es el reloj.
  ///
  /// Devuelve null en vez de tirar ante cualquier cosa que no sea una
  /// credencial usable. Por el mismo canal viaja lo que publique el reloj y
  /// cualquier payload futuro; un desconocido se ignora, no rompe.
  WearCredential? _traducir(Map<String, dynamic> contexto) {
    if (contexto['kind'] != WatchCredentialPayload.kind) return null;
    try {
      final payload = WatchCredentialPayload.fromJson(contexto);
      return WearCredential(
        customToken: payload.customToken,
        uid: payload.uid,
      );
    } on FormatException catch (e) {
      debugPrint('[wear-pairing] payload de credencial inservible — $e');
      return null;
    }
  }
}
