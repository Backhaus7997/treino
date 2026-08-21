//
//  WorkoutDurationRules.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F3. Decision D4, firmada.
//
//  De donde sale la duracion del entreno.
//
//  Hasta acá los dos lados la ESTIMABAN restando timestamps. D4 la convierte en
//  una MEDICION cuando existe: la sesion de entrenamiento de watchOS sabe
//  cuanto duro de verdad, y el calculo de reloj de pared queda como respaldo
//  para cuando no hay sesion —permiso negado, Salud caida, dispositivo sin
//  Salud—.
//
//  `durationMin` no cambia de forma en Firestore. Cambia de donde sale el
//  numero.
//

import Foundation

/// De donde salio la duracion. Se devuelve junto al numero para poder
/// diagnosticar sin adivinar: un entreno con duracion rara no es lo mismo si
/// vino medido que si vino calculado.
enum WorkoutDurationSource: Equatable {
    case medida
    case calculada
}

enum WorkoutDurationRules {

    /// Techo de duracion, en minutos.
    ///
    /// El mismo que aplica el telefono en
    /// `lib/features/workout/application/session_duration.dart`. No es una
    /// coincidencia que haya que mantener: sin el, el MISMO entreno persistia
    /// una duracion distinta segun que dispositivo lo terminara.
    ///
    /// El techo existe porque las sesiones olvidadas se acumulan —deuda
    /// conocida del ciclo anterior— y una dejada abierta toda la noche escribia
    /// duraciones absurdas que despues salen al feed publico.
    ///
    /// ⚠️ El telefono ademas RECUPERA la duracion real desde los timestamps de
    /// las series cuando se pasa del techo. Eso NO esta portado acá: el reloj
    /// solo acota. Es una asimetria conocida, no un olvido.
    static let maxMinutos = 8 * 60

    /// Piso de duracion, en minutos.
    ///
    /// Un entreno relampago igual duro algo, y un 0 se lee como "no se
    /// registro". Es la regla que ya tenia el reloj y no cambia.
    static let minMinutos = 1

    /// Los minutos del entreno, y de donde salieron.
    ///
    /// `measuredSeconds` es lo que midio la sesion de entrenamiento. Si viene
    /// `nil` —no habia sesion— se cae al calculo de siempre.
    static func minutes(
        measuredSeconds: TimeInterval?,
        startedAt: Date,
        now: Date
    ) -> (minutes: Int, source: WorkoutDurationSource) {
        let seconds: TimeInterval
        let source: WorkoutDurationSource

        if let measuredSeconds {
            seconds = measuredSeconds
            source = .medida
        } else {
            seconds = now.timeIntervalSince(startedAt)
            source = .calculada
        }

        let crudos = Int(seconds / 60)
        return (min(max(crudos, minMinutos), maxMinutos), source)
    }
}
