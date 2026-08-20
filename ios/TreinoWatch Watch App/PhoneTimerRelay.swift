//
//  PhoneTimerRelay.swift
//  TreinoWatch Watch App
//
//  El reloj le pide al TELEFONO que corte el cronometro que arranco alla.
//
//  ── Por que hace falta un canal nuevo ───────────────────────────────────
//
//  El reloj ya le manda al telefono su esfuerzo por `updateApplicationContext`
//  (`EffortRelay`), pero eso es ESTADO: "esto es lo que estoy midiendo ahora".
//  Esto otro es una ORDEN puntual sobre algo que vive del otro lado, y una
//  orden que se colapsa o llega tarde no sirve — cancelar una serie diez
//  minutos despues no cancela nada, marca otra cosa.
//
//  Por eso va por `sendMessage`, igual que el camino de ida.
//
//  ── Y por que la entrega SE MIRA ────────────────────────────────────────
//
//  `sendMessage` exige que el telefono este alcanzable AHORA. Si no llega, el
//  telefono sigue contando y va a MARCAR la serie al llegar a cero — mientras
//  el atleta cree que la cancelo. Eso es peor que no ofrecer cancelar.
//
//  Es la misma leccion que ya costo `WorkoutCloseFailure`: abandonar el entreno
//  sin conectividad era un no-op SILENCIOSO. Aca se usa la variante con
//  `errorHandler` y el resultado se le muestra al atleta.
//

import Foundation
import os
import WatchConnectivity

@MainActor
final class PhoneTimerRelay {

    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "phone-timer"
    )

    /// Le pide al telefono que corte su cronometro.
    ///
    /// `fallo` se llama SOLO si no llego. No hay callback de exito, y no es un
    /// olvido: `WCSession` no ofrece uno sin `replyHandler`, y con
    /// `replyHandler` esto no funcionaria en absoluto — ver abajo.
    ///
    /// ⚠️ **`replyHandler` tiene que ser nil.** Apple exige que, si el emisor
    /// pasa un `replyHandler`, la contraparte implemente
    /// `session(_:didReceiveMessage:replyHandler:)`. Del lado del telefono el
    /// receptor es el plugin `watch_connectivity`, y ese implementa SOLO la
    /// variante sin reply
    /// (`WatchConnectivityPlugin.swift:72`, verificado en la version 0.2.8
    /// instalada). Con un `replyHandler` puesto, TODOS los envios caerian en el
    /// `errorHandler` y "Cancelar" diria siempre que no se pudo, incluso
    /// habiendo llegado.
    func cancelar(
        exerciseId: String,
        setNumber: Int,
        fallo: @escaping @MainActor () -> Void
    ) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else {
            log.notice("Cancelacion NO enviada: la sesion WC no esta activada")
            fallo()
            return
        }

        // Sin alcanzabilidad `sendMessage` falla igual, pero se consulta antes
        // para no depender de que el error llegue: el errorHandler puede tardar
        // y el atleta esta mirando la pantalla.
        guard WCSession.default.isReachable else {
            log.notice("Cancelacion NO enviada: el telefono no esta alcanzable")
            fallo()
            return
        }

        WCSession.default.sendMessage(
            PhoneTimerMirror.cancelRequestMessage(
                exerciseId: exerciseId,
                setNumber: setNumber
            ),
            replyHandler: nil,
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.log.error(
                        "El telefono no recibio la cancelacion: \(error.localizedDescription, privacy: .public)"
                    )
                    fallo()
                }
            }
        )
    }
}
