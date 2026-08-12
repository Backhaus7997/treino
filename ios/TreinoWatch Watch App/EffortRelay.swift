//
//  EffortRelay.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F4.
//
//  Le manda al telefono lo que el reloj esta midiendo, para que si el atleta
//  agarra el celular a mitad de entreno los datos tambien esten ahi.
//
//  ES UN AGREGADO. Si esto falla —o si no hay telefono cerca— no pasa nada: el
//  reloj sigue mostrando todo en su pantalla, que es donde vive el dato.
//
//  ── Por que `updateApplicationContext` y NO `sendMessage` ─────────────────
//
//  Es la misma distincion que ya documenta `watch_nudge_service.dart` del lado
//  Dart, aplicada al reves:
//
//  `sendMessage` exige que la contraparte este alcanzable AHORA y falla si no.
//  Sirve para un aviso puntual que se puede perder.
//
//  `updateApplicationContext` es estado "actual": el sistema lo COLAPSA
//  quedandose con el ultimo valor y lo entrega cuando el telefono vuelve. Eso
//  es exactamente lo que se quiere para "a cuanto esta el pulso ahora" — si se
//  pierden tres actualizaciones intermedias no importa, importa la ultima.
//
//  NO PERSISTE NADA DEL LADO NUESTRO. El dato vive en el contexto de
//  WatchConnectivity mientras dura el entreno y muere ahi. D1 sigue intacta.
//

import Foundation
import os
import WatchConnectivity

@MainActor
final class EffortRelay {

    private var last: (payload: EffortSnapshot, at: Date)?

    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "effort-relay"
    )

    /// Publica el esfuerzo actual, si corresponde.
    ///
    /// La decision de si corresponde vive en `EffortBroadcastRules`, sin
    /// WatchConnectivity, para poder testearla en el host.
    func publish(bpm: Int?, kcal: Int?, measuredAt: Date, now: Date = Date()) {
        let actual = EffortSnapshot(bpm: bpm, kcal: kcal)
        guard EffortBroadcastRules.shouldSend(last: last, actual: actual, now: now) else {
            return
        }

        // Sin sesion activada no hay a donde mandar. No se activa acá: de eso ya
        // se encarga `CredentialCoordinator`, que es el WCSessionDelegate.
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            return
        }

        do {
            try WCSession.default.updateApplicationContext(actual.context(measuredAt: measuredAt))
            last = (actual, now)
        } catch {
            // Que el telefono no reciba el dato no es un problema del entreno.
            // Se loguea y se sigue; el proximo intento lo reintenta solo.
            log.debug("No se pudo publicar el esfuerzo: \(error.localizedDescription)")
        }
    }

    /// Olvida lo ultimo enviado.
    ///
    /// Se llama al cerrar el entreno para que el proximo arranque no se coma el
    /// primer envio por parecerse al ultimo del entreno anterior.
    func reset() {
        last = nil
    }
}
