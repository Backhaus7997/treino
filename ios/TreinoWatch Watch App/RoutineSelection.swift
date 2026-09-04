//
//  RoutineSelection.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F2.
//

import Foundation

/// Elige QUÉ rutina es la activa del atleta.
///
/// ⚠️ **PUERTO LITERAL de `resolveActiveRoutineId` en
/// `lib/features/workout/domain/routine_selection.dart`.** Es la misma regla
/// escrita dos veces: si divergen, teléfono y reloj le muestran rutinas
/// DISTINTAS al mismo usuario, y el atleta entrena lo que no era.
///
/// El contrato está en `conformance/routine_selection.json` y lo corren los dos
/// lados. Si tocás esto sin tocar el Dart —o al revés— CI se pone rojo.
///
/// Prioridad:
/// 0. Marcador explícito del perfil, buscado en la lista UNIFICADA: primero
///    asignadas por PF, después auto-creadas, y por último las plantillas del
///    catálogo que el atleta eligió seguir sin copiarlas. Un id obsoleto NO
///    devuelve nil: cae al resto de la cadena.
/// 1. Plan asignado por un PF (el más nuevo; llegan ordenados).
/// 2. Una sola auto-creada: se auto-activa.
/// 3. Varias auto-creadas sin marcador válido: nil, no se adivina.
///
/// `catalogIds` sólo participa del tier 0: una plantilla del catálogo nunca se
/// auto-activa, hay que elegirla. El llamador puede pasar `[]` cuando ya sabe
/// que no hace falta —marcador nulo, o que ya matcheó contra las otras dos
/// listas— y ahorrarse la query; el resultado es el mismo.
func resolveActiveRoutineId(
    activeRoutineId: String?,
    assignedIds: [String],
    selfCreatedIds: [String],
    catalogIds: [String] = []
) -> String? {
    // Tier 0 — marcador explícito.
    if let marker = activeRoutineId, !marker.isEmpty {
        if assignedIds.contains(marker) { return marker }
        if selfCreatedIds.contains(marker) { return marker }
        if catalogIds.contains(marker) { return marker }
        // Obsoleto: sigue la cadena.
    }

    // Tier 1 — plan de PF.
    if let first = assignedIds.first { return first }

    // Tier 2 — única auto-creada.
    if selfCreatedIds.count == 1 { return selfCreatedIds[0] }

    // Tier 3 — varias auto-creadas: exige marcador, y si se llegó hasta acá el
    // marcador no resolvió. Tier 4 — sin rutinas.
    return nil
}
