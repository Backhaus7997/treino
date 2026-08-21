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
/// El teléfono escribe las series con ids autogenerados y el reloj con uno
/// DETERMINÍSTICO (`exerciseId__setNumber`). Los dos espacios de ids son
/// disjuntos, así que **por id no se puede deduplicar nada entre clientes**: el
/// que escribe segundo no tiene contra qué comparar y crea un documento nuevo.
/// Medido en el emulador el 2026-08-11: en las 7 sesiones inspeccionadas los
/// documentos duplicados tenían todos `createTime == updateTime`, o sea que
/// ninguna escritura pisó nunca a otra.
///
/// El id determinístico sí resuelve el caso PROPIO: reintentar una escritura que
/// falló no duplica, porque la segunda pisa a la primera.
///
/// Para el caso CRUZADO la deduplicación no puede vivir en el id: vive en
/// `resolveSetLogWriteTarget`, que decide dónde escribir mirando la identidad
/// LÓGICA de lo que el historial ya tiene. `WorkoutCoordinator.sync` lee el
/// historial ANTES de subir lo pendiente justamente para poder consultarla.
enum HistorySync {

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

    /// Una sesión activa que ya existe en el historial, venga de donde venga.
    struct ActiveSession {
        let id: String
        let routineId: String
        let routineName: String
        let dayNumber: Int
        let weekNumber: Int
        let startedAt: Date
    }

    /// Busca CUALQUIER sesión sin terminar del atleta, sin importar la rutina,
    /// y **barre las colgadas** por el camino.
    ///
    /// Es lo que permite que el reloj adopte solo un entreno que empezó el
    /// teléfono. `findActiveSession` no sirve para esto: filtra por la rutina
    /// del entreno de hoy, así que un entreno arrancado desde una plantilla —o
    /// desde cualquier rutina que no sea la activa— quedaba invisible.
    ///
    /// ⚠️ EL BARRIDO NO ERA SIMÉTRICO (HANDOFF §8.1). El teléfono cierra con un
    /// write real todo lo que pase de 8h (`SessionRepository.getActive`); acá no
    /// había NINGÚN corte por antigüedad, así que un atleta que usara solo la
    /// muñeca no barría nada y **adoptaba una sesión de hace días** como si
    /// fuera el entreno de hoy. La política ahora es la misma de los dos lados y
    /// vive en un solo lugar: `StaleSessionRules.decidir`.
    ///
    /// El cierre es **best-effort**, igual que en el teléfono: si el write falla
    /// se devuelve igual la sesión viva. El atleta tiene que poder seguir
    /// entrenando aunque la limpieza no entre.
    ///
    /// - Parameter now: se inyecta para poder medir el corte sin esperar 8h.
    static func findAnyActiveSession(
        client: FirestoreREST,
        uid: String,
        now: Date = Date()
    ) async throws -> ActiveSession? {
        let rows = try await client.runQuery([
            "from": [["collectionId": "sessions"]],
            "orderBy": [[
                "field": ["fieldPath": "startedAt"],
                "direction": "DESCENDING",
            ]],
            "limit": 10,
        ], parent: "users/\(uid)")

        // El filtro va en el cliente: sumar `status` a la query exigiria un
        // indice compuesto, y son diez filas.
        //
        // `FS.isEmpty` y NO `== nil`: el telefono escribe finishedAt con
        // nullValue explicito, asi que el campo EXISTE aunque no haya
        // valor. Ver la nota en FS.isEmpty.
        let abiertas = rows.filter { FS.isEmpty($0.fields["finishedAt"]) }

        let decision = StaleSessionRules.decidir(
            candidatas: abiertas.map {
                StaleSessionRules.Candidata(
                    id: $0.id,
                    startedAt: parseTimestamp($0.fields["startedAt"]) ?? now
                )
            },
            ahora: now
        )

        // Best-effort a proposito: una limpieza que falla no puede dejar al
        // atleta sin poder entrenar. `try?` y no un catch con log porque este
        // archivo no tiene logger y agregarlo por esto seria mas ruido que
        // señal — el sintoma de que el barrido no entra es visible: la sesion
        // sigue apareciendo.
        for colgada in decision.aCerrar {
            try? await closeStaleSession(
                client: client, uid: uid, sessionId: colgada, closedAt: now
            )
        }

        guard let adoptar = decision.adoptar,
              let doc = abiertas.first(where: { $0.id == adoptar })
        else { return nil }

        let f = doc.fields
        // Sin `routineId` no se puede resolver que ejercicios mostrar. Se
        // devuelve nil en vez de seguir buscando hacia atras: caer a una sesion
        // MAS VIEJA teniendo una abierta mas nueva es exactamente el bug que
        // esta funcion acaba de dejar de tener.
        guard let routineId = FS.string(f["routineId"]) else { return nil }

        return ActiveSession(
            id: doc.id,
            routineId: routineId,
            routineName: FS.string(f["routineName"]) ?? "Rutina",
            dayNumber: FS.int(f["dayNumber"]) ?? 1,
            weekNumber: FS.int(f["weekNumber"]) ?? 0,
            startedAt: parseTimestamp(f["startedAt"]) ?? now
        )
    }

    /// Cierra una sesión que quedó colgada.
    ///
    /// Escribe los MISMOS campos que el barrido del teléfono
    /// (`SessionRepository.getActive`) y ninguno más: `totalVolumeKg` y
    /// `durationMin` se dejan como están —una sesión activa nace en 0 y nadie
    /// los toca hasta terminarla— porque inventarles un valor sería peor que
    /// dejar el 0 honesto.
    ///
    /// `wasFullyCompleted: false` es lo que hace que NO cuente como entreno
    /// hecho: no mueve el plan, ni la racha, ni los rankings.
    static func closeStaleSession(
        client: FirestoreREST,
        uid: String,
        sessionId: String,
        closedAt: Date
    ) async throws {
        try await client.patchFields(
            path: "users/\(uid)/sessions/\(sessionId)",
            fields: [
                "status": ["stringValue": "finished"],
                "finishedAt": ["timestampValue": iso(closedAt)],
                "wasFullyCompleted": ["booleanValue": false],
            ]
        )
    }

    /// Si la sesión ya está TERMINADA en el historial.
    ///
    /// El reloj lo consulta para cerrarse solo cuando el atleta terminó el
    /// entreno desde el teléfono. Sin esto el reloj se quedaba con la pantalla
    /// de entreno abierta sobre una sesión que ya no existe.
    static func isFinished(
        client: FirestoreREST,
        uid: String,
        sessionId: String
    ) async throws -> Bool {
        let doc = try await client.document("users/\(uid)/sessions/\(sessionId)")
        // Un doc que ya no está se trata como terminado: seguir mostrándolo
        // sería peor que cerrarlo.
        guard let doc else { return true }
        return FS.isPresent(doc["finishedAt"])
    }

    private static func parseTimestamp(_ field: Any?) -> Date? {
        guard let raw = (field as? [String: Any])?["timestampValue"] as? String
        else { return nil }
        let formatter = ISO8601DateFormatter()
        // Firestore devuelve fracciones de segundo; sin esta opción el parseo
        // falla en silencio y la duración del entreno sale mal.
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
            ?? ISO8601DateFormatter().date(from: raw)
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
            // `FS.isEmpty` y no `== nil`: sin esto una sesion ABIERTA creada en
            // el telefono se leia como terminada, el reloj no la adoptaba y
            // creaba una SEGUNDA sesion del mismo entreno.
            guard FS.isEmpty(f["finishedAt"]),
                  FS.int(f["dayNumber"]) == workout.dayNumber,
                  FS.int(f["weekNumber"]) == workout.weekNumber
            else { continue }
            return doc.id
        }
        return nil
    }

    /// Trae las series que hay en el historial para esta sesion.
    ///
    /// Es lo que permite ver en el reloj lo que se cargo desde el telefono.
    static func remoteSetLogs(
        client: FirestoreREST,
        uid: String,
        sessionId: String
    ) async throws -> [LoggedSet] {
        try await existingSetLogs(client: client, uid: uid, sessionId: sessionId)
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
                synced: true,
                // Se conserva el id REAL del documento: si lo escribio el
                // telefono es autogenerado, y volver a escribir con el id
                // deterministico del reloj crearia un segundo doc de la misma
                // serie.
                remoteDocId: doc.id
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

    /// Escribe una serie en el documento `docId`.
    ///
    /// El id lo elige QUIEN LLAMA, con `resolveSetLogWriteTarget`, no esta
    /// funcion. Decidir donde escribir necesita saber que hay en el historial, y
    /// eso es una lectura que `WorkoutCoordinator.sync` ya hace. Derivarlo aca a
    /// ciegas de `exerciseId__setNumber` era lo que dejaba DOS documentos de la
    /// misma serie cuando el telefono la habia cargado antes: su id autogenerado
    /// no coincide con el deterministico, asi que no habia nada que pisar.
    static func writeSetLog(
        client: FirestoreREST,
        uid: String,
        sessionId: String,
        docId: String,
        exerciseName: String,
        set: LoggedSet
    ) async throws {
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

    /// Marca la sesion como FINALIZADA en el historial.
    ///
    /// Sin esto el reloj borraba su estado local pero la sesion quedaba
    /// `active` en Firestore, asi que la app del telefono la seguia viendo
    /// pendiente y ofrecia retomarla — el bug que reporto el dueño.
    ///
    /// Escribe los mismos campos que `SessionRepository.finish` del telefono.
    /// `timestampValue` produce un Timestamp real de Firestore, que es lo que
    /// el @TimestampConverter del lado Dart espera al leer.
    static func finishSession(
        client: FirestoreREST,
        uid: String,
        sessionId: String,
        finishedAt: Date,
        totalVolumeKg: Double,
        durationMin: Int,
        wasFullyCompleted: Bool
    ) async throws {
        try await client.patchFields(
            path: "users/\(uid)/sessions/\(sessionId)",
            fields: [
                "status": ["stringValue": "finished"],
                "finishedAt": ["timestampValue": iso(finishedAt)],
                "totalVolumeKg": ["doubleValue": totalVolumeKg],
                "durationMin": ["integerValue": String(durationMin)],
                "wasFullyCompleted": ["booleanValue": wasFullyCompleted],
            ]
        )
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
