//
//  HeartRateRules.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F2.
//
//  Que se le muestra al atleta como ritmo cardiaco, y cuando NO se le muestra
//  nada.
//
//  Sin HealthKit adentro: la regla no lo necesita, y no arrastrarlo la deja
//  verificable en el host en segundos. El puente vive en
//  `WorkoutSessionController.swift`.
//

import Foundation

/// Una lectura de ritmo cardiaco, con el momento en que se tomo.
///
/// El timestamp no es decorativo: es lo que permite distinguir una medicion
/// actual de una vieja que quedo colgada.
struct HeartRateReading: Equatable {
    let bpm: Int
    let takenAt: Date

    /// HealthKit entrega la frecuencia como `Double`. Se REDONDEA, no se trunca:
    /// 141.6 esta mas cerca de 142 que de 141, y truncar sesga toda la lectura
    /// hacia abajo.
    static func bpm(fromQuantity value: Double) -> Int {
        Int(value.rounded())
    }
}

/// Que mostrar en pantalla.
enum HeartRateDisplay: Equatable {
    /// No hay nada que mostrar. La pantalla NO pone un error.
    ///
    /// Es el estado mas importante de F2, y el mas facil de tratar mal. En F0
    /// se midio que una lectura NEGADA por el atleta es indistinguible de "no
    /// hay datos todavia": las dos dan una query exitosa con cero muestras.
    /// Como la app no puede saber cual de las dos es, no puede acusar a
    /// ninguna. El silencio se muestra como silencio.
    case sinDatos

    case bpm(Int)
}

enum HeartRateRules {

    /// Cuanto vale una lectura antes de considerarse vieja.
    ///
    /// El Apple Watch muestrea cada ~5 segundos durante un entrenamiento, asi
    /// que 15 son tres muestras perdidas: suficiente para absorber un hueco
    /// normal, poco para que un numero viejo se haga pasar por actual.
    ///
    /// En un entreno de verdad el sensor se corta seguido —muñeca floja, brazo
    /// en una posicion rara, transpiracion—. Dejar la ultima lectura conocida
    /// en pantalla seria mentirle al atleta sobre su propio esfuerzo justo
    /// cuando mas lo esta mirando.
    static let maxAntiguedad: TimeInterval = 15

    static func display(reading: HeartRateReading?, now: Date) -> HeartRateDisplay {
        guard let reading else { return .sinDatos }

        // Un 0 no es una medicion: es un sensor que no engancho. Mostrarlo
        // asustaria al atleta por un problema de hardware.
        guard reading.bpm > 0 else { return .sinDatos }

        let antiguedad = now.timeIntervalSince(reading.takenAt)

        // Antiguedad negativa = el reloj se corrio hacia atras. Es un problema
        // del dispositivo, no del atleta, y no tiene por que borrarle la
        // pantalla: se toma como actual.
        guard antiguedad > maxAntiguedad else { return .bpm(reading.bpm) }

        return .sinDatos
    }
}
