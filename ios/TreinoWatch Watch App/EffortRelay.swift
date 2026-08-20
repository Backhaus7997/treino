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
    func publish(
        bpm: Int?,
        kcal: Int?,
        measuredAt: Date,
        timer: EffortSnapshot.RunningTimer? = nil,
        now: Date = Date()
    ) {
        let actual = EffortSnapshot(bpm: bpm, kcal: kcal, timer: timer)
        guard EffortBroadcastRules.shouldSend(last: last, actual: actual, now: now) else {
            return
        }

        // Sin sesion activada no hay a donde mandar. No se activa acá: de eso ya
        // se encarga `CredentialCoordinator`, que es el WCSessionDelegate.
        //
        // Se loguea el corte. Antes retornaba MUDO, y ese silencio es caro:
        // "el telefono no muestra nada" y "el reloj ni intento mandar" se ven
        // exactamente igual desde afuera.
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            log.notice("Esfuerzo NO publicado: la sesion WC no esta activada")
            return
        }

        do {
            try WCSession.default.updateApplicationContext(actual.context(measuredAt: measuredAt))
            last = (actual, now)
            // Se loguea el EXITO y no solo el fallo: sin esto, verificar el
            // relay de punta a punta es a ciegas — si el telefono no muestra
            // nada no se sabe si el reloj no mando o si el telefono no recibio.
            //
            // El cronometro va en el log porque es el dato mas dificil de
            // verificar de los tres: el pulso y las calorias se ven en la
            // pantalla del reloj, la cuenta espejada solo se ve en el telefono.
            let crono = timer.map { "serie \($0.setNumber) de \($0.exerciseId), \($0.totalSeconds)s" }
                ?? "sin cronometro"
            log.notice("Esfuerzo publicado al telefono: bpm \(bpm ?? -1), kcal \(kcal ?? -1), \(crono, privacy: .public)")
        } catch {
            // Que el telefono no reciba el dato no es un problema del entreno.
            // Se sigue; el proximo intento lo reintenta solo.
            //
            // Va a `.error` y no a `.debug`: `.debug` no se persiste por
            // defecto, asi que el unico caso en que ESTE log importa —mirar
            // despues por que no llego nada— era justo el que no quedaba
            // grabado.
            log.error("No se pudo publicar el esfuerzo: \(error.localizedDescription, privacy: .public)")
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
