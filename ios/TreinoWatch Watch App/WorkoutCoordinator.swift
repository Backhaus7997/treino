//
//  WorkoutCoordinator.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F3.
//

import Combine
import Foundation
import os

/// Maneja la sesión de entrenamiento en curso desde el reloj.
///
/// F3 es LOCAL: nada se escribe al historial todavía. La sincronización —y con
/// ella el problema difícil de no duplicar si el teléfono también abrió una
/// sesión— es F4.
@MainActor
final class WorkoutCoordinator: ObservableObject {

    @Published private(set) var session: WorkoutSession?

    /// El entreno que se está haciendo, con sus ejercicios ya resueltos.
    ///
    /// Se guarda acá y no se pasa por parámetro en cada llamada porque puede NO
    /// ser el entreno de la rutina activa: si el atleta arrancó una plantilla
    /// sin activarla, quien llame no tiene forma de saber cuál era. Pasarlo por
    /// parámetro hacía que un `sync` recibiera el entreno equivocado.
    @Published private(set) var workout: TodaysWorkout?

    @Published var currentExerciseIndex: Int = 0

    var exercises: [WatchExercise] { workout?.exercises ?? [] }

    /// Segundos que faltan del descanso, o nil si no hay descanso corriendo.
    @Published private(set) var restRemaining: Int?

    /// Ultima falla de sincronizacion, para diagnostico. La UI solo muestra que
    /// hay pendientes, no el detalle.
    @Published private(set) var syncError: String?

    private var restTimer: Timer?

    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "workout"
    )

    /// El permiso de Salud. Se pide al entrar en modo entreno y nunca
    /// condiciona nada de lo que pasa despues (D2).
    ///
    /// Privado a proposito: en F0 nadie de afuera necesita mirarlo. Cuando F2
    /// tenga que mostrar las pulsaciones en pantalla, que lo abra quien lo
    /// necesite y por la razon concreta.
    private let healthStore = HealthStore()

    /// La sesion de entrenamiento de watchOS. La inyecta la app, igual que el
    /// cliente de Firestore, para que este coordinator no importe HealthKit y
    /// siga compilando —y testeandose— en el host.
    ///
    /// Opcional a proposito: si nadie la inyecta, el entreno funciona igual.
    /// Es la misma regla de D2 aplicada a F1.
    var workoutSession: WorkoutSessionControlling?

    /// Como conseguir un cliente de Firestore autenticado. Lo inyecta la app
    /// para no acoplar este coordinator al de credenciales.
    var makeClient: (() async throws -> (FirestoreREST, String))?

    /// Cómo resolver el entreno de una rutina en una POSICIÓN dada del plan.
    ///
    /// Toma día y semana explícitos —no los calcula— porque se usa sobre
    /// sesiones que YA existen: la posición la manda el historial, no lo que
    /// tocaría hoy. Resolverla de nuevo hacía que el reloj mostrara los
    /// ejercicios de otro día que el que decía la sesión.
    var makeWorkout: ((String, Int, Int) async throws -> TodaysWorkout?)?

    var currentExercise: WatchExercise? {
        guard currentExerciseIndex >= 0, currentExerciseIndex < exercises.count
        else { return nil }
        return exercises[currentExerciseIndex]
    }

    /// Recupera una sesión que haya quedado a medias.
    ///
    /// Los ejercicios NO se persisten: se re-resuelven desde la rutina. Guardar
    /// la prescripción entera dejaría al reloj mostrando series viejas si el PF
    /// la cambia a mitad de plan.
    ///
    /// Se re-resuelve LA RUTINA DE LA SESIÓN, no la activa: si el atleta arrancó
    /// una plantilla sin activarla, compararla contra la activa daba distinto y
    /// el entreno se descartaba entero al reabrir la app.
    /// Adopta un entreno que YA está abierto en el historial, aunque no lo haya
    /// empezado el reloj.
    ///
    /// Es lo que hace que el reloj sea un complemento de verdad: si el atleta
    /// arrancó desde el teléfono, la muñeca se pone en modo entreno sola en vez
    /// de mostrarle "Empezar" para algo que ya empezó.
    ///
    /// No pisa un entreno local en curso: si el reloj ya tiene el suyo, manda
    /// ese. La reconciliación de los dos la hace `sync`, que adopta la sesión
    /// remota del mismo día en vez de crear otra.
    func adoptRemoteSessionIfAny() async {
        guard session == nil, let makeClient, let makeWorkout else { return }
        do {
            let (client, uid) = try await makeClient()
            guard let remote = try await HistorySync.findAnyActiveSession(
                client: client, uid: uid
            ) else { return }

            // Los ejercicios salen de LA RUTINA Y LA POSICIÓN DE ESA SESIÓN.
            // La rutina puede no ser la activa (el atleta arrancó una plantilla
            // desde el teléfono), y el día NO se recalcula: lo manda el
            // historial. Recalcularlo mostraba los ejercicios de un día
            // distinto al que decía la sesión.
            guard let workout = try await makeWorkout(
                remote.routineId, remote.dayNumber, remote.weekNumber
            ) else { return }

            let logged = try await HistorySync.remoteSetLogs(
                client: client, uid: uid, sessionId: remote.id
            )

            var adopted = WorkoutSession(
                localId: UUID().uuidString,
                routineId: remote.routineId,
                routineName: remote.routineName,
                dayName: workout.dayName,
                dayNumber: remote.dayNumber,
                weekNumber: remote.weekNumber,
                startedAt: remote.startedAt,
                loggedSets: logged
            )
            adopted.remoteId = remote.id

            session = adopted
            self.workout = workout
            currentExerciseIndex = firstUnfinishedIndex(
                in: workout.exercises, session: adopted
            )
            WorkoutSessionStore.save(adopted)
            syncError = nil
            requestHealthAccess()
            beginWorkoutSession()
        } catch {
            syncError = String(describing: error)
        }
    }

    func restore() async {
        // Sin nada guardado localmente, puede haber un entreno abierto que
        // empezó el teléfono. Antes se volvía sin mirar, y el reloj mostraba
        // "Empezar" mientras el atleta ya estaba entrenando.
        guard WorkoutSessionStore.load() != nil else {
            await adoptRemoteSessionIfAny()
            return
        }
        guard let stored = WorkoutSessionStore.load(), let makeWorkout else { return }

        let resolved: TodaysWorkout?
        do {
            // La posición la manda LA SESIÓN GUARDADA, no lo que tocaría hoy.
            // Antes se recalculaba y después se comparaba: si el plan había
            // avanzado, el entreno a medias se descartaba entero — y si no, se
            // corría el riesgo de mostrar los ejercicios de otro día.
            resolved = try await makeWorkout(
                stored.routineId, stored.dayNumber, stored.weekNumber
            )
        } catch {
            // Sin red no se puede re-resolver. NO se descarta: la sesión queda
            // en disco y se reintenta al próximo arranque. Borrarla acá sería
            // perder un entreno hecho por un problema de conectividad.
            syncError = String(describing: error)
            return
        }

        // Sin rutina (la borraron) no hay nada que mostrar.
        guard let workout = resolved else {
            WorkoutSessionStore.clear()
            return
        }

        session = stored
        self.workout = workout
        currentExerciseIndex = firstUnfinishedIndex(in: workout.exercises, session: stored)
        requestHealthAccess()
        beginWorkoutSession()
    }

    /// Le pide permiso a Salud cuando el reloj entra en modo entreno.
    ///
    /// Se llama desde los TRES caminos que abren un entreno —empezarlo acá,
    /// adoptar el que abrio el telefono, y recuperar uno a medias— y no solo
    /// desde `start`. Un companion pasa la mayor parte del tiempo adoptando lo
    /// que arranco el celular: dejar el pedido solo en `start` era no
    /// preguntarle nunca justo al caso mas comun.
    ///
    /// Va suelto y no lanza. El entreno ya empezo y no depende de esto (D2).
    private func requestHealthAccess() {
        Task { await healthStore.requestAccessIfNeeded() }
    }

    /// Le declara a watchOS que esto es un entrenamiento.
    ///
    /// Va junto al pedido de permiso y por los mismos tres caminos, pero NO
    /// depende de el: en F0 se midio que la sesion abre incluso con el permiso
    /// negado por completo, y que asi el atleta conserva la ejecucion en
    /// segundo plano. Sin permiso pierde el ritmo cardiaco, no el descanso.
    ///
    /// Abrir dos veces es un NO-OP; la garantia vive en el controller.
    private func beginWorkoutSession() {
        workoutSession?.begin()
    }

    /// Cierra la sesion cuando el entreno termina, venga de donde venga el
    /// cierre: lo termino el atleta acá, o lo cerro el telefono.
    ///
    /// Dejarla abierta seria peor que no haberla abierto: watchOS mantendria la
    /// app viva y el reloj gastando bateria por un entreno que ya no existe.
    private func endWorkoutSession() {
        workoutSession?.end()
    }

    func start(workout: TodaysWorkout) {
        let new = WorkoutSession(
            localId: UUID().uuidString,
            routineId: workout.routineId,
            routineName: workout.routineName,
            dayName: workout.dayName,
            dayNumber: workout.dayNumber,
            weekNumber: workout.weekNumber,
            startedAt: Date(),
            loggedSets: []
        )
        session = new
        self.workout = workout
        currentExerciseIndex = 0
        WorkoutSessionStore.save(new)

        // Se adopta o crea la sesion remota en segundo plano: el atleta empieza
        // a entrenar YA, sin esperar a la red. Si falla, el proximo sync lo
        // reintenta.
        Task { await sync() }

        requestHealthAccess()
        beginWorkoutSession()
    }

    /// Carga una serie. Idempotente por `exerciseId + setNumber`, igual que el
    /// teléfono: tocar dos veces la misma no la duplica.
    func logSet(exerciseId: String, setNumber: Int, spec: SetSpec, restSeconds: Int) {
        guard var current = session else { return }
        guard !current.isLogged(exerciseId: exerciseId, setNumber: setNumber) else { return }

        current.loggedSets.append(
            LoggedSet(
                exerciseId: exerciseId,
                setNumber: setNumber,
                // Con un rango se registra el máximo: es el objetivo del plan.
                // El atleta podrá corregirlo cuando exista la edición (F4).
                reps: spec.reps ?? spec.repsMax ?? spec.repsMin,
                weightKg: spec.weightKg,
                completedAt: Date()
            )
        )
        session = current
        WorkoutSessionStore.save(current)

        startRest(seconds: restSeconds)
        advanceIfExerciseDone(exerciseId: exerciseId)

        Task { await sync() }
    }

    /// Cierra el entreno. Intenta subir lo que falte ANTES de descartar el
    /// estado local: si se borrara primero, una serie que nunca llego al
    /// historial se perderia sin dejar rastro.
    func finish() async {
        stopRest()
        await sync()

        // Si quedan pendientes, el entreno NO se descarta: se conserva para
        // reintentar. Perder series que el atleta hizo es peor que dejarle la
        // pantalla abierta.
        if let current = session, !current.pendingSets.isEmpty { return }

        // Marca la sesion FINALIZADA en el historial. Sin esto el reloj borraba
        // su estado local pero la sesion quedaba `active` en Firestore, y la app
        // del telefono la seguia ofreciendo para retomar.
        //
        // Si esto falla, el entreno NO se descarta: quedaria una sesion
        // colgada como activa y el atleta sin forma de cerrarla.
        if let current = session, let remoteId = current.remoteId,
           let makeClient {
            do {
                let (client, uid) = try await makeClient()
                try await HistorySync.finishSession(
                    client: client, uid: uid, sessionId: remoteId,
                    finishedAt: Date(),
                    totalVolumeKg: totalVolume(of: current),
                    durationMin: durationMinutes(since: current.startedAt),
                    wasFullyCompleted: isFullyCompleted(current)
                )
            } catch {
                syncError = String(describing: error)
                return
            }
        }

        session = nil
        workout = nil
        currentExerciseIndex = 0
        WorkoutSessionStore.clear()
        endWorkoutSession()
    }

    /// Reconcilia el entreno del reloj con el historial. El ORDEN es parte del
    /// contrato, no un detalle de implementacion:
    ///
    /// 1. ¿La cerraron desde el telefono? Entonces no hay nada que escribir.
    /// 2. Resolver la sesion remota (adoptarla o crearla).
    /// 3. **LEER** las series que ya estan en el historial.
    /// 4. **DESPUES** subir las pendientes, sabiendo que hay alla.
    ///
    /// Los pasos 3 y 4 estaban al reves, y eso dejaba DOS documentos de la misma
    /// serie cuando el telefono la habia cargado antes: el reloj escribia con su
    /// id deterministico contra un documento de id autogenerado, asi que no habia
    /// nada que pisar. Leer primero no cuesta un viaje de red extra — esa lectura
    /// ya se hacia, solo llegaba tarde.
    ///
    /// Cada serie se marca como subida SOLO si su escritura salio bien, asi que
    /// una falla parcial deja el resto en la cola en vez de darlas por hechas.
    func sync() async {
        guard var current = session, let makeClient else { return }
        do {
            let (client, uid) = try await makeClient()

            // ¿Lo terminaron desde el teléfono? Entonces el reloj se cierra
            // solo. Sin esto quedaba con la pantalla de entreno abierta sobre
            // una sesión que ya no existe, y cualquier serie que se marcara ahí
            // se escribía sobre un entreno cerrado.
            //
            // Va ANTES de subir lo pendiente a propósito: no tiene sentido
            // escribir series nuevas en algo que ya se cerró.
            if let remoteId = current.remoteId,
               try await HistorySync.isFinished(
                   client: client, uid: uid, sessionId: remoteId
               ) {
                stopRest()
                session = nil
                workout = nil
                currentExerciseIndex = 0
                WorkoutSessionStore.clear()
                endWorkoutSession()
                syncError = nil
                return
            }

            if current.remoteId == nil {
                guard let workout else {
                    // Sin la rutina no se puede adoptar/crear: queda para el
                    // proximo sync, que si la tiene.
                    return
                }
                let adopted = try await HistorySync.adoptOrCreateSession(
                    client: client, uid: uid, workout: workout,
                    startedAt: current.startedAt
                )
                current.remoteId = adopted.sessionId
                // Series que ya estaban en esa sesion (cargadas desde el
                // telefono, o por un intento anterior): se marcan como hechas
                // para no volver a ofrecerlas ni re-escribirlas.
                for existing in adopted.alreadyLogged
                where !current.isLogged(
                    exerciseId: existing.exerciseId, setNumber: existing.setNumber
                ) {
                    current.loggedSets.append(existing)
                }
                session = current
                WorkoutSessionStore.save(current)
            }

            guard let remoteId = current.remoteId else { return }

            // ── Se LEE el historial antes de ESCRIBIR ──────────────────────
            //
            // El orden era el otro: primero se subia lo pendiente y despues se
            // leia. Asi, la serie que el atleta acababa de marcar en la muñeca
            // se escribia SIN saber que el telefono ya la habia cargado — y
            // como los ids de los dos clientes no coinciden, no habia nada que
            // pisar: quedaban DOS documentos de la misma serie. Medido contra el
            // emulador el 2026-08-11: 5 de 7 sesiones con duplicados, en las dos
            // direcciones.
            //
            // Leer primero NO cuesta un viaje de red extra. Esta lectura ya
            // existia; lo unico que estaba mal era que llegaba tarde.
            //
            // Trae ademas lo que se haya cargado desde el TELEFONO, que es la
            // otra direccion de la sincronizacion: sin esto el reloj solo ve lo
            // suyo y le vuelve a ofrecer series que el atleta ya marco en el
            // celular.
            //
            // Solo se AGREGA lo que falta; nunca se borra una serie local. Una
            // serie cargada en el reloj y todavia sin subir no debe desaparecer
            // porque el remoto aun no la tiene.
            let remote = try await HistorySync.remoteSetLogs(
                client: client, uid: uid, sessionId: remoteId
            )

            // Las series que el reloj NO tenia: sirven para saber si hay que
            // arrancar el descanso, no solo para contar.
            var nuevas: [LoggedSet] = []
            for set in remote where !current.isLogged(
                exerciseId: set.exerciseId, setNumber: set.setNumber
            ) {
                current.loggedSets.append(set)
                nuevas.append(set)
            }
            if !nuevas.isEmpty {
                session = current
                WorkoutSessionStore.save(current)

                // El descanso arranca TAMBIEN cuando la serie se marco en el
                // telefono. Antes solo lo disparaba `logSet`, o sea marcar en la
                // muñeca: el atleta marcaba en el celular y el reloj —que es
                // donde mira el descanso— se quedaba mudo.
                //
                // Solo si la serie nueva es del ejercicio EN CURSO: una que
                // llega de un ejercicio ya pasado (una correccion tardia) no
                // tiene por que poner a contar nada.
                if let exercise = currentExercise,
                   restRemaining == nil,
                   nuevas.contains(where: { $0.exerciseId == exercise.exerciseId }) {
                    startRest(seconds: exercise.restSeconds)
                }

                // Si el telefono completo el ejercicio actual, avanzar.
                if let exercise = currentExercise,
                   current.loggedCount(exerciseId: exercise.exerciseId)
                       >= exercise.sets.count,
                   currentExerciseIndex + 1 < exercises.count {
                    currentExerciseIndex += 1
                }
            }

            // ── Ahora si, subir lo pendiente, sabiendo que hay alla ────────
            //
            // La identidad del documento se resuelve por identidad LOGICA de la
            // serie contra el historial recien leido, no derivandola del
            // `exerciseId__setNumber` a ciegas. `resolveSetLogWriteTarget` es
            // pura y esta medida en el host: la decision de donde escribir es
            // justo lo incomodo de verificar corriendo el reloj.
            let remoteRefs = remote.compactMap { set -> RemoteSetLogRef? in
                guard let docId = set.remoteDocId else { return nil }
                return RemoteSetLogRef(
                    docId: docId,
                    exerciseId: set.exerciseId,
                    setNumber: set.setNumber
                )
            }

            for pending in current.pendingSets {
                let target = resolveSetLogWriteTarget(
                    exerciseId: pending.exerciseId,
                    setNumber: pending.setNumber,
                    remote: remoteRefs
                )
                let docId: String
                switch target {
                case .alreadyThere(let existing):
                    // El historial YA tiene esta serie. No se escribe: el dato
                    // esta, y pisarlo solo podria tapar una correccion de
                    // reps/peso que el atleta hizo en el celular, que es la
                    // unica superficie con edicion.
                    docId = existing
                case .write(let target):
                    docId = target
                    let name = exercises
                        .first { $0.exerciseId == pending.exerciseId }?
                        .exerciseName ?? pending.exerciseId
                    try await HistorySync.writeSetLog(
                        client: client, uid: uid, sessionId: remoteId,
                        docId: docId, exerciseName: name, set: pending
                    )
                }
                if let index = current.loggedSets.firstIndex(where: {
                    $0.exerciseId == pending.exerciseId
                        && $0.setNumber == pending.setNumber
                }) {
                    current.loggedSets[index].synced = true
                    // Se guarda el id REAL del documento: si un sync posterior
                    // tiene que volver sobre esta serie, va al documento que
                    // existe en vez de crear uno paralelo.
                    current.loggedSets[index].remoteDocId = docId
                }
                // Se persiste por serie y no al final: una falla a mitad deja
                // subido lo que entro en vez de reintentarlo todo.
                session = current
                WorkoutSessionStore.save(current)
            }

            syncError = nil
        } catch {
            syncError = String(describing: error)
        }
    }

    func skipRest() { stopRest() }

    // MARK: - Metricas del entreno

    /// Volumen total: suma de reps x kilos de cada serie cargada.
    ///
    /// Una serie sin peso (peso corporal, o un plan sin kilos cargados) suma
    /// cero. No se inventa un peso: mentir el volumen es peor que subestimarlo.
    func totalVolume(of session: WorkoutSession) -> Double {
        session.loggedSets.reduce(0) { total, set in
            total + Double(set.reps ?? 0) * (set.weightKg ?? 0)
        }
    }

    /// Duracion en minutos.
    ///
    /// D4, firmada: la sesion de entrenamiento es la fuente de verdad cuando
    /// existe, y el calculo de reloj de pared queda como respaldo. Antes esto
    /// SIEMPRE estimaba restando timestamps; ahora estima solo cuando no hay
    /// nada que medir —permiso negado, Salud caida, dispositivo sin Salud—.
    ///
    /// La regla vive en `WorkoutDurationRules`, sin HealthKit, para poder
    /// testearla en el host.
    func durationMinutes(since start: Date) -> Int {
        let resultado = WorkoutDurationRules.minutes(
            measuredSeconds: workoutSession?.measuredElapsedSeconds,
            startedAt: start,
            now: Date()
        )
        // Se loguea DE DONDE salio y no solo el numero: cuando medicion y
        // reloj de pared coinciden —que es lo normal— el resultado solo no
        // distingue si la medicion se uso o si se cayo al respaldo en silencio.
        // Sin esto, D4 es inverificable corriendo.
        log.notice(
            "Duracion \(resultado.minutes) min, origen \(String(describing: resultado.source))"
        )
        return resultado.minutes
    }

    /// Si se cargaron TODAS las series de TODOS los ejercicios.
    func isFullyCompleted(_ session: WorkoutSession) -> Bool {
        guard !exercises.isEmpty else { return false }
        return exercises.allSatisfy {
            session.loggedCount(exerciseId: $0.exerciseId) >= $0.sets.count
        }
    }

    // MARK: - Internos

    /// Avanza al siguiente ejercicio cuando el actual quedó completo.
    ///
    /// No avanza más allá del último: quedarse ahí deja al atleta ver que
    /// terminó, en vez de mostrarle una pantalla vacía.
    private func advanceIfExerciseDone(exerciseId: String) {
        guard let session, let exercise = currentExercise,
              exercise.exerciseId == exerciseId,
              session.loggedCount(exerciseId: exerciseId) >= exercise.sets.count,
              currentExerciseIndex + 1 < exercises.count
        else { return }
        currentExerciseIndex += 1
    }

    private func firstUnfinishedIndex(
        in exercises: [WatchExercise],
        session: WorkoutSession
    ) -> Int {
        for (index, exercise) in exercises.enumerated() {
            if session.loggedCount(exerciseId: exercise.exerciseId) < exercise.sets.count {
                return index
            }
        }
        return max(exercises.count - 1, 0)
    }

    /// Descanso contado LOCALMENTE por el reloj.
    ///
    /// El plan original lo descartaba porque mandar un tick por segundo desde
    /// el teléfono saturaba el canal. Acá no aplica: el reloj es autónomo y
    /// tiene el estado, así que contar no cuesta tráfico (Locked Decision #8).
    private func startRest(seconds: Int) {
        stopRest()
        guard seconds > 0 else { return }
        restRemaining = seconds
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let remaining = self.restRemaining else { return }
                if remaining <= 1 {
                    self.stopRest()
                } else {
                    self.restRemaining = remaining - 1
                }
            }
        }
    }

    private func stopRest() {
        restTimer?.invalidate()
        restTimer = nil
        restRemaining = nil
    }
}
