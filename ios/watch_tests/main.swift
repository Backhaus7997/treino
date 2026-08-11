//
//  main.swift
//
//  Tests de la logica PURA del reloj — la que no necesita ni HealthKit ni un
//  simulador. Se compila junto al codigo REAL del reloj, no una copia:
//
//      bash scripts/test_watch_swift.sh
//
//  Por que existe aparte de `conformance/`: aquellos fixtures son el contrato
//  Dart<->Swift, y estas reglas no tienen contraparte en Dart. Meterlas ahi
//  diluiria el significado de ese contrato.
//
//  Esta carpeta vive FUERA de `ios/TreinoWatch Watch App/` a proposito: ese
//  grupo es un PBXFileSystemSynchronizedRootGroup, asi que todo lo que caiga
//  adentro se compila DENTRO de la app que se le instala al atleta.
//

import Foundation

// MARK: - Utilidades de reporte

private var failures: [String] = []
private var totalChecks = 0

private func check(_ condition: Bool, _ message: String) {
    totalChecks += 1
    if !condition {
        failures.append(message)
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
    totalChecks += 1
    if actual != expected {
        failures.append("\(what): se esperaba \(expected) y vino \(actual)")
    }
}

// MARK: - Que tipos de Salud se piden
//
// El alcance del pedido es una decision de PRIVACIDAD, no un detalle tecnico:
// cada identificador de mas es un dato del atleta que TREINO no necesita, y
// algo que Apple pregunta en la review. Por eso la lista se fija acá y no se
// deja crecer sola.

private func runRequestedTypes() {
    // Lo que se LEE: el esfuerzo en vivo (F2).
    check(
        HealthAccess.readIdentifiers.contains("HKQuantityTypeIdentifierHeartRate"),
        "Se tiene que pedir LECTURA de ritmo cardiaco: es el dato que originó el ciclo."
    )

    // Lo que se ESCRIBE: decision D3, firmada — el entreno va a Salud para que
    // cuente en los anillos y el historial del atleta.
    check(
        HealthAccess.shareIdentifiers.contains("HKWorkoutTypeIdentifier"),
        "Se tiene que pedir ESCRITURA del tipo entreno (D3 firmada)."
    )

    // Nada de mas. Si alguien agrega un identificador, tiene que pasar por acá
    // y explicarlo — y acordarse de que el texto del permiso lo cubra.
    let permitidosLectura: Set<String> = [
        "HKQuantityTypeIdentifierHeartRate",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]
    let permitidosEscritura: Set<String> = [
        "HKWorkoutTypeIdentifier",
        "HKQuantityTypeIdentifierActiveEnergyBurned",
    ]
    let lecturaDeMas = Set(HealthAccess.readIdentifiers).subtracting(permitidosLectura)
    let escrituraDeMas = Set(HealthAccess.shareIdentifiers).subtracting(permitidosEscritura)
    check(
        lecturaDeMas.isEmpty,
        "Se pide LECTURA de datos no justificados: \(lecturaDeMas.sorted()). "
            + "Cada uno hay que explicarlo en la review de Apple."
    )
    check(
        escrituraDeMas.isEmpty,
        "Se pide ESCRITURA de datos no justificados: \(escrituraDeMas.sorted())."
    )

    // Listas vacias pasarian todo lo de arriba en falso.
    check(!HealthAccess.readIdentifiers.isEmpty, "La lista de lectura esta vacia.")
    check(!HealthAccess.shareIdentifiers.isEmpty, "La lista de escritura esta vacia.")
}

// MARK: - Cuando se pregunta

private func runShouldRequest() {
    // Sin Salud en el dispositivo no hay a quien preguntarle.
    checkEqual(
        HealthAccess.shouldRequest(current: .notRequested, isHealthDataAvailable: false),
        false,
        "Sin Salud disponible no se pregunta"
    )

    // Primera vez: se pregunta.
    checkEqual(
        HealthAccess.shouldRequest(current: .notRequested, isHealthDataAvailable: true),
        true,
        "La primera vez se pregunta"
    )

    // Ya contesto: no se vuelve a molestar. Salud no muestra la hoja dos veces,
    // pero pedirlo igual gasta un viaje en cada entreno.
    checkEqual(
        HealthAccess.shouldRequest(current: .resolved(canWriteWorkouts: true), isHealthDataAvailable: true),
        false,
        "Con el permiso ya resuelto no se vuelve a pedir"
    )
    checkEqual(
        HealthAccess.shouldRequest(current: .resolved(canWriteWorkouts: false), isHealthDataAvailable: true),
        false,
        "Aunque haya negado la escritura, no se vuelve a pedir"
    )

    // Si fallo, se reintenta: un error de Salud no es la respuesta del atleta.
    checkEqual(
        HealthAccess.shouldRequest(current: .failed("boom"), isHealthDataAvailable: true),
        true,
        "Un fallo de Salud se reintenta, no es una negativa del atleta"
    )

    checkEqual(
        HealthAccess.shouldRequest(current: .unsupported, isHealthDataAvailable: false),
        false,
        "Sin soporte no se pregunta"
    )
}

// MARK: - Como se lee la respuesta de Salud
//
// Sutileza que define el estado: HealthKit NO revela si el atleta nego la
// LECTURA. `authorizationStatus(for:)` contesta solo sobre los tipos de
// ESCRITURA; para los de lectura devuelve siempre `.notDetermined`, a proposito,
// para no filtrar que alguien no tiene datos de ese tipo.
//
// O sea: despues de pedir permiso sabemos si podemos ESCRIBIR, y de la lectura
// nos enteramos recien cuando llegan —o no llegan— pulsaciones (F2).

private func runAuthorizationMapping() {
    checkEqual(
        HealthAccess.stateAfterRequest(shareStatus: .sharingAuthorized),
        .resolved(canWriteWorkouts: true),
        "Escritura autorizada"
    )
    checkEqual(
        HealthAccess.stateAfterRequest(shareStatus: .sharingDenied),
        .resolved(canWriteWorkouts: false),
        "Escritura negada"
    )
    // `notDetermined` despues de pedir permiso pasa de verdad: es lo que
    // contesta Salud cuando el atleta cierra la hoja sin decidir.
    checkEqual(
        HealthAccess.stateAfterRequest(shareStatus: .notDetermined),
        .resolved(canWriteWorkouts: false),
        "Hoja cerrada sin decidir: se asume que no se puede escribir"
    )
}

// MARK: - D2: el entreno nunca depende del permiso
//
// Decision FIRMADA por el dueño: si el atleta niega el permiso, el entreno
// funciona igual, sin pulsaciones y sin degradar nada mas.
//
// Este bloque es un alambre de trampa. Si algun dia se pone rojo, alguien esta
// cambiando una decision firmada — y eso vuelve al dueño, no se arregla
// tocando la linea que lo hace pasar.

private func runNeverBlocksWorkout() {
    let todosLosEstados: [HealthAccessState] = [
        .unsupported,
        .notRequested,
        .resolved(canWriteWorkouts: true),
        .resolved(canWriteWorkouts: false),
        .failed("Salud no contesto"),
    ]

    for estado in todosLosEstados {
        check(
            estado.blocksWorkout == false,
            "D2 rota: el estado \(estado) bloquea el entreno. El permiso de Salud "
                + "NUNCA puede ser condicion para entrenar."
        )
    }
}

// MARK: - Corrida

runRequestedTypes()
runShouldRequest()
runAuthorizationMapping()
runNeverBlocksWorkout()

if failures.isEmpty {
    print("OK: \(totalChecks) chequeos de la logica de permisos de Salud")
    exit(0)
}

print("FALLA: \(failures.count) de \(totalChecks) chequeos")
for failure in failures {
    print("  ✗ \(failure)")
}
exit(1)
