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

// MARK: - Calorias en pantalla
//
// LA DIFERENCIA DE FONDO CON EL RITMO CARDIACO, y la razon por la que estas dos
// reglas NO comparten codigo aunque se parezcan en la pantalla:
//
//   El ritmo cardiaco es INSTANTANEO. Una lectura vieja es una MENTIRA: dice
//   "estas a 140" cuando hace 40 segundos que no se mide.
//
//   Las calorias son ACUMULADAS. Una lectura vieja sigue siendo VERDAD: si hace
//   40 segundos habias quemado 120, ahora quemaste 120 o mas. Borrarla seria
//   ocultar algo cierto.
//
// Por eso las calorias no caducan y el ritmo cardiaco si.

private func runActiveEnergyDisplay() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    checkEqual(
        ActiveEnergyRules.display(reading: nil, now: t0),
        .sinDatos,
        "Sin lecturas no se muestra nada"
    )

    checkEqual(
        ActiveEnergyRules.display(
            reading: ActiveEnergyReading(kcal: 87, takenAt: t0), now: t0
        ),
        .kcal(87),
        "Una lectura del momento se muestra"
    )

    // LO QUE LA DISTINGUE DEL RITMO CARDIACO: no caduca.
    for antiguedad in [30.0, 300.0, 3600.0] {
        checkEqual(
            ActiveEnergyRules.display(
                reading: ActiveEnergyReading(kcal: 210, takenAt: t0),
                now: t0.addingTimeInterval(antiguedad)
            ),
            .kcal(210),
            "A los \(Int(antiguedad))s las calorias SIGUEN valiendo: son acumuladas, no instantaneas"
        )
    }

    // Y 0 kcal SI se muestra, al reves que 0 bpm.
    //
    // Un 0 de pulsaciones es imposible: es un sensor que no engancho. Un 0 de
    // calorias es cierto — todavia no se midio consumo. Ocultarlo seria
    // esconder un dato verdadero, que es el mismo pecado que mostrar uno falso.
    checkEqual(
        ActiveEnergyRules.display(
            reading: ActiveEnergyReading(kcal: 0, takenAt: t0), now: t0
        ),
        .kcal(0),
        "0 kcal es un dato cierto y se muestra (a diferencia de 0 bpm)"
    )

    // Negativo si es imposible: no se puede des-quemar energia.
    checkEqual(
        ActiveEnergyRules.display(
            reading: ActiveEnergyReading(kcal: -3, takenAt: t0), now: t0
        ),
        .sinDatos,
        "Un valor negativo no es una medicion"
    )

    // HealthKit entrega Double; la pantalla muestra entero.
    checkEqual(ActiveEnergyReading.kcal(fromQuantity: 86.7), 87, "86.7 redondea a 87")
    checkEqual(ActiveEnergyReading.kcal(fromQuantity: 86.2), 86, "86.2 redondea a 86")
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
runActiveEnergyDisplay()
runWorkoutDuration()
runEffortBroadcast()
runSetLogWriteTarget()
runSetLogDeletion()
runExerciseCursor()
runStaleSessions()
runCloseFeedback()

if failures.isEmpty {
    print("OK: \(totalChecks) chequeos de la logica de permisos de Salud")
    exit(0)
}

print("FALLA: \(failures.count) de \(totalChecks) chequeos")
for failure in failures {
    print("  ✗ \(failure)")
}
exit(1)

// MARK: - Cuando el reloj le manda el esfuerzo al telefono (F4)
//
// El reloj recolecta pulsaciones cada ~5 segundos. Mandar cada muestra por
// WatchConnectivity seria despertar al telefono decenas de veces por entreno
// para nada: el atleta mira la pantalla del celular de vez en cuando, no
// continuamente.
//
// Estas reglas deciden CUANDO vale la pena mandar. Son puras y se testean en el
// host; el envio en si vive en `EffortRelay.swift`.

private func runEffortBroadcast() {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    let a = EffortSnapshot(bpm: 140, kcal: 50)
    let b = EffortSnapshot(bpm: 145, kcal: 52)

    // Primera vez: siempre se manda, no hay con que comparar.
    check(
        EffortBroadcastRules.shouldSend(last: nil, actual: a, now: t0),
        "El primer dato siempre se manda"
    )

    // Muy seguido: no. El limite es del sistema tambien — updateApplicationContext
    // esta rate-limited, y pasarse hace que descarte envios en silencio.
    check(
        !EffortBroadcastRules.shouldSend(
            last: (a, t0), actual: b,
            now: t0.addingTimeInterval(EffortBroadcastRules.minIntervalo - 1)
        ),
        "Antes del intervalo minimo no se manda, aunque el valor haya cambiado"
    )

    // Pasado el intervalo y con valor nuevo: se manda.
    check(
        EffortBroadcastRules.shouldSend(
            last: (a, t0), actual: b,
            now: t0.addingTimeInterval(EffortBroadcastRules.minIntervalo)
        ),
        "Pasado el intervalo, un valor nuevo se manda"
    )

    // Pasado el intervalo pero SIN cambio: no se manda.
    //
    // El telefono ya tiene ese dato y su regla de antiguedad es de 45s, asi que
    // reenviar lo mismo no le agrega nada y le cuesta una activacion.
    check(
        !EffortBroadcastRules.shouldSend(
            last: (a, t0), actual: a,
            now: t0.addingTimeInterval(EffortBroadcastRules.minIntervalo * 10)
        ),
        "Un valor identico no se reenvia por mas que pase el tiempo"
    )

    // Un snapshot sin ninguna medicion no se manda: no hay nada que mostrar y
    // el telefono ya sabe no dibujar nada.
    check(
        !EffortBroadcastRules.shouldSend(
            last: nil, actual: EffortSnapshot(bpm: nil, kcal: nil), now: t0
        ),
        "Un snapshot vacio no se manda"
    )
}

// MARK: - Donde escribe el reloj cada serie
//
// El bug que estas reglas cierran, medido contra el emulador el 2026-08-11 sobre
// sesiones de `seed-athlete-001`: la misma serie marcada en el reloj y en el
// telefono dejaba DOS documentos en Firestore. En las 7 sesiones inspeccionadas,
// 5 tenian duplicados; la peor, 17 documentos para 10 series reales. Los 7
// documentos de una de ellas tenian `createTime == updateTime`, o sea que
// ninguna escritura piso nunca a otra: los dos clientes acunan ids distintos
// para la misma fila logica, asi que el que escribe segundo no tiene contra que
// deduplicar y crea uno nuevo.
//
// La deduplicacion pasa entonces a decidirse por identidad LOGICA contra lo que
// el historial ya tiene, no por el id. Es una decision pura para poder medirla
// acá: verificarla corriendo el reloj cuesta dos builds y una carrera de
// segundos que no se reproduce a pedido.

private func runSetLogWriteTarget() {
    let deterministic = setLogDeterministicDocId(
        exerciseId: "peso-muerto", setNumber: 1
    )
    checkEqual(deterministic, "peso-muerto__1", "El id deterministico")

    // Historial vacio: el caso normal, se escribe con el id deterministico.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto", setNumber: 1, remote: []
        ),
        .write(docId: "peso-muerto__1"),
        "Sin nada en el historial se usa el id deterministico"
    )

    // La serie ya esta, escrita por el TELEFONO con id autogenerado. Es el caso
    // que dejaba dos documentos: por id no matcheaba nunca.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 1,
            remote: [
                RemoteSetLogRef(
                    docId: "EeFxyim8WMzP8qQvpGxj",
                    exerciseId: "peso-muerto",
                    setNumber: 1
                )
            ]
        ),
        .alreadyThere(docId: "EeFxyim8WMzP8qQvpGxj"),
        "Una serie que el telefono ya cargo no se vuelve a escribir"
    )

    // La escribio un intento anterior del reloj: tampoco se reescribe.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 2,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__2",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                )
            ]
        ),
        .alreadyThere(docId: "peso-muerto__2"),
        "Una serie que el propio reloj ya subio no se reescribe"
    )

    // Otras series del mismo ejercicio no bloquean: la identidad es el PAR
    // ejercicio + numero de serie, no el ejercicio.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 3,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__1",
                    exerciseId: "peso-muerto",
                    setNumber: 1
                ),
                RemoteSetLogRef(
                    docId: "lUbF5qxLk72UbRggR084",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                ),
            ]
        ),
        .write(docId: "peso-muerto__3"),
        "Una serie nueva del mismo ejercicio se escribe normal"
    )

    // La misma serie de OTRO ejercicio no cuenta.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 1,
            remote: [
                RemoteSetLogRef(
                    docId: "remo-barra__1",
                    exerciseId: "remo-barra",
                    setNumber: 1
                )
            ]
        ),
        .write(docId: "peso-muerto__1"),
        "La serie 1 de otro ejercicio no es esta serie"
    )

    // La ruta deterministica ocupada por OTRA serie logica. Pasa despues de que
    // el telefono borre una serie: al renumerar conserva el id del documento y
    // baja el campo `setNumber`, asi que `peso-muerto__3` puede contener la
    // serie 2. Escribir ahi PERDERIA esa serie — peor que el duplicado que este
    // arreglo vino a cerrar.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 3,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__3",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                )
            ]
        ),
        .write(docId: "peso-muerto__3__alt"),
        "Una ruta ocupada por otra serie no se pisa: se usa un id propio"
    )

    // Y ese id propio es ESTABLE: reintentar la misma serie no acumula
    // documentos, que es la propiedad por la que el id deterministico existe.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 3,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__3",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                )
            ]
        ),
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 3,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__3",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                )
            ]
        ),
        "El id alternativo es estable entre llamadas"
    )

    // Y si ese id alternativo ya contiene la serie, se adopta en vez de escribir.
    checkEqual(
        resolveSetLogWriteTarget(
            exerciseId: "peso-muerto",
            setNumber: 3,
            remote: [
                RemoteSetLogRef(
                    docId: "peso-muerto__3",
                    exerciseId: "peso-muerto",
                    setNumber: 2
                ),
                RemoteSetLogRef(
                    docId: "peso-muerto__3__alt",
                    exerciseId: "peso-muerto",
                    setNumber: 3
                ),
            ]
        ),
        .alreadyThere(docId: "peso-muerto__3__alt"),
        "La identidad logica manda sobre la ruta, tambien para el id alternativo"
    )
}

// MARK: - Lo que el telefono borra tiene que desaparecer del reloj
//
// Reportado por el dueño: "si elimino o sumo una serie desde el celu, cosa que
// no se puede hacer desde el reloj, esos cambios no se modifican en la vista del
// reloj".
//
// La sincronizacion solo AGREGABA, con este motivo escrito: "nunca se borra una
// serie local, una serie cargada en el reloj y todavia sin subir no debe
// desaparecer porque el remoto aun no la tiene". El motivo es correcto y sigue
// valiendo — lo que estaba mal era aplicarlo TAMBIEN a las que ya se subieron.

private func runSetLogDeletion() {
    let remoto = [
        RemoteSetLogRef(docId: "peso-muerto__1", exerciseId: "peso-muerto", setNumber: 1),
        RemoteSetLogRef(docId: "peso-muerto__2", exerciseId: "peso-muerto", setNumber: 2),
    ]

    // Sincronizada y ya no esta en el historial: la borro el telefono.
    check(
        setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: 3, synced: true, remote: remoto
        ),
        "Una serie subida que ya no esta en el historial la borro el telefono"
    )

    // Sincronizada y presente: se queda.
    check(
        !setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: 2, synced: true, remote: remoto
        ),
        "Una serie que sigue en el historial no se toca"
    )

    // PENDIENTE y ausente del historial: NO se saca. Es la cola de subida, y
    // perder una serie que el atleta hizo es peor que mostrarla de mas.
    check(
        !setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: 9, synced: false, remote: remoto
        ),
        "Una serie del reloj todavia sin subir NUNCA se saca"
    )

    // La misma serie de OTRO ejercicio no la sostiene.
    check(
        setLogWasDeletedRemotely(
            exerciseId: "remo-barra", setNumber: 1, synced: true, remote: remoto
        ),
        "La serie 1 de otro ejercicio no cuenta como presente"
    )

    // Historial vacio: todo lo sincronizado se fue, lo pendiente se queda.
    check(
        setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: 1, synced: true, remote: []
        ),
        "Con el historial vacio, lo que estaba subido se saca"
    )
    check(
        !setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: 1, synced: false, remote: []
        ),
        "Con el historial vacio, lo pendiente sigue"
    )

    // Despues de que el telefono borre la serie 2 y RENUMERE la 3 a 2, el
    // historial queda {1,2} y el reloj tenia {1,2,3}: sobra exactamente una.
    let localDespues = [1, 2, 3].map {
        setLogWasDeletedRemotely(
            exerciseId: "peso-muerto", setNumber: $0, synced: true, remote: remoto
        )
    }
    checkEqual(
        localDespues, [false, false, true],
        "Tras borrar+renumerar en el telefono, al reloj le sobra una sola serie"
    )
}

// MARK: - Donde queda parado el cursor de ejercicio
//
// El cursor se movia con `currentExerciseIndex += 1`: un DELTA. Avanzaba un solo
// paso aunque en un mismo sync entraran tres ejercicios enteros cargados desde
// el telefono, y la muñeca quedaba clavada en un ejercicio ya terminado — sin
// fila tocable y sin boton de Terminar.
//
// Cuarta vez que muerde la misma trampa (§4.5 del HANDOFF): aplicar un delta
// sobre un estado que movio otro actor.

private func runExerciseCursor() {
    // Nada cargado: el primero.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [0, 0, 0]),
        0,
        "Sin nada cargado el cursor esta en el primer ejercicio"
    )

    // El primero completo: el segundo.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [4, 0, 0]),
        1,
        "Con el primero completo el cursor pasa al segundo"
    )

    // EL CASO DEL BUG: el telefono completo DOS ejercicios de una mientras el
    // reloj no miraba. Con el delta el cursor avanzaba a 1 y quedaba clavado en
    // un ejercicio ya terminado.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [4, 3, 0]),
        2,
        "Dos ejercicios completados de una: el cursor salta los DOS"
    )

    // Tres de una, con el entreno entero hecho: se queda en el ultimo para que
    // el atleta vea que termino, no en una pantalla vacia.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [4, 3, 3]),
        2,
        "Con todo completo el cursor se queda en el ultimo"
    )

    // RETROCEDE: el telefono borro una serie del primero, que dejo de estar
    // completo. Con un delta esto era imposible de expresar.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [3, 3, 3]),
        0,
        "Si el telefono borro una serie del primero, el cursor VUELVE ahi"
    )

    // Mas cargadas que planificadas (series agregadas desde el telefono mas alla
    // del plan): cuenta como completo, no rompe.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3], seriesCargadas: [5, 1]),
        1,
        "Series de mas no traban el cursor"
    )

    // Lista vacia: 0, nunca negativo. Un indice negativo se usa para indexar.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [], seriesCargadas: []),
        0,
        "Sin ejercicios el cursor es 0, jamas negativo"
    )

    // Menos entradas de cargadas que de planificadas: se asume 0, sin reventar.
    checkEqual(
        firstUnfinishedExerciseIndex(seriesPlanificadas: [4, 3, 3], seriesCargadas: [4]),
        1,
        "Una lista de cargadas mas corta no rompe"
    )
}

// MARK: - Sesiones colgadas: que adoptar y que cerrar (HANDOFF §8.1)
//
// El barrido lo disparaba SOLO el telefono. El reloj adoptaba cualquier sesion
// sin `finishedAt`, sin mirar la fecha: un atleta que usara solo la muñeca
// podia caer en un entreno de hace dias creyendo que era el de hoy.
//
// Esto es caro de reproducir corriendo —hay que fabricar historial viejo— y
// barato de medir acá.

private func runStaleSessions() {
    let ahora = Date(timeIntervalSince1970: 1_760_000_000)
    func haceHoras(_ h: Double) -> Date { ahora.addingTimeInterval(-h * 3600) }
    func candidata(_ id: String, _ cuandoEmpezo: Date) -> StaleSessionRules.Candidata {
        StaleSessionRules.Candidata(id: id, startedAt: cuandoEmpezo)
    }

    // El techo es DERIVADO del del telefono, no una copia. Si alguien mueve uno,
    // este chequeo cae con el otro en vez de dejarlos discrepar en silencio.
    checkEqual(
        StaleSessionRules.maxAntiguedad,
        TimeInterval(WorkoutDurationRules.maxMinutos * 60),
        "El corte de antiguedad sale del mismo techo que la duracion"
    )
    checkEqual(StaleSessionRules.maxAntiguedad, 8 * 3600, "El corte son 8 horas")

    // Sin nada abierto no hay nada que hacer.
    checkEqual(
        StaleSessionRules.decidir(candidatas: [], ahora: ahora),
        StaleSessionRules.Decision(adoptar: nil, aCerrar: []),
        "Sin sesiones abiertas no se adopta ni se cierra nada"
    )

    // El caso normal: el atleta esta entrenando ahora.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [candidata("viva", haceHoras(0.5))], ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: "viva", aCerrar: []),
        "Una sesion de hace media hora se adopta y no se cierra"
    )

    // ⚠️ EL BUG. Una sola sesion, de hace tres dias. Antes se adoptaba: el reloj
    // abria la pantalla de entreno sobre un entreno de otro dia. Sin el corte
    // por antiguedad este chequeo se pone rojo.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [candidata("de-hace-tres-dias", haceHoras(72))],
            ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: nil, aCerrar: ["de-hace-tres-dias"]),
        "Una sesion de hace tres dias NO se adopta: se cierra"
    )

    // El borde, exacto. `>` estricto, igual que el telefono: a las 8h clavadas
    // todavia esta viva.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [candidata("justo", haceHoras(8))], ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: "justo", aCerrar: []),
        "A las 8h clavadas la sesion sigue viva"
    )
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [candidata("pasada", ahora.addingTimeInterval(-8 * 3600 - 60))],
            ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: nil, aCerrar: ["pasada"]),
        "Un minuto despues de las 8h ya vencio"
    )

    // Varias abiertas y la mas nueva viva: esa es la que el atleta esta
    // haciendo, las otras se barren. Barrer solo las repetidas y dejar viva una
    // de ayer era el agujero del telefono; acá no se repite.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [
                candidata("anteayer", haceHoras(50)),
                candidata("ahora", haceHoras(0.2)),
                candidata("ayer", haceHoras(26)),
            ],
            ahora: ahora
        ),
        StaleSessionRules.Decision(
            adoptar: "ahora", aCerrar: ["ayer", "anteayer"]
        ),
        "Con la mas nueva viva se adopta esa y se cierran las demas"
    )

    // Todas vencidas: no se adopta ninguna y se barren TODAS, incluida la mas
    // nueva. Es lo que hace `getActive` cuando la primera ya vencio.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [
                candidata("vieja", haceHoras(30)),
                candidata("menos-vieja", haceHoras(9)),
            ],
            ahora: ahora
        ),
        StaleSessionRules.Decision(
            adoptar: nil, aCerrar: ["menos-vieja", "vieja"]
        ),
        "Si vencio la mas nueva, vencieron todas"
    )

    // La decision NO depende del orden de entrada. La query ordena, pero una
    // regla que se apoya en eso se rompe muda el dia que alguien la toca.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [
                candidata("b", haceHoras(1)),
                candidata("a", haceHoras(0.1)),
                candidata("c", haceHoras(2)),
            ],
            ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: "a", aCerrar: ["b", "c"]),
        "El orden de entrada no cambia la decision"
    )

    // Reloj desfasado: una fecha en el FUTURO no vence. Cerrarla le sacaria al
    // atleta el entreno que esta haciendo.
    checkEqual(
        StaleSessionRules.decidir(
            candidatas: [candidata("futuro", ahora.addingTimeInterval(600))],
            ahora: ahora
        ),
        StaleSessionRules.Decision(adoptar: "futuro", aCerrar: []),
        "Una sesion con fecha futura no se da por vencida"
    )
}

// MARK: - Cerrar el entreno puede fallar, y hay que DECIRLO (HANDOFF §8.3)
//
// Abandonar sin conectividad era un no-op silencioso: el dialogo se cerraba y
// la sesion seguia abierta. El motivo es lo unico que el atleta necesita para
// entender que paso y volver a intentar.

private func runCloseFeedback() {
    // Singular y plural. Un "1 series" en la muñeca se lee como un bug.
    checkEqual(
        WorkoutCloseFailure.seriesSinSubir(1).mensaje,
        "Falta subir 1 serie. El entreno sigue abierto.",
        "Con una sola serie pendiente el mensaje va en singular"
    )
    checkEqual(
        WorkoutCloseFailure.seriesSinSubir(3).mensaje,
        "Falta subir 3 series. El entreno sigue abierto.",
        "Con varias series pendientes el mensaje va en plural"
    )

    // Las dos causas piden lo mismo del atleta —reintentar— pero NO dicen lo
    // mismo. Colapsarlas esconde justo la que hay que diagnosticar.
    check(
        WorkoutCloseFailure.seriesSinSubir(2).mensaje
            != WorkoutCloseFailure.historialNoRespondio.mensaje,
        "Las dos causas de fallo no pueden decir lo mismo"
    )

    // El contrato con el atleta, el mismo que el dialogo de confirmacion: lo
    // hecho NO se pierde. Si el mensaje no lo dice, el cartel naranja se lee
    // como "perdiste el entreno".
    check(
        WorkoutCloseFailure.historialNoRespondio.mensaje.contains("guardado"),
        "El fallo del historial tiene que decir que lo hecho esta guardado"
    )
    check(
        WorkoutCloseFailure.seriesSinSubir(2).mensaje.contains("sigue abierto"),
        "El fallo por pendientes tiene que decir que el entreno sigue abierto"
    )
}
