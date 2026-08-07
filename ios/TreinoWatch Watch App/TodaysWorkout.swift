//
//  TodaysWorkout.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F2.
//

import Foundation

/// El entreno que le toca al atleta hoy, resuelto por el reloj.
struct TodaysWorkout: Equatable {
    let routineName: String
    let dayName: String
    let dayNumber: Int
    let weekNumber: Int
    let numWeeks: Int
    let exerciseCount: Int
}

/// Resuelve el entreno de hoy leyendo Firestore por REST.
///
/// ⚠️ **DIVERGENCIA CONOCIDA — leer antes de tocar.**
///
/// La elección de CUÁL rutina usar es una simplificación de la cadena de 4
/// niveles de `todaysRoutineProvider` (Dart), que además contempla el marcador
/// `activeRoutineId` del perfil y el caso multi-rutina auto-creadas. Acá se
/// implementa solo: rutina asignada por PF, y si no hay, la auto-creada más
/// reciente.
///
/// Eso alcanza para v1 (Locked Decision #5) pero **todavía no está cubierto por
/// fixtures de conformidad**, a diferencia del avance de día/semana. Es deuda
/// consciente y anotada en el state.yaml del change: mientras esa elección no
/// sea una función pura testeada de los dos lados, teléfono y reloj pueden
/// elegir rutinas distintas para el mismo usuario.
///
/// El cálculo de qué día toca SÍ usa `nextPlanPosition`, que es puerto literal
/// del Dart y está bajo contrato en `conformance/plan_advance.json`.
enum TodaysWorkoutResolver {

    static func resolve(
        client: FirestoreREST,
        uid: String
    ) async throws -> TodaysWorkout? {
        guard let routine = try await findRoutine(client: client, uid: uid) else {
            return nil
        }

        let routineId = FS.string(routine["id"]) ?? ""
        let days = FS.array(routine["days"]) ?? []
        guard !days.isEmpty else { return nil }

        let lastFinished = try await findLastFinishedSession(
            client: client, uid: uid, routineId: routineId
        )

        let position = nextPlanPosition(
            lastFinished: lastFinished,
            numDays: days.count,
            numWeeks: FS.int(routine["numWeeks"]) ?? 1
        )

        // Defensivo contra dayNumbers no contiguos, igual que el lado Dart:
        // si no aparece el día buscado, se cae al primero.
        let dayFields = days
            .first { FS.int(FS.mapFields($0)?["dayNumber"]) == position.dayNumber }
            .flatMap { FS.mapFields($0) }
            ?? FS.mapFields(days[0])

        return TodaysWorkout(
            routineName: FS.string(routine["name"]) ?? "Rutina",
            dayName: FS.string(dayFields?["name"]) ?? "Día \(position.dayNumber)",
            dayNumber: position.dayNumber,
            weekNumber: position.weekNumber,
            numWeeks: FS.int(routine["numWeeks"]) ?? 1,
            exerciseCount: (FS.array(dayFields?["slots"]) ?? []).count
        )
    }

    /// Rutina asignada por un PF; si no hay, la auto-creada más reciente.
    /// Ver la advertencia de divergencia del encabezado.
    private static func findRoutine(
        client: FirestoreREST,
        uid: String
    ) async throws -> [String: Any]? {
        let assigned = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": fieldEquals("assignedTo", uid),
        ])
        if let first = assigned.first { return first }

        let selfCreated = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": fieldEquals("createdBy", uid),
        ])
        return selfCreated.first
    }

    /// Última sesión FINALIZADA de esa rutina, que es la entrada de
    /// `nextPlanPosition`.
    ///
    /// Se ordena por `startedAt` descendente y se filtra en el cliente por
    /// `finishedAt` presente: agregar ese filtro a la query exigiría un índice
    /// compuesto en Firestore, y no vale la pena para el puñado de sesiones que
    /// se traen.
    private static func findLastFinishedSession(
        client: FirestoreREST,
        uid: String,
        routineId: String
    ) async throws -> PlanPosition? {
        let sessions = try await client.runQuery([
            "from": [["collectionId": "sessions"]],
            "where": fieldEquals("routineId", routineId),
            "orderBy": [[
                "field": ["fieldPath": "startedAt"],
                "direction": "DESCENDING",
            ]],
            "limit": 20,
        ], parent: "users/\(uid)")

        for fields in sessions {
            guard fields["finishedAt"] != nil,
                  let day = FS.int(fields["dayNumber"]),
                  let week = FS.int(fields["weekNumber"])
            else { continue }
            return PlanPosition(dayNumber: day, weekNumber: week)
        }
        return nil
    }

    private static func fieldEquals(_ path: String, _ value: String) -> [String: Any] {
        [
            "fieldFilter": [
                "field": ["fieldPath": path],
                "op": "EQUAL",
                "value": ["stringValue": value],
            ],
        ]
    }
}
