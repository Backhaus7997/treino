//
//  SetResolution.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F3.
//

import Foundation

/// Una serie prescrita. Solo los campos que fija el contrato compartido.
struct SetSpec: Equatable {
    var reps: Int?
    var repsMin: Int?
    var repsMax: Int?
    var weightKg: Double?
    var durationSeconds: Int?
}

/// Los campos de un `RoutineSlot` que intervienen en resolver las series.
struct SlotPrescription {
    var targetSets: Int
    var durationSeconds: Int?
    var targetReps: [Int]
    var targetRepsMin: Int
    var targetRepsMax: Int
    var targetWeightKg: Double?
    var sets: [SetSpec]
    var weeklySets: [[SetSpec]]
    var activeWeeks: [Int]
}

/// ⚠️ **PUERTO LITERAL de `RoutineSlot.effectiveSetsForWeek` /
/// `isPresentInWeek` (`lib/features/workout/domain/routine_slot.dart`).**
///
/// Es la lógica MÁS SUTIL del dominio: define lo que el atleta efectivamente
/// levanta. Si diverge del teléfono, el reloj le hace hacer otro entreno.
///
/// Contrato en `conformance/set_resolution.json`, corrido por los dos lados.
enum SetResolution {

    /// Si el ejercicio está presente en la semana 0-based dada.
    ///
    /// Máscara vacía = presente en TODAS (back-compat: los docs legacy no traen
    /// el campo). Nunca falla, ni con semanas negativas.
    static func isPresentInWeek(_ slot: SlotPrescription, week: Int) -> Bool {
        slot.activeWeeks.isEmpty || slot.activeWeeks.contains(week)
    }

    /// Las series de una semana 0-based.
    ///
    /// Precedencia: `weeklySets[week]` si está EN RANGO —incluso si está
    /// vacía, porque una semana vacía autorada es un deload y no un dato
    /// faltante— y si no, la vía plana.
    static func effectiveSets(_ slot: SlotPrescription, week: Int) -> [SetSpec] {
        if !slot.weeklySets.isEmpty, week >= 0, week < slot.weeklySets.count {
            return slot.weeklySets[week]
        }
        return flatSets(slot)
    }

    private static func flatSets(_ slot: SlotPrescription) -> [SetSpec] {
        // Filas explícitas ganan.
        if !slot.sets.isEmpty { return slot.sets }

        // Siempre al menos una serie: un doc mal cargado no debe dejar al
        // atleta sin nada que hacer.
        let n = min(max(slot.targetSets, 1), 999)

        // Por tiempo.
        if let duration = slot.durationSeconds, duration > 0 {
            return Array(repeating: SetSpec(durationSeconds: duration), count: n)
        }

        // Reps por serie.
        if !slot.targetReps.isEmpty {
            if slot.targetReps.count == 1 {
                return Array(repeating: SetSpec(reps: slot.targetReps[0]), count: n)
            }
            // Secuencia explícita: una fila por entrada, ignorando targetSets.
            return slot.targetReps.map { SetSpec(reps: $0) }
        }

        // Último fallback: rango.
        return Array(
            repeating: SetSpec(
                repsMin: slot.targetRepsMin,
                repsMax: slot.targetRepsMax,
                weightKg: slot.targetWeightKg
            ),
            count: n
        )
    }
}
