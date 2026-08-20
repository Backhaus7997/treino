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

/// Lee un entero de 64 bits del fixture.
///
/// `as? Int` alcanzaría en este corredor, que compila en el host — y ese es
/// justamente el problema. En watchOS `Int` es de 32 bits (arm64_32) y los
/// milisegundos desde epoch rondan 1,8e12, así que ahí ese cast devolvería nil
/// y la regla no correría nunca. Leerlos como `Int64` acá mantiene el corredor
/// bajo la misma disciplina que el código del reloj.
private func int64(_ any: Any?) -> Int64? {
    (any as? NSNumber)?.int64Value
}

/// Un instante a partir de milisegundos desde epoch.
private func fecha(desdeMs ms: Int64) -> Date {
    Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
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

// MARK: - duration_timer

private func runDurationTimer(fixtureURL: URL) {
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

    guard rule == "duration-timer" else {
        fail("Se esperaba rule 'duration-timer' y vino '\(rule)'.")
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
            let endsAtMs = int64(given["endsAtMs"]),
            let nowMs = int64(given["nowMs"]),
            let expectedRemaining = expected["remaining"] as? Int,
            let expectedFinished = expected["finished"] as? Bool
        else {
            fail("Caso '\(name)' mal formado.")
            continue
        }

        let endsAt = fecha(desdeMs: endsAtMs)
        let now = fecha(desdeMs: nowMs)

        let restante = CountdownRules.remaining(endsAt: endsAt, now: now)
        if restante != expectedRemaining {
            fail("Caso '\(name)': segundos restantes — se esperaba "
                + "\(expectedRemaining) y vino \(restante).")
        }

        let termino = CountdownRules.isFinished(endsAt: endsAt, now: now)
        if termino != expectedFinished {
            fail("Caso '\(name)': terminada — se esperaba \(expectedFinished) "
                + "y vino \(termino).")
        }
    }
}

// MARK: - effort_payload

/// Este contrato es ASIMETRICO: Swift ESCRIBE el diccionario y Dart lo LEE. Acá
/// se verifica la mitad de Swift — que `EffortSnapshot.context(measuredAt:)`
/// produzca exactamente el diccionario del fixture, clave por clave.
private func runEffortPayload(fixtureURL: URL) {
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

    guard rule == "effort-payload" else {
        fail("Se esperaba rule 'effort-payload' y vino '\(rule)'.")
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
            let esperado = testCase["expect"] as? [String: Any],
            let measuredAtMs = int64(given["measuredAtMs"])
        else {
            fail("Caso '\(name)' mal formado.")
            continue
        }

        // `NSNull` es como JSONSerialization representa un null explícito del
        // fixture; hay que distinguirlo de "la clave no está".
        let bpm = given["bpm"] as? Int
        let kcal = given["kcal"] as? Int

        var cronometro: EffortSnapshot.RunningTimer?
        if let t = given["timer"] as? [String: Any] {
            guard
                let exerciseId = t["exerciseId"] as? String,
                let setNumber = t["setNumber"] as? Int,
                let totalSeconds = t["totalSeconds"] as? Int,
                let endsAtMs = int64(t["endsAtMs"])
            else {
                fail("Caso '\(name)': el cronómetro del fixture está mal formado.")
                continue
            }
            cronometro = EffortSnapshot.RunningTimer(
                exerciseId: exerciseId,
                setNumber: setNumber,
                totalSeconds: totalSeconds,
                endsAt: fecha(desdeMs: endsAtMs)
            )
        }

        let snapshot = EffortSnapshot(bpm: bpm, kcal: kcal, timer: cronometro)
        let payload = snapshot.context(measuredAt: fecha(desdeMs: measuredAtMs))

        // Mismo conjunto de claves, ni una de más ni una de menos. Una clave de
        // más es tan grave como una de menos: significa que un lado manda algo
        // que el otro no sabe que existe.
        let clavesEsperadas = Set(esperado.keys)
        let clavesReales = Set(payload.keys)
        if clavesEsperadas != clavesReales {
            let sobran = clavesReales.subtracting(clavesEsperadas).sorted()
            let faltan = clavesEsperadas.subtracting(clavesReales).sorted()
            fail("Caso '\(name)': las claves no coinciden — sobran \(sobran), faltan \(faltan).")
            continue
        }

        for (clave, valorEsperado) in esperado {
            let valorReal = payload[clave]
            let ok: Bool
            switch valorEsperado {
            case let s as String:
                ok = (valorReal as? String) == s
            case let n as NSNumber:
                // Los enteros viajan como Int o Int64 según la clave; comparar
                // por valor de 64 bits cubre las dos sin perder precisión.
                ok = int64(valorReal) == n.int64Value
            default:
                ok = false
            }
            if !ok {
                fail("Caso '\(name)': clave '\(clave)' — se esperaba "
                    + "\(valorEsperado) y vino \(valorReal.map { String(describing: $0) } ?? "nada").")
            }
        }

        // TODA clave de milisegundos tiene que salir como `Int64`.
        //
        // Se recorre por nombre y no se chequea una sola a mano: la comparación
        // de valores de arriba usa `int64(...)`, que en el host de 64 bits es
        // CIEGA al tipo — un `Int64` cambiado a `Int` dejaría el corredor en
        // verde y crashearía el reloj. Es lo único observable desde acá sobre la
        // trampa de arm64_32.
        for clave in esperado.keys where clave.hasSuffix("Ms") {
            guard let valor = payload[clave] else { continue }
            if !(valor is Int64) {
                fail("Caso '\(name)': '\(clave)' tiene que ser Int64 y es \(type(of: valor)). "
                    + "Con `Int` trapea en arm64_32 — ver commit 3a0840cc.")
            }
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
runDurationTimer(fixtureURL: conformanceDir.appendingPathComponent("duration_timer.json"))
runEffortPayload(fixtureURL: conformanceDir.appendingPathComponent("effort_payload.json"))

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
