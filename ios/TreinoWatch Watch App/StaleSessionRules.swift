//
//  StaleSessionRules.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, tanda de bugfixes de sincronizacion.
//

import Foundation

/// Que hacer con las sesiones que quedaron ABIERTAS en el historial.
///
/// Existe porque el barrido de colgadas lo disparaba SOLO el telefono
/// (HANDOFF §8.1). `SessionRepository.getActive` mira las 10 `active` mas
/// nuevas y CIERRA con un write real todo lo que pase de 8h; el reloj tenia su
/// propio camino —`HistorySync.findAnyActiveSession`— sin corte por antiguedad.
/// Un atleta que use solo la muñeca no barria nada y podia ADOPTAR una sesion
/// de hace dias: la pantalla de entreno abierta sobre un entreno de otro dia,
/// y cada serie que marcara ahi escrita en el documento equivocado.
///
/// La regla vive afuera de `HistorySync` para poder medirla en el host: el
/// caso que importa —una sesion de hace tres dias— es de los mas caros de
/// reproducir corriendo, porque hay que fabricar el historial y esperar.
///
/// Es la MISMA politica que el telefono, a proposito. Si los dos lados
/// decidieran distinto, el mismo historial daria un entreno activo en un
/// dispositivo y no en el otro — que es exactamente la clase de bug que este
/// ciclo lleva arreglada cuatro veces.
enum StaleSessionRules {

    /// Cuanto puede estar abierta una sesion antes de darla por muerta.
    ///
    /// Sale de `WorkoutDurationRules.maxMinutos` y NO es una constante nueva:
    /// es el mismo techo que ya acota la duracion que se persiste. Si el propio
    /// contador considera que un entreno no puede durar mas que eso, una sesion
    /// activa mas vieja esta muerta por definicion. Derivarla en vez de
    /// copiarla es lo que evita que las dos se separen sin que nadie lo note.
    static var maxAntiguedad: TimeInterval {
        TimeInterval(WorkoutDurationRules.maxMinutos * 60)
    }

    /// Una sesion abierta candidata, reducida a lo unico que la decision mira.
    struct Candidata: Equatable {
        let id: String
        let startedAt: Date

        init(id: String, startedAt: Date) {
            self.id = id
            self.startedAt = startedAt
        }
    }

    /// Que sesion adoptar y cuales cerrar.
    struct Decision: Equatable {
        /// La sesion que el atleta esta haciendo AHORA, o nil si no hay
        /// ninguna viva.
        let adoptar: String?

        /// Las colgadas. Se cierran con `wasFullyCompleted: false`, asi que no
        /// cuentan como entreno hecho: no mueven el plan, ni la racha, ni los
        /// rankings.
        let aCerrar: [String]
    }

    /// La decision, espejo exacto de `SessionRepository.getActive`:
    ///
    /// - Si la MAS NUEVA ya vencio, vencieron todas: no hay nada que adoptar y
    ///   se cierra la lista entera.
    /// - Si no, esa es la que el atleta esta haciendo y se cierran las demas.
    ///   Barrer solo las repetidas y dejar viva una de ayer era justamente el
    ///   agujero: el reloj la adoptaba igual.
    ///
    /// La lista se ordena acá y no se confia en el `orderBy` de la query:
    /// una regla que depende del orden de entrada es una regla que se rompe en
    /// silencio el dia que alguien toca la consulta.
    ///
    /// - Parameters:
    ///   - candidatas: las sesiones ABIERTAS (sin `finishedAt`), en cualquier
    ///     orden.
    ///   - ahora: se inyecta para que la decision sea determinística.
    static func decidir(candidatas: [Candidata], ahora: Date) -> Decision {
        let porFecha = candidatas.sorted { $0.startedAt > $1.startedAt }
        guard let masNueva = porFecha.first else {
            return Decision(adoptar: nil, aCerrar: [])
        }

        // Una fecha en el FUTURO no vence: es reloj desfasado, no una sesion
        // muerta. Cerrarla le sacaria al atleta el entreno que esta haciendo.
        let vencio = ahora.timeIntervalSince(masNueva.startedAt) > maxAntiguedad
        if vencio {
            return Decision(adoptar: nil, aCerrar: porFecha.map(\.id))
        }
        return Decision(
            adoptar: masNueva.id,
            aCerrar: porFecha.dropFirst().map(\.id)
        )
    }
}
