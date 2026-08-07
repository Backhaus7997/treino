//
//  HistorySync.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F4.
//

import Foundation

/// Escribe al historial de Firestore lo que el reloj registró.
///
/// DECISIÓN DEL DUEÑO: **una sola sesión compartida**. Si el teléfono ya tiene
/// una sesión activa del mismo día, el reloj se suma a ESA en vez de crear la
/// suya. Un entreno = un registro, sin importar dónde se cargó.
///
/// IDEMPOTENCIA — la parte que importa:
///
/// El teléfono escribe las series con ids autogenerados, así que no se puede
/// deduplicar por id contra lo que él escribe. El reloj usa en cambio un id
/// DETERMINÍSTICO (`exerciseId__setNumber`), que resuelve el caso que de verdad
/// importa: reintentar una escritura que fallo no duplica nada, porque la
/// segunda pisa a la primera en vez de crear un doc nuevo.
///
/// Para el caso cruzado —que el teléfono ya haya cargado esa misma serie— la
/// defensa es otra: al adoptar una sesión existente, el reloj LEE las series ya
/// cargadas y las marca como hechas, así no vuelve a ofrecerlas.
enum HistorySync {

    /// Id determinístico de una serie escrita por el reloj.
    ///
    /// Doble guion bajo como separador para que un exerciseId con guion bajo no
    /// genere colisiones entre `a_1` serie 0 y `a` serie 1.
    static func setLogId(exerciseId: String, setNumber: Int) -> String {
        "\(exerciseId)__\(setNumber)"
    }

    /// Busca una sesión ACTIVA del mismo día, o crea una nueva.
    ///
    /// Devuelve el id de la sesión en Firestore y las series que ya estuvieran
    /// cargadas (por el teléfono o por un intento anterior del reloj).
    static func adoptOrCreateSession(
        client: FirestoreREST,
        uid: String,
        workout: TodaysWorkout,
        startedAt: Date
    ) async throws -> (sessionId: String, alreadyLogged: [LoggedSet]) {
        if let existing = try await findActiveSession(
            client: client, uid: uid, workout: workout
        ) {
            let logged = try await existingSetLogs(
                client: client, uid: uid, sessionId: existing
            )
            return (existing, logged)
        }

        let sessionId = try await createSession(
            client: client, uid: uid, workout: workout, startedAt: startedAt
        )
        return (sessionId, [])
    }

    private static func findActiveSession(
        client: FirestoreREST,
        uid: String,
        workout: TodaysWorkout
    ) async throws -> String? {
        let rows = try await client.runQuery([
            "from": [["collectionId": "sessions"]],
            "where": ["fieldFilter": [
                "field": ["fieldPath": "routineId"],
                "op": "EQUAL",
                "value": ["stringValue": workout.routineId],
            ]],
            "orderBy": [[
                "field": ["fieldPath": "startedAt"],
                "direction": "DESCENDING",
            ]],
            "limit": 10,
        ], parent: "users/\(uid)")

        // El filtro fino se hace en el cliente: sumar dayNumber/weekNumber/
        // status a la query exigiria un indice compuesto en Firestore, y son
        // pocas filas.
        for doc in rows {
            let f = doc.fields
            guard f["finishedAt"] == nil,
                  FS.int(f["dayNumber"]) == workout.dayNumber,
                  FS.int(f["weekNumber"]) == workout.weekNumber
            else { continue }
            return doc.id
        }
        return nil
    }

    private static func existingSetLogs(
        client: FirestoreREST,
        uid: String,
        sessionId: String
    ) async throws -> [LoggedSet] {
        let rows = try await client.runQuery(
            ["from": [["collectionId": "setLogs"]], "limit": 200],
            parent: "users/\(uid)/sessions/\(sessionId)"
        )
        return rows.compactMap { doc in
            let f = doc.fields
            guard let exerciseId = FS.string(f["exerciseId"]),
                  let setNumber = FS.int(f["setNumber"])
            else { return nil }
            return LoggedSet(
                exerciseId: exerciseId,
                setNumber: setNumber,
                reps: FS.int(f["reps"]),
                weightKg: FS.double(f["weightKg"]),
                completedAt: Date(),
                synced: true
            )
        }
    }

    private static func createSession(
        client: FirestoreREST,
        uid: String,
        workout: TodaysWorkout,
        startedAt: Date
    ) async throws -> String {
        // Mismos campos que escribe `SessionRepository.create` en el telefono:
        // si faltara alguno, la sesion del reloj se veria rota en el historial.
        let fields: [String: Any] = [
            "uid": ["stringValue": uid],
            "routineId": ["stringValue": workout.routineId],
            "routineName": ["stringValue": workout.routineName],
            "startedAt": ["timestampValue": iso(startedAt)],
            "totalVolumeKg": ["doubleValue": 0],
            "durationMin": ["integerValue": "0"],
            "status": ["stringValue": "active"],
            "dayNumber": ["integerValue": String(workout.dayNumber)],
            "weekNumber": ["integerValue": String(workout.weekNumber)],
        ]
        return try await client.createDocument(
            collectionPath: "users/\(uid)/sessions",
            fields: fields
        )
    }

    /// Escribe una serie. Idempotente: el id determinístico hace que reintentar
    /// pise el doc anterior en vez de duplicarlo.
    static func writeSetLog(
        client: FirestoreREST,
        uid: String,
        sessionId: String,
        exerciseName: String,
        set: LoggedSet
    ) async throws {
        let docId = setLogId(exerciseId: set.exerciseId, setNumber: set.setNumber)
        let fields: [String: Any] = [
            "id": ["stringValue": docId],
            "exerciseId": ["stringValue": set.exerciseId],
            "exerciseName": ["stringValue": exerciseName],
            "setNumber": ["integerValue": String(set.setNumber)],
            "reps": ["integerValue": String(set.reps ?? 0)],
            "weightKg": ["doubleValue": set.weightKg ?? 0],
            "completedAt": ["timestampValue": iso(set.completedAt)],
        ]
        try await client.setDocument(
            path: "users/\(uid)/sessions/\(sessionId)/setLogs/\(docId)",
            fields: fields
        )
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
