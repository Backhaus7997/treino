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

// MARK: - main

// El script pasa la raíz de `conformance/` como primer argumento.
let conformanceDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("conformance")

runPlanAdvance(fixtureURL: conformanceDir.appendingPathComponent("plan_advance.json"))
runRoutineSelection(fixtureURL: conformanceDir.appendingPathComponent("routine_selection.json"))

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
