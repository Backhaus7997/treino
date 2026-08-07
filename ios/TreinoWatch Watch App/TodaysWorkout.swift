//
//  TodaysWorkout.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F2.
//

import Foundation

/// Un ejercicio del entreno, con sus series ya resueltas para la semana.
struct WatchExercise: Equatable {
    let exerciseId: String
    let exerciseName: String
    let sets: [SetSpec]
    let restSeconds: Int
}

/// El entreno que le toca al atleta hoy, resuelto por el reloj.
struct TodaysWorkout: Equatable {
    let routineId: String
    let routineName: String
    let dayName: String
    let dayNumber: Int
    let weekNumber: Int
    let numWeeks: Int
    let exercises: [WatchExercise]

    var exerciseCount: Int { exercises.count }
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
        guard let doc = try await findRoutine(client: client, uid: uid) else {
            return nil
        }

        // El ID sale del PATH, no de un campo: los docs creados por la app no
        // guardan `id` adentro.
        let routineId = doc.id
        let routine = doc.fields
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
            routineId: routineId,
            routineName: FS.string(routine["name"]) ?? "Rutina",
            dayName: FS.string(dayFields?["name"]) ?? "Día \(position.dayNumber)",
            dayNumber: position.dayNumber,
            weekNumber: position.weekNumber,
            numWeeks: FS.int(routine["numWeeks"]) ?? 1,
            exercises: exercises(
                from: FS.array(dayFields?["slots"]) ?? [],
                week: position.weekNumber
            )
        )
    }

    /// Traduce los slots de Firestore a ejercicios con series resueltas.
    ///
    /// Filtra por `isPresentInWeek`: un ejercicio con máscara de semanas que no
    /// incluye la actual NO va en el entreno de hoy. Mostrarlo igual sería
    /// hacerle hacer al atleta algo que el plan no pide esta semana.
    private static func exercises(from slots: [Any], week: Int) -> [WatchExercise] {
        var result: [WatchExercise] = []
        for slot in slots {
            guard let f = FS.mapFields(slot) else { continue }

            let prescription = SlotPrescription(
                targetSets: FS.int(f["targetSets"]) ?? 0,
                durationSeconds: FS.int(f["durationSeconds"]),
                targetReps: (FS.array(f["targetReps"]) ?? []).compactMap { FS.int($0) },
                targetRepsMin: FS.int(f["targetRepsMin"]) ?? 0,
                targetRepsMax: FS.int(f["targetRepsMax"]) ?? 0,
                targetWeightKg: FS.double(f["targetWeightKg"]),
                sets: setSpecs(FS.array(f["sets"])),
                weeklySets: (FS.array(f["weeklySets"]) ?? []).map { week in
                    // Firestore rechaza arrays anidados, asi que cada semana
                    // viaja envuelta en un map con la clave `sets`.
                    setSpecs(FS.array(FS.mapFields(week)?["sets"]))
                },
                activeWeeks: (FS.array(f["activeWeeks"]) ?? []).compactMap { FS.int($0) }
            )

            guard SetResolution.isPresentInWeek(prescription, week: week) else { continue }

            result.append(
                WatchExercise(
                    exerciseId: FS.string(f["exerciseId"]) ?? "",
                    exerciseName: FS.string(f["exerciseName"]) ?? "Ejercicio",
                    sets: SetResolution.effectiveSets(prescription, week: week),
                    restSeconds: FS.int(f["restSeconds"]) ?? 90
                )
            )
        }
        return result
    }

    private static func setSpecs(_ raw: [Any]?) -> [SetSpec] {
        (raw ?? []).compactMap { item in
            guard let f = FS.mapFields(item) else { return nil }
            return SetSpec(
                reps: FS.int(f["reps"]),
                repsMin: FS.int(f["repsMin"]),
                repsMax: FS.int(f["repsMax"]),
                weightKg: FS.double(f["weightKg"]),
                durationSeconds: FS.int(f["durationSeconds"])
            )
        }
    }

    /// Aplica la MISMA prioridad que el teléfono, vía `resolveActiveRoutineId`.
    ///
    /// El marcador `activeRoutineId` vive en el doc del usuario, así que hay
    /// que leerlo antes: sin él el reloj se saltearía el tier 0 y podría elegir
    /// una rutina distinta a la que el atleta marcó.
    private static func findRoutine(
        client: FirestoreREST,
        uid: String
    ) async throws -> FirestoreDocument? {
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

        guard let resolvedId = resolveActiveRoutineId(
            activeRoutineId: activeRoutineId,
            assignedIds: assigned.map(\.id),
            selfCreatedIds: selfCreated.map(\.id)
        ) else { return nil }

        return (assigned + selfCreated).first { $0.id == resolvedId }
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

        for doc in sessions {
            let fields = doc.fields
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
