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

    var isEmpty: Bool { bpm == nil && kcal == nil }

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
        // Nada que mostrar: el telefono ya sabe no dibujar nada.
        guard !actual.isEmpty else { return false }

        guard let last else { return true }

        // Identico a lo ultimo que se mando: reenviarlo no le agrega nada al
        // telefono y le cuesta una activacion.
        guard last.payload != actual else { return false }

        return now.timeIntervalSince(last.at) >= minIntervalo
    }
}
