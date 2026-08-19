//
//  Haptics.swift
//  TreinoWatch Watch App
//
//  El unico lugar que hace vibrar el reloj.
//
//  Antes de esto la app NO vibraba NUNCA: ni el descanso ni nada. El atleta
//  tenia que mirar la pantalla para enterarse de que el descanso habia
//  terminado, que es exactamente lo que un reloj viene a evitar.
//
//  Va aislado en su propio archivo porque `WKInterfaceDevice` es watchOS-only:
//  metido adentro del coordinator lo dejaria sin poder compilarse en el host,
//  que es la unica forma barata de testear la logica.
//

import WatchKit

enum Haptics {

    /// Termino un descanso: es momento de volver a la barra.
    ///
    /// `.notification` y no `.success`: el descanso no es un logro, es un
    /// aviso. Y se distingue del otro por diseno — dos hapticos identicos para
    /// dos eventos distintos no informan nada.
    static func restFinished() {
        WKInterfaceDevice.current().play(.notification)
    }

    /// Termino un ejercicio por tiempo Y quedo marcado como hecho.
    ///
    /// `.success` porque aca SI se completo algo: la serie se cargo sola.
    static func durationSetCompleted() {
        WKInterfaceDevice.current().play(.success)
    }
}
