//
//  CountdownRules.swift
//  TreinoWatch Watch App
//
//  Cuanto falta de una cuenta regresiva, y si termino.
//
//  ── Por que por RELOJ DE PARED y no por ticks ───────────────────────────
//
//  El temporizador de descanso que ya existe decrementa un contador con un
//  `Timer` de un segundo (`WorkoutCoordinator.startRest`). Funciona porque el
//  modo `workout-processing` mantiene la app viva, pero si el sistema la
//  estrangula —bateria baja, muneca abajo, otra app en primer plano— los ticks
//  se pierden y el contador se ATRASA.
//
//  Para el descanso eso es tolerable. Para un ejercicio POR TIEMPO no: una
//  plancha de 60 segundos que dura 70 no es la misma serie, y el atleta no
//  tiene como notarlo. Guardando el instante de fin y restando contra `Date()`
//  la cuenta es correcta aunque no se ejecute un solo tick.
//
//  La regla vive aparte y pura para medirla en el host.
//

import Foundation

enum CountdownRules {

    /// Segundos que faltan, nunca negativos.
    ///
    /// Se redondea hacia ARRIBA: mientras quede una fraccion de segundo, la
    /// serie no termino. Mostrar 0 con tiempo restante seria mentir, y peor:
    /// invitaria a cortar antes.
    static func remaining(endsAt: Date, now: Date) -> Int {
        let falta = endsAt.timeIntervalSince(now)
        if falta <= 0 { return 0 }
        return Int(falta.rounded(.up))
    }

    /// Si la cuenta llego a cero.
    static func isFinished(endsAt: Date, now: Date) -> Bool {
        remaining(endsAt: endsAt, now: now) == 0
    }

    /// El texto de la cuenta, en el minimo de caracteres legible de reojo.
    ///
    /// Bajo un minuto va sin cero a la izquierda: en una pantalla de 40mm cada
    /// caracter cuenta, y "45" se lee de un vistazo mejor que "0:45".
    static func display(remaining segundos: Int) -> String {
        guard segundos >= 60 else { return "\(segundos)" }
        let minutos = segundos / 60
        let resto = segundos % 60
        return String(format: "%d:%02d", minutos, resto)
    }
}
