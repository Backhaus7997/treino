//
//  ActiveEnergyRules.swift
//  TreinoWatch Watch App
//
//  Change `watch-workout-session`, fase F2.
//
//  Que se le muestra al atleta como calorias quemadas.
//
//  Sin HealthKit adentro, igual que `HeartRateRules`: la regla no lo necesita y
//  asi se verifica en el host en segundos.
//

import Foundation

/// Las calorias activas quemadas en lo que va del entreno.
///
/// Es un ACUMULADO desde que arranco la sesion, no un instantaneo. Esa
/// diferencia con el ritmo cardiaco es la que manda sobre toda la regla de
/// abajo.
struct ActiveEnergyReading: Equatable {
    let kcal: Int
    let takenAt: Date

    static func kcal(fromQuantity value: Double) -> Int {
        Int(value.rounded())
    }
}

enum ActiveEnergyDisplay: Equatable {
    case sinDatos
    case kcal(Int)
}

enum ActiveEnergyRules {

    /// Que mostrar.
    ///
    /// **Estas reglas NO comparten codigo con las del ritmo cardiaco aunque en
    /// pantalla se parezcan, porque los dos datos son de naturaleza distinta:**
    ///
    /// - El ritmo cardiaco es INSTANTANEO. Una lectura vieja es una MENTIRA:
    ///   dice "estas a 140" cuando hace 40 segundos que no se mide. Por eso
    ///   `HeartRateRules` la descarta pasados 15 segundos.
    ///
    /// - Las calorias son ACUMULADAS. Una lectura vieja sigue siendo VERDAD: si
    ///   hace 40 segundos habias quemado 120, ahora quemaste 120 o mas.
    ///   Borrarla seria ocultar algo cierto.
    ///
    /// Por eso acá no hay regla de antiguedad, y `now` no se usa. Se recibe
    /// igual para que la firma sea la misma que la del ritmo cardiaco y quede a
    /// la vista que la diferencia es DELIBERADA y no un olvido.
    static func display(reading: ActiveEnergyReading?, now: Date) -> ActiveEnergyDisplay {
        guard let reading else { return .sinDatos }

        // Negativo es imposible: no se puede des-quemar energia.
        //
        // Ojo con el CERO: acá si se muestra, al reves que en el ritmo cardiaco.
        // Un 0 de pulsaciones es imposible —es un sensor que no engancho— pero
        // un 0 de calorias es cierto: todavia no se midio consumo. Ocultar un
        // dato verdadero es el mismo pecado que mostrar uno falso.
        guard reading.kcal >= 0 else { return .sinDatos }

        return .kcal(reading.kcal)
    }
}
