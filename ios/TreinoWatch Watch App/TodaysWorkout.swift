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
/// Las DOS reglas de negocio que usa están bajo contrato de conformidad y
/// verificadas de los dos lados:
///   * cuál rutina — `resolveActiveRoutineId` / `conformance/routine_selection.json`
///   * qué día toca — `nextPlanPosition` / `conformance/plan_advance.json`
///
/// Lo que queda acá es solo la traducción entre Firestore y esas funciones.
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

    /// Aplica la MISMA prioridad que el teléfono, vía `resolveActiveRoutineId`.
    ///
    /// El marcador `activeRoutineId` vive en el doc del usuario, así que hay
    /// que leerlo antes: sin él el reloj se saltearía el tier 0 y podría elegir
    /// una rutina distinta a la que el atleta marcó.
    private static func findRoutine(
        client: FirestoreREST,
        uid: String
    ) async throws -> [String: Any]? {
        let profile = try await client.document("users/\(uid)")
        let activeRoutineId = FS.string(profile?["activeRoutineId"])

        let assigned = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": fieldEquals("assignedTo", uid),
        ])
        let selfCreated = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": fieldEquals("createdBy", uid),
        ])

        func ids(_ docs: [[String: Any]]) -> [String] {
            docs.compactMap { FS.string($0["id"]) }
        }

        guard let resolvedId = resolveActiveRoutineId(
            activeRoutineId: activeRoutineId,
            assignedIds: ids(assigned),
            selfCreatedIds: ids(selfCreated)
        ) else { return nil }

        return (assigned + selfCreated).first {
            FS.string($0["id"]) == resolvedId
        }
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
