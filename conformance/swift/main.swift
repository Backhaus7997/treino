//
//  main.swift
//
//  Corre los fixtures compartidos de `conformance/*.json` contra la
//  implementación SWIFT, la misma que usa el reloj.
//
//  El lado Dart corre los MISMOS archivos desde
//  `test/conformance/plan_advance_conformance_test.dart`. Ese es el punto: si
//  una implementación cambia y la otra no, uno de los dos corredores se pone
//  rojo antes de que el historial del usuario se corrompa en silencio.
//
//  Se compila junto al código real del reloj (no una copia), así que no puede
//  divergir de lo que corre en producción:
//
//      bash conformance/run_swift.sh
//

import Foundation

// MARK: - Utilidades de reporte

private var failures: [String] = []
private var totalCases = 0

private func fail(_ message: String) {
    failures.append(message)
}

// MARK: - plan_advance

private func runPlanAdvance(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL) else {
        fail("No se pudo leer \(fixtureURL.path). Los fixtures son el contrato "
            + "con la implementación Dart: si el archivo no está, ese contrato "
            + "no existe.")
        return
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let rule = json["rule"] as? String,
        let cases = json["cases"] as? [[String: Any]]
    else {
        fail("\(fixtureURL.lastPathComponent) no tiene la forma esperada.")
        return
    }

    guard rule == "plan-advance" else {
        fail("Se esperaba rule 'plan-advance' y vino '\(rule)'.")
        return
    }

    // Un fixture vacío pasaría en falso: es el modo de falla más peligroso de
    // este mecanismo.
    guard !cases.isEmpty else {
        fail("\(fixtureURL.lastPathComponent) no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        guard
            let given = testCase["given"] as? [String: Any],
            let expected = testCase["expect"] as? [String: Any],
            let numDays = given["numDays"] as? Int,
            let numWeeks = given["numWeeks"] as? Int,
            let expectedDay = expected["dayNumber"] as? Int,
            let expectedWeek = expected["weekNumber"] as? Int
        else {
            fail("  · \"\(name)\": el caso no tiene la forma esperada.")
            continue
        }

        var last: PlanPosition?
        if let lastRaw = given["lastFinished"] as? [String: Any],
           let day = lastRaw["dayNumber"] as? Int,
           let week = lastRaw["weekNumber"] as? Int {
            last = PlanPosition(dayNumber: day, weekNumber: week)
        }

        let actual = nextPlanPosition(
            lastFinished: last,
            numDays: numDays,
            numWeeks: numWeeks
        )

        if actual.dayNumber != expectedDay || actual.weekNumber != expectedWeek {
            fail("""
              · "\(name)"
                  esperado: día \(expectedDay), semana \(expectedWeek)
                  obtenido: día \(actual.dayNumber), semana \(actual.weekNumber)
            """)
        }
    }
}

// MARK: - routine_selection

private func runRoutineSelection(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = json["cases"] as? [[String: Any]], !cases.isEmpty
    else {
        fail("No se pudo leer \(fixtureURL.lastPathComponent) o no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        guard let given = testCase["given"] as? [String: Any],
              let expected = testCase["expect"] as? [String: Any],
              let assigned = given["assignedIds"] as? [String],
              let selfCreated = given["selfCreatedIds"] as? [String]
        else {
            fail("  · \"\(name)\": el caso no tiene la forma esperada.")
            continue
        }

        let actual = resolveActiveRoutineId(
            activeRoutineId: given["activeRoutineId"] as? String,
            assignedIds: assigned,
            selfCreatedIds: selfCreated
        )
        let expectedId = expected["routineId"] as? String

        if actual != expectedId {
            fail("""
              · "\(name)"
                  esperado: \(expectedId ?? "null")
                  obtenido: \(actual ?? "null")
            """)
        }
    }
}

// MARK: - set_resolution

private func specs(_ raw: Any?) -> [SetSpec] {
    (raw as? [[String: Any]] ?? []).map { s in
        SetSpec(
            reps: s["reps"] as? Int,
            repsMin: s["repsMin"] as? Int,
            repsMax: s["repsMax"] as? Int,
            weightKg: (s["weightKg"] as? NSNumber)?.doubleValue,
            durationSeconds: s["durationSeconds"] as? Int
        )
    }
}

private func describe(_ specs: [SetSpec]) -> String {
    // Se arma paso a paso a proposito: encadenado en una sola expresion, el
    // type-checker de Swift se queda sin tiempo y aborta la compilacion.
    var parts: [String] = []
    for spec in specs {
        let reps: String = spec.reps.map { String($0) } ?? "nil"
        let repsMin: String = spec.repsMin.map { String($0) } ?? "nil"
        let repsMax: String = spec.repsMax.map { String($0) } ?? "nil"
        let weight: String = spec.weightKg.map { String($0) } ?? "nil"
        let duration: String = spec.durationSeconds.map { String($0) } ?? "nil"
        parts.append("{reps:\(reps),min:\(repsMin),max:\(repsMax),kg:\(weight),dur:\(duration)}")
    }
    return "[" + parts.joined(separator: ", ") + "]"
}

private func runSetResolution(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let cases = json["cases"] as? [[String: Any]], !cases.isEmpty
    else {
        fail("No se pudo leer \(fixtureURL.lastPathComponent) o no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        guard let g = testCase["given"] as? [String: Any],
              let e = testCase["expect"] as? [String: Any],
              let week = g["week"] as? Int,
              let expectedPresent = e["isActive"] as? Bool
        else {
            fail("  · \"\(name)\": el caso no tiene la forma esperada.")
            continue
        }

        let slot = SlotPrescription(
            targetSets: g["targetSets"] as? Int ?? 0,
            durationSeconds: g["durationSeconds"] as? Int,
            targetReps: g["targetReps"] as? [Int] ?? [],
            targetRepsMin: g["targetRepsMin"] as? Int ?? 0,
            targetRepsMax: g["targetRepsMax"] as? Int ?? 0,
            targetWeightKg: (g["targetWeightKg"] as? NSNumber)?.doubleValue,
            sets: specs(g["sets"]),
            weeklySets: (g["weeklySets"] as? [Any] ?? []).map { specs($0) },
            activeWeeks: g["activeWeeks"] as? [Int] ?? []
        )

        let actualPresent = SetResolution.isPresentInWeek(slot, week: week)
        if actualPresent != expectedPresent {
            fail("""
              · "\(name)" (isActive)
                  esperado: \(expectedPresent)
                  obtenido: \(actualPresent)
            """)
        }

        let actual = describe(SetResolution.effectiveSets(slot, week: week))
        let expected = describe(specs(e["sets"]))
        if actual != expected {
            fail("""
              · "\(name)" (sets)
                  esperado: \(expected)
                  obtenido: \(actual)
            """)
        }
    }
}

// MARK: - session_counting

private func runSessionCounting(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL) else {
        fail("No se pudo leer \(fixtureURL.path). Los fixtures son el contrato "
            + "con la implementación Dart: si el archivo no está, ese contrato "
            + "no existe.")
        return
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let rule = json["rule"] as? String,
        let cases = json["cases"] as? [[String: Any]]
    else {
        fail("\(fixtureURL.lastPathComponent) no tiene la forma esperada.")
        return
    }

    guard rule == "session-counting" else {
        fail("Se esperaba rule 'session-counting' y vino '\(rule)'.")
        return
    }

    guard !cases.isEmpty else {
        fail("\(fixtureURL.lastPathComponent) no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        // `status` y `wasFullyCompleted` NO se validan con `guard let`: `null`
        // es una entrada legítima del contrato —campo ausente o nulo
        // explícito— y es justo el caso que hay que cubrir. `as? T` sobre
        // NSNull da nil, que es la semántica que queremos.
        guard
            let given = testCase["given"] as? [String: Any],
            let expected = testCase["expect"] as? [String: Any],
            let expectedValue = expected["countsAsWorkout"] as? Bool
        else {
            fail("  · \"\(name)\": el caso no tiene la forma esperada.")
            continue
        }

        let actual = sessionCountsAsWorkout(
            status: given["status"] as? String,
            wasFullyCompleted: given["wasFullyCompleted"] as? Bool
        )

        if actual != expectedValue {
            fail("""
              · "\(name)"
                  esperado: \(expectedValue)
                  obtenido: \(actual)
            """)
        }
    }
}

// MARK: - set_log_identity

private func runSetLogIdentity(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL) else {
        fail("No se pudo leer \(fixtureURL.path). Los fixtures son el contrato "
            + "con la implementación Dart: si el archivo no está, ese contrato "
            + "no existe.")
        return
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let rule = json["rule"] as? String,
        let cases = json["cases"] as? [[String: Any]]
    else {
        fail("\(fixtureURL.lastPathComponent) no tiene la forma esperada.")
        return
    }

    guard rule == "set-log-identity" else {
        fail("Se esperaba rule 'set-log-identity' y vino '\(rule)'.")
        return
    }

    guard !cases.isEmpty else {
        fail("\(fixtureURL.lastPathComponent) no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        guard
            let given = testCase["given"] as? [String: Any],
            let exerciseId = given["exerciseId"] as? String,
            let setNumber = given["setNumber"] as? Int,
            let expected = testCase["expect"] as? [String: Any],
            let expectedDocId = expected["docId"] as? String
        else {
            fail("  · \"\(name)\": el caso no tiene la forma esperada.")
            continue
        }

        let actual = setLogDeterministicDocId(
            exerciseId: exerciseId, setNumber: setNumber
        )

        if actual != expectedDocId {
            fail("""
              · "\(name)"
                  esperado: \(expectedDocId)
                  obtenido: \(actual)
            """)
        }
    }
}

// MARK: - superset_order

private func runSupersetOrder(fixtureURL: URL) {
    guard let data = try? Data(contentsOf: fixtureURL) else {
        fail("No se pudo leer \(fixtureURL.path). Los fixtures son el contrato "
            + "con la implementación Dart: si el archivo no está, ese contrato "
            + "no existe.")
        return
    }

    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let rule = json["rule"] as? String,
        let cases = json["cases"] as? [[String: Any]]
    else {
        fail("\(fixtureURL.lastPathComponent) no tiene la forma esperada.")
        return
    }

    guard rule == "superset-order" else {
        fail("Se esperaba rule 'superset-order' y vino '\(rule)'.")
        return
    }

    guard !cases.isEmpty else {
        fail("\(fixtureURL.lastPathComponent) no tiene casos.")
        return
    }

    for testCase in cases {
        totalCases += 1
        let name = testCase["name"] as? String ?? "(sin nombre)"

        guard
            let given = testCase["given"] as? [String: Any],
            let expected = testCase["expect"] as? [String: Any],
            let rawMembers = given["members"] as? [[String: Any]],
            let expectedRounds = expected["totalRounds"] as? Int
        else {
            fail("Caso '\(name)' mal formado.")
            continue
        }

        let members: [SupersetMember] = rawMembers.compactMap {
            guard
                let id = $0["exerciseId"] as? String,
                let planned = $0["plannedSets"] as? Int,
                let logged = $0["loggedSets"] as? Int
            else { return nil }
            return SupersetMember(exerciseId: id, plannedSets: planned, loggedSets: logged)
        }
        guard members.count == rawMembers.count else {
            fail("Caso '\(name)': algún miembro está mal formado.")
            continue
        }

        let rounds = SupersetOrder.totalRounds(members)
        if rounds != expectedRounds {
            fail("Caso '\(name)': vueltas totales — se esperaba \(expectedRounds) y vino \(rounds).")
            continue
        }

        let cell = SupersetOrder.nextCell(members)

        // `exerciseId: null` en el fixture significa bloque completo.
        if expected["exerciseId"] is NSNull || expected["exerciseId"] == nil {
            if let cell {
                fail("Caso '\(name)': se esperaba bloque completo y vino \(cell.exerciseId) serie \(cell.setNumber).")
            }
            continue
        }

        guard
            let expectedId = expected["exerciseId"] as? String,
            let expectedSet = expected["setNumber"] as? Int,
            let expectedRound = expected["round"] as? Int
        else {
            fail("Caso '\(name)': expect mal formado.")
            continue
        }

        guard let cell else {
            fail("Caso '\(name)': se esperaba \(expectedId) serie \(expectedSet) y vino bloque completo.")
            continue
        }

        if cell.exerciseId != expectedId || cell.setNumber != expectedSet || cell.round != expectedRound {
            fail("Caso '\(name)': se esperaba \(expectedId)/serie \(expectedSet)/vuelta \(expectedRound) "
                + "y vino \(cell.exerciseId)/serie \(cell.setNumber)/vuelta \(cell.round).")
        }
    }
}

// MARK: - main

// El script pasa la raíz de `conformance/` como primer argumento.
let conformanceDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("conformance")

runPlanAdvance(fixtureURL: conformanceDir.appendingPathComponent("plan_advance.json"))
runRoutineSelection(fixtureURL: conformanceDir.appendingPathComponent("routine_selection.json"))
runSetResolution(fixtureURL: conformanceDir.appendingPathComponent("set_resolution.json"))
runSessionCounting(fixtureURL: conformanceDir.appendingPathComponent("session_counting.json"))
runSetLogIdentity(fixtureURL: conformanceDir.appendingPathComponent("set_log_identity.json"))
runSupersetOrder(fixtureURL: conformanceDir.appendingPathComponent("superset_order.json"))

if failures.isEmpty {
    print("✓ conformidad Swift: \(totalCases) casos, todos en verde")
    exit(0)
} else {
    print("""
    ✗ La implementación SWIFT discrepa del contrato compartido \
    en \(failures.count) de \(totalCases) casos:

    \(failures.joined(separator: "\n"))

    Si el contrato es el correcto, arreglá la implementación Swift. Si el
    contrato está mal, corregí el JSON de conformance/ PRIMERO y después las
    DOS implementaciones — nunca al revés.
    """)
    exit(1)
}
