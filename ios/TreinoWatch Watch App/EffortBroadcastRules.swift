//
//  EffortBroadcastRules.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F4.
//
//  Cuando vale la pena mandarle al telefono lo que el reloj esta midiendo.
//
//  El reloj recolecta pulsaciones cada ~5 segundos. Mandar cada muestra seria
//  despertar al telefono decenas de veces por entreno para nada: el atleta mira
//  la pantalla del celular de vez en cuando, no continuamente.
//
//  Sin HealthKit ni WatchConnectivity adentro: la regla no los necesita y asi se
//  verifica en el host. El envio vive en `EffortRelay.swift`.
//

import Foundation

/// Lo que el reloj esta midiendo ahora mismo.
struct EffortSnapshot: Equatable {
    let bpm: Int?
    let kcal: Int?

    /// Un ejercicio POR TIEMPO corriendo en el reloj, para que el telefono
    /// muestre la misma cuenta.
    ///
    /// Viaja ACA y no en su propio contexto porque el reloj tiene UN SOLO
    /// `applicationContext` de salida: mandarlo aparte PISARIA el pulso.
    ///
    /// Se manda el INSTANTE DE FIN y no lo que falta. Asi el telefono calcula
    /// la cuenta solo, sin trafico por segundo, y un envio que llega tarde
    /// —el throttle es de 5s— sigue mostrando el numero correcto.
    struct RunningTimer: Equatable {
        let exerciseId: String
        /// CUAL de las series del ejercicio se esta cronometrando.
        ///
        /// Sin esto el telefono sabe QUE ejercicio corre pero no cual de sus
        /// series, y con tres series por tiempo en el mismo ejercicio tendria
        /// que adivinar. Adivinar por "la proxima sin cargar" falla justo
        /// cuando el estado viene desordenado, que es cuando importa. Es la
        /// misma identidad logica —ejercicio + numero de serie— que usa el
        /// resto del sistema.
        let setNumber: Int
        let totalSeconds: Int
        let endsAt: Date
    }

    let timer: RunningTimer?

    init(bpm: Int?, kcal: Int?, timer: RunningTimer? = nil) {
        self.bpm = bpm
        self.kcal = kcal
        self.timer = timer
    }

    /// Un cronometro corriendo YA es algo que mostrar, aunque no haya pulso ni
    /// calorias. Sin esto el envio se descartaba por vacio y el telefono no se
    /// enteraba nunca del cronometro.
    var isEmpty: Bool { bpm == nil && kcal == nil && timer == nil }

    /// El diccionario que viaja por WatchConnectivity.
    ///
    /// ⚠️ **Es un contrato con el lado Dart.** Las mismas claves las lee
    /// `WatchEffort.tryParse` en `lib/features/watch/domain/watch_effort.dart`.
    /// Cambiar una acá sin cambiarla alla deja al telefono sin datos y sin
    /// ningun error visible.
    func context(measuredAt: Date) -> [String: Any] {
        // `Int64` y NO `Int`. Esto CRASHEABA el reloj.
        //
        // watchOS corre arm64_32: los punteros son de 32 bits y `Int` tambien.
        // Los milisegundos desde 1970 rondan 1,79e12, que excede el maximo de
        // Int32 (2,15e9) por un factor de ~832. Y `Int(Double)` no trunca ni
        // devuelve basura cuando no entra: TRAPEA. El proceso muere con
        // EXC_BREAKPOINT en el primer dato de pulso que llega.
        //
        // En el iPhone `Int` son 64 bits y esto anda perfecto, que es
        // exactamente por que sobrevivio tanto: el mismo codigo es correcto de
        // un lado del emparejamiento y letal del otro.
        //
        // Los tests puros del reloj TAMPOCO lo agarraban: corren en el host con
        // `swiftc`, o sea arm64 de 64 bits. El test que se agrego abajo verifica
        // el TIPO, que es lo unico observable desde el host.
        var payload: [String: Any] = [
            "kind": "watchEffort",
            "measuredAtMs": Int64(measuredAt.timeIntervalSince1970 * 1000),
        ]
        if let bpm { payload["bpm"] = bpm }
        if let kcal { payload["kcal"] = kcal }
        if let timer {
            payload["timerExerciseId"] = timer.exerciseId
            payload["timerSetNumber"] = timer.setNumber
            payload["timerTotalSeconds"] = timer.totalSeconds
            // Int64 por lo mismo que measuredAtMs: en arm64_32 `Int` son 32
            // bits y los milisegundos desde 1970 no entran — trapea.
            payload["timerEndsAtMs"] = Int64(timer.endsAt.timeIntervalSince1970 * 1000)
        }
        return payload
    }
}

enum EffortBroadcastRules {

    /// Minimo entre envios.
    ///
    /// `updateApplicationContext` esta rate-limited por el sistema, y pasarse
    /// hace que descarte envios EN SILENCIO. Mejor espaciarlos nosotros que
    /// enterarnos por un dato que no llega.
    ///
    /// Cinco segundos contra los 45 que el telefono da por bueno un dato: hay
    /// margen de sobra para que un envio perdido no deje la pantalla vacia.
    static let minIntervalo: TimeInterval = 5

    /// Si corresponde mandar `actual`.
    static func shouldSend(
        last: (payload: EffortSnapshot, at: Date)?,
        actual: EffortSnapshot,
        now: Date
    ) -> Bool {
        // APAGAR un cronometro que el telefono cree que sigue corriendo SI vale
        // un envio, aunque el payload quede vacio.
        //
        // Sin esto: el atleta CANCELA el cronometro antes de que llegue el
        // primer pulso, el snapshot queda sin bpm, sin kcal y sin timer, se
        // descarta por vacio, y el telefono sigue contando hasta cero algo que
        // ya no existe. Se corrige solo al vencer, pero mientras tanto miente.
        if actual.isEmpty, let last, last.payload.timer != nil {
            return true
        }

        // Nada que mostrar: el telefono ya sabe no dibujar nada.
        guard !actual.isEmpty else { return false }

        guard let last else { return true }

        // Identico a lo ultimo que se mando: reenviarlo no le agrega nada al
        // telefono y le cuesta una activacion.
        guard last.payload != actual else { return false }

        // ARRANCAR, CAMBIAR o CORTAR un cronometro NO espera al throttle.
        //
        // El throttle existe para no despertar al telefono por cada muestra de
        // pulso: llegan cada ~5 segundos y un segundo de atraso no le cambia
        // nada a nadie. Un cronometro es otra cosa. El atleta ya empezo la
        // plancha y esta mirando la pantalla; que la cuenta aparezca tarde es
        // exactamente el sintoma de "no anda".
        //
        // Y pasaba siempre: basta que haya llegado un pulso en los 5 segundos
        // previos —lo normal a mitad de entreno— para que el arranque caiga en
        // el throttle de abajo. Peor: si despues no llega otro dato, el envio
        // espera al proximo evento cualquiera, no a que se cumplan los 5s.
        //
        // El test que deberia haber agarrado esto elegia el unico input que
        // cortocircuita el throttle (`last: nil`), asi que nadie cruzaba nunca
        // throttle x cronometro.
        if last.payload.timer != actual.timer { return true }

        return now.timeIntervalSince(last.at) >= minIntervalo
    }
}
