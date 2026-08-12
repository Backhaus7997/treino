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

// MARK: - El ciclo de vida de la sesion de entrenamiento (F1)
//
// La garantia que define F1: UNA SOLA HKWorkoutSession por entreno.
//
// No es paranoia. El reloj entra en modo entreno por tres caminos, y al
// arrancar la app dos corren EN PARALELO: `restore()` desde el .task y
// `adoptRemoteSessionIfAny()` desde el onChange de scenePhase. En F0 se midio
// que los dos se ejecutan. Si cada uno abriera su sesion, watchOS tendria dos
// entrenamientos abiertos para uno solo del atleta.
//
// La defensa NO va en cada llamador —son tres, y mañana pueden ser cuatro—
// sino en el recurso: abrir con una sesion ya abierta es un NO-OP.

private func runSessionLifecycleBasics() {
    var r = WorkoutSessionLifecycle.resolve(.begin, in: .idle)
    check(r.execute, "Abrir desde idle tiene que ejecutarse")
    checkEqual(r.next, .open, "Abrir desde idle deja la sesion abierta")

    // LA GARANTIA DE F1.
    r = WorkoutSessionLifecycle.resolve(.begin, in: .open)
    check(
        !r.execute,
        "Abrir con una sesion YA ABIERTA tiene que ser un NO-OP. Si esto se pone "
            + "rojo, watchOS termina con dos entrenamientos para uno solo del atleta."
    )
    checkEqual(r.next, .open, "Un begin ignorado no cambia el estado")

    r = WorkoutSessionLifecycle.resolve(.end, in: .open)
    check(r.execute, "Cerrar una sesion abierta tiene que ejecutarse")
    checkEqual(r.next, .idle, "Cerrar deja la sesion en idle")

    // Pasa de verdad: el atleta descarta un entreno que el reloj nunca abrio.
    r = WorkoutSessionLifecycle.resolve(.end, in: .idle)
    check(!r.execute, "Cerrar sin sesion abierta tiene que ser un NO-OP")
    checkEqual(r.next, .idle, "Un end ignorado no cambia el estado")
}

private func runSessionLifecycleSequences() {
    func correr(_ comandos: [WorkoutSessionCommand])
        -> (aperturas: Int, cierres: Int, final: WorkoutSessionPhase)
    {
        var phase = WorkoutSessionPhase.idle
        var aperturas = 0
        var cierres = 0
        for c in comandos {
            let r = WorkoutSessionLifecycle.resolve(c, in: phase)
            if r.execute {
                if c == .begin { aperturas += 1 } else { cierres += 1 }
            }
            phase = r.next
        }
        return (aperturas, cierres, phase)
    }

    // La carrera medida en F0: varios caminos pidiendo abrir a la vez.
    var s = correr([.begin, .begin, .begin])
    checkEqual(s.aperturas, 1, "Tres begin tienen que abrir UNA sola sesion")
    checkEqual(s.final, .open, "Y dejarla abierta")

    s = correr([.begin, .end, .end, .end])
    checkEqual(s.aperturas, 1, "Una apertura")
    checkEqual(s.cierres, 1, "Un solo cierre, aunque pidan tres")
    checkEqual(s.final, .idle, "Termina cerrada")

    // Idempotente no es "una sola vez en la vida de la app": un entreno nuevo
    // SI abre otra sesion.
    s = correr([.begin, .end, .begin, .end])
    checkEqual(s.aperturas, 2, "Dos entrenos seguidos abren dos sesiones")
    checkEqual(s.cierres, 2, "Y cierran las dos")
    checkEqual(s.final, .idle, "Termina cerrada")

    // Invariante sobre una secuencia larga y desordenada: en todo momento hay
    // como maximo UNA sesion abierta, y nunca se cierra algo que no se abrio.
    //
    // La secuencia es DETERMINISTICA a proposito: un test que falla distinto en
    // cada corrida no se puede depurar.
    var comandos: [WorkoutSessionCommand] = []
    var x = 7
    for _ in 0..<200 {
        x = (x &* 1103515245 &+ 12345) & 0x7FFF_FFFF
        comandos.append(x % 3 == 0 ? .end : .begin)
    }

    var phase = WorkoutSessionPhase.idle
    var abiertas = 0
    var violaciones = 0
    for c in comandos {
        let r = WorkoutSessionLifecycle.resolve(c, in: phase)
        if r.execute {
            abiertas += (c == .begin ? 1 : -1)
            if abiertas < 0 || abiertas > 1 { violaciones += 1 }
        }
        phase = r.next
    }
    checkEqual(
        violaciones, 0,
        "En 200 ordenes desordenadas nunca puede haber dos sesiones abiertas ni "
            + "un cierre sin apertura"
    )
}

// MARK: - Ritmo cardiaco en pantalla (F2)
//
// La regla que mas importa acá NO es mostrar el numero: es NO MENTIR cuando no
// hay dato.
//
// En F0 se midio que una lectura negada por el atleta es INDISTINGUIBLE de "no
// hay datos": las dos dan una query exitosa con cero muestras. Y en un
// entrenamiento real el sensor se corta seguido —muñeca floja, brazo en
// posicion rara—. Mostrar la ultima lectura conocida como si fuera actual es
// mentirle al atleta sobre su propio esfuerzo.

private func runHeartRateDisplay() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // Sin ninguna lectura: no hay nada que mostrar.
    checkEqual(
        HeartRateRules.display(reading: nil, now: t0),
        .sinDatos,
        "Sin lecturas no se muestra numero"
    )

    // Lectura recien tomada.
    checkEqual(
        HeartRateRules.display(reading: HeartRateReading(bpm: 142, takenAt: t0), now: t0),
        .bpm(142),
        "Una lectura del momento se muestra"
    )

    // Lectura de hace poco: sigue valiendo. El reloj muestrea cada ~5s.
    checkEqual(
        HeartRateRules.display(
            reading: HeartRateReading(bpm: 138, takenAt: t0),
            now: t0.addingTimeInterval(10)
        ),
        .bpm(138),
        "A los 10s la lectura sigue siendo actual"
    )

    // LECTURA VIEJA: se deja de mostrar. Es la regla que evita la mentira.
    checkEqual(
        HeartRateRules.display(
            reading: HeartRateReading(bpm: 138, takenAt: t0),
            now: t0.addingTimeInterval(HeartRateRules.maxAntiguedad + 1)
        ),
        .sinDatos,
        "Pasada la antiguedad maxima se deja de mostrar en vez de mentir"
    )

    // Justo en el limite todavia vale: el corte es estrictamente mayor.
    checkEqual(
        HeartRateRules.display(
            reading: HeartRateReading(bpm: 150, takenAt: t0),
            now: t0.addingTimeInterval(HeartRateRules.maxAntiguedad)
        ),
        .bpm(150),
        "Justo en el limite la lectura todavia vale"
    )

    // Reloj corrido hacia atras: una lectura "del futuro" no puede borrar la
    // pantalla. Es un problema del reloj, no del atleta.
    //
    // El desfase de prueba tiene que ser MAYOR que maxAntiguedad. Con uno chico
    // el test no distingue esta regla de `abs(antiguedad) > maxAntiguedad`, que
    // es la implementacion equivocada: esa SI borraria la pantalla ante un
    // desfase grande. (Se descubrio justamente asi: la mutacion sobrevivio.)
    for adelanto in [5.0, HeartRateRules.maxAntiguedad * 4] {
        checkEqual(
            HeartRateRules.display(
                reading: HeartRateReading(bpm: 130, takenAt: t0.addingTimeInterval(adelanto)),
                now: t0
            ),
            .bpm(130),
            "Una lectura \(Int(adelanto))s en el futuro se toma como actual, no se descarta"
        )
    }

    // Valores imposibles: 0 pulsaciones no es una medicion, es un sensor que no
    // engancho. Mostrarlo asustaria al atleta.
    for imposible in [0, -5] {
        checkEqual(
            HeartRateRules.display(reading: HeartRateReading(bpm: imposible, takenAt: t0), now: t0),
            .sinDatos,
            "Un bpm de \(imposible) no es una medicion"
        )
    }
}

private func runHeartRateRounding() {
    // HealthKit entrega Double; la pantalla muestra entero. Se redondea, no se
    // trunca: 141.6 es mas cerca de 142 que de 141.
    checkEqual(HeartRateReading.bpm(fromQuantity: 141.6), 142, "141.6 redondea a 142")
    checkEqual(HeartRateReading.bpm(fromQuantity: 141.4), 141, "141.4 redondea a 141")
    checkEqual(HeartRateReading.bpm(fromQuantity: 0), 0, "0 se preserva para que la regla lo descarte")
}

// MARK: - De donde sale la duracion (F3, decision D4)
//
// D4, firmada: la sesion de entrenamiento pasa a ser la fuente de verdad cuando
// existe, y el calculo actual queda como respaldo.

private func runWorkoutDuration() {
    let inicio = Date(timeIntervalSince1970: 1_700_000_000)

    // Con medicion de la sesion: manda esa.
    var r = WorkoutDurationRules.minutes(
        measuredSeconds: 42 * 60, startedAt: inicio, now: inicio.addingTimeInterval(90 * 60)
    )
    checkEqual(r.minutes, 42, "Con medicion manda la medicion, no el reloj de pared")
    checkEqual(r.source, .medida, "Y se declara que salio de la sesion")

    // Sin medicion: cae al calculo de siempre.
    r = WorkoutDurationRules.minutes(
        measuredSeconds: nil, startedAt: inicio, now: inicio.addingTimeInterval(35 * 60)
    )
    checkEqual(r.minutes, 35, "Sin medicion se calcula por reloj de pared")
    checkEqual(r.source, .calculada, "Y se declara que fue calculada")

    // Piso de 1: un entreno relampago igual duro algo, y un 0 se lee como "no
    // se registro". Es la regla que ya tenia el reloj y no cambia.
    r = WorkoutDurationRules.minutes(
        measuredSeconds: 20, startedAt: inicio, now: inicio.addingTimeInterval(20)
    )
    checkEqual(r.minutes, 1, "Un entreno de 20 segundos cuenta como 1 minuto")

    // TECHO: una sesion olvidada no puede escribir una duracion absurda.
    // El telefono ya acota a 8 horas (session_duration.dart); sin esto el mismo
    // entreno daria distinto segun quien lo termine.
    r = WorkoutDurationRules.minutes(
        measuredSeconds: 20 * 3600, startedAt: inicio, now: inicio.addingTimeInterval(20 * 3600)
    )
    checkEqual(r.minutes, WorkoutDurationRules.maxMinutos, "20 horas se acotan al techo")
    r = WorkoutDurationRules.minutes(
        measuredSeconds: nil, startedAt: inicio, now: inicio.addingTimeInterval(20 * 3600)
    )
    checkEqual(r.minutes, WorkoutDurationRules.maxMinutos, "El techo tambien aplica al calculo de respaldo")

    // El techo es el MISMO que el del telefono. Si alguien cambia uno solo, los
    // dos lados vuelven a discrepar.
    checkEqual(WorkoutDurationRules.maxMinutos, 8 * 60, "El techo son 8 horas, igual que en el telefono")
}

// MARK: - Corrida

runRequestedTypes()
runShouldRequest()
runAuthorizationMapping()
runNeverBlocksWorkout()
runSessionLifecycleBasics()
runSessionLifecycleSequences()
runHeartRateDisplay()
runHeartRateRounding()
runWorkoutDuration()

if failures.isEmpty {
    print("OK: \(totalChecks) chequeos de la logica de permisos de Salud")
    exit(0)
}

print("FALLA: \(failures.count) de \(totalChecks) chequeos")
for failure in failures {
    print("  ✗ \(failure)")
}
exit(1)
