//
//  CredentialCoordinator.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Combine
import Foundation
import WatchConnectivity
import os

/// Estado de credencial del reloj, para que la UI sepa qué mostrar.
enum WatchAuthState: Equatable {
    /// Todavía no llegó nada del teléfono y no hay nada guardado.
    case waitingForPairing
    /// Canjeando el token que mandó el teléfono.
    case exchanging
    /// El reloj tiene credencial propia y puede operar solo.
    case ready(uid: String)
    /// El atleta CERRO SESION en el telefono.
    ///
    /// Es un estado propio y no un `waitingForPairing` a proposito: ese dice
    /// "abri TREINO en el telefono para vincular el reloj", que para alguien
    /// que acaba de desloguearse le echa la culpa al emparejamiento. El reloj
    /// esta perfectamente vinculado; lo que falta es una sesion.
    case signedOut
    /// Algo falló. `message` es para diagnóstico, no para mostrarle al usuario.
    case failed(message: String)
}

/// Recibe la credencial del teléfono, la canjea por una propia y la persiste.
///
/// A partir del canje el reloj NO necesita más al teléfono: renueva su idToken
/// contra `securetoken.googleapis.com` con el refresh token del Keychain.
///
/// Es `@MainActor` porque publica estado a SwiftUI. Los callbacks de
/// `WCSessionDelegate` llegan en una cola de fondo, así que saltan al main
/// actor explícitamente — sin eso hay carrera con la UI.
@MainActor
final class CredentialCoordinator: NSObject, ObservableObject {

    @Published private(set) var state: WatchAuthState = .waitingForPairing

    /// Entreno de hoy, resuelto por el reloj contra Firestore. Nil mientras se
    /// carga o si el atleta no tiene rutina.
    @Published private(set) var todaysWorkout: TodaysWorkout?

    /// Diagnóstico de la carga del entreno. No se le muestra al usuario.
    @Published private(set) var workoutError: String?

    /// Si la carga del entreno ya TERMINÓ, con o sin resultado.
    ///
    /// Sin esta bandera, "todavía cargando" y "cargó y no hay rutina activa" son
    /// indistinguibles desde la vista: en los dos casos `todaysWorkout` y
    /// `workoutError` están en nil, y la pantalla se quedaba girando para
    /// siempre. Un atleta sin rutina asignada veía un spinner eterno.
    @Published private(set) var workoutLoaded = false

    /// El error de carga TAMBIÉN va a `os_log`, no sólo a `workoutError`.
    ///
    /// `workoutError` vive en memoria y no se muestra: sin esto, el status HTTP
    /// y el body que trae `FirestoreError.http` se descartaban sin dejar rastro
    /// ni en un sysdiagnose. Un índice compuesto faltante —que Firestore
    /// reporta con un 400 y un mensaje explícito— costó una tarde de
    /// diagnóstico a ciegas porque ese texto nunca se escribía a ningún lado.
    private let log = Logger(
        subsystem: "com.backhaus.treino.watchkitapp",
        category: "credential"
    )

    /// Sube cada vez que el TELÉFONO avisa que algo cambió.
    ///
    /// Las listas de planes y plantillas lo miran para releer. El reloj no
    /// tiene listeners de Firestore —no existe en watchOS—, así que este aviso
    /// es la única forma de que un cambio hecho en el celular se vea sin que el
    /// atleta toque nada.
    @Published private(set) var externalRefresh = 0

    /// La ultima orden de cronometro que mando el telefono.
    ///
    /// Lleva numero de secuencia y no viaja sola porque `onChange` compara por
    /// igualdad: dos cancelaciones seguidas son el mismo valor y la segunda no
    /// dispararia nada. Mismo motivo por el que `externalRefresh` es un
    /// contador y no un Bool.
    struct PhoneTimerSignal: Equatable {
        let secuencia: Int
        let command: PhoneTimerMirror.Command
    }

    @Published private(set) var phoneTimerSignal: PhoneTimerSignal?
    private var phoneTimerSecuencia = 0

    /// Arranca la sesión de WatchConnectivity y recupera lo que haya guardado.
    func start() {
        if let stored = CredentialStore.load() {
            // Ya emparejado en un arranque anterior: no hay que esperar al
            // teléfono.
            state = .ready(uid: stored.uid)
            Task { await loadTodaysWorkout() }
        }

        guard WCSession.isSupported() else {
            // Sin WatchConnectivity no hay forma de recibir la credencial
            // inicial. Si ya había una guardada, el reloj sigue funcionando.
            if CredentialStore.load() == nil {
                state = .failed(message: "WatchConnectivity no disponible")
            }
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()

        // El contexto ya recibido persiste del lado del reloj, así que puede
        // estar disponible antes de que llegue un callback nuevo.
        handle(applicationContext: session.receivedApplicationContext)
    }

    /// El idToken cacheado, CON el uid de quien es. Ver `TokenFreshness`.
    ///
    /// El uid no es decorativo: sin el, cambiar de cuenta dejaba al reloj con
    /// el token de A y el uid de B. `freshIdToken()` devolvia el cacheado ANTES
    /// de mirar la credencial, asi que la identidad ni entraba en la decision.
    /// Con ese par, leer `users/B` da 403 garantizado —las reglas son
    /// owner-only— y la pantalla se quedaba con el entreno del atleta anterior.
    ///
    /// Va acá y no como un `idTokenCacheado = nil` en `exchange()` a proposito:
    /// eso arreglaria el camino de hoy y dejaria la trampa puesta para el
    /// proximo que alguien agregue. Un cache que no puede devolver el token de
    /// otro no se puede usar mal.
    private var idTokenCacheado: (token: String, emitidoEn: Date, uid: String)?

    /// Devuelve un idToken para hablar con Firestore, reusando el vigente.
    ///
    /// ANTES renovaba en CADA llamada. Eso ponía un POST completo a
    /// securetoken delante de cada sincronización — o sea, delante de cada
    /// serie marcada. Medido: 4 viajes de red en serie antes de que la serie
    /// existiera en Firestore, y este era el primero de los cuatro. Se reportó
    /// como "tarda mucho en verse en el teléfono".
    ///
    /// El token dura 3600s; se reusa hasta 3000s. La decisión de cuándo
    /// renovar vive en `TokenFreshness`, aparte y pura, porque acá no se puede
    /// medir.
    func freshIdToken() async throws -> String {
        // La credencial se lee PRIMERO. El cache solo sirve si es del mismo
        // atleta: un token no es reusable entre cuentas, es de una sola.
        guard let credential = CredentialStore.load() else {
            throw FirebaseAuthREST.AuthError.malformedResponse
        }

        if let cache = idTokenCacheado,
           TokenFreshness.canReuse(
               cacheDe: cache.uid,
               credencialDe: credential.uid,
               emitidoEn: cache.emitidoEn,
               ahora: Date()
           ) {
            return cache.token
        }
        let token = try await FirebaseAuthREST.refreshIdToken(
            refreshToken: credential.refreshToken,
            apiKey: credential.apiKey,
            host: credential.authEmulatorHost.map { "\($0)/securetoken.googleapis.com" }
                ?? "https://securetoken.googleapis.com"
        )
        idTokenCacheado = (token: token, emitidoEn: Date(), uid: credential.uid)
        return token
    }

    /// Vuelve a mirar el contexto que ya tenga WatchConnectivity.
    ///
    /// Hace falta porque `start()` corre UNA vez por proceso, desde el `.task`
    /// de la escena, y ese no reentra en un resume. El contexto, en cambio, se
    /// entrega "on next launch" segun el SDK: con la app del reloj cerrada, la
    /// credencial nueva espera ahi. Sin esta relectura el atleta tenia que
    /// cerrar y reabrir la app —y el propio arranque tiene una carrera, porque
    /// `activate()` es asincrono y `start()` lee las properties en la linea
    /// siguiente.
    ///
    /// Es idempotente por construccion: `handle()` corta solo si el uid ya
    /// coincide, asi que llamarlo de mas no re-canjea nada.
    func revisarContextoPendiente() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        handle(applicationContext: session.receivedApplicationContext)
    }

    /// Descarta el token cacheado.
    ///
    /// Se llama cuando Firestore contesta 401: el token puede haber muerto
    /// antes de tiempo (credencial revocada, reloj con la hora corrida). Sin
    /// esto, un token invalidado dejaría al reloj rebotando hasta que venza el
    /// TTL.
    func invalidateIdToken() {
        idTokenCacheado = nil
    }

    /// Procesa un contexto entrante. Ignora en silencio lo que no sea un
    /// payload de credencial: por ese canal pueden viajar otras cosas.
    fileprivate func handle(applicationContext: [String: Any]) {
        // El atleta cerro sesion en el telefono. Viaja por el MISMO slot que la
        // credencial, y eso no es casualidad: el contexto de salida es uno solo
        // y se pisa entero, asi que publicar esto BORRA la credencial del canal
        // —que es exactamente la semantica que se quiere— y ademas persiste: se
        // entrega en el proximo lanzamiento del reloj aunque este cerrado.
        if WatchSignedOutPayload.esAviso(applicationContext) {
            cerrarSesion()
            return
        }

        guard let payload = WatchCredentialPayload(applicationContext: applicationContext)
        else { return }

        // Si ya hay credencial de este mismo usuario, no se re-canjea: el
        // teléfono reenvía el contexto en cada arranque y canjear de nuevo
        // invalidaría el refresh token que ya funciona.
        if let existing = CredentialStore.load(), existing.uid == payload.uid {
            state = .ready(uid: existing.uid)
            return
        }

        // CAMBIO DE CUENTA. Todo lo del atleta anterior se va ANTES de canjear.
        //
        // Sin esto el reloj quedaba con el entreno de A en `todaysWorkout` y el
        // uid de B en `state`, y como `ContentView` prefiere el entreno sobre el
        // error, le mostraba a B la rutina de A —dia, nombre del plan, lista
        // completa de ejercicios— como si estuviera bien.
        olvidarAlAtletaAnterior()

        state = .exchanging
        Task { await exchange(payload) }
    }

    /// Borra todo rastro del atleta anterior, menos la credencial.
    ///
    /// La credencial NO se toca acá: en un cambio de cuenta la pisa `exchange()`
    /// con la nueva, y borrarla antes dejaria al reloj sin poder hablar con
    /// Firestore si el canje falla.
    private func olvidarAlAtletaAnterior() {
        idTokenCacheado = nil
        todaysWorkout = nil
        workoutLoaded = false
        workoutError = nil
        phoneTimerSignal = nil

        // El entreno a medias del atleta ANTERIOR tambien se va, y con el sus
        // series sin subir.
        //
        // Se pierden, y es la opcion menos mala: para subirlas hace falta la
        // credencial de A, que en este mismo momento se esta reemplazando por la
        // de B. La alternativa es peor — `sync()` pide el cliente con el uid
        // NUEVO y escribiria las series de A bajo `users/B`. Perder datos de una
        // cuenta es malo; mezclarlos entre cuentas es inaceptable.
        WorkoutSessionStore.clear()
    }

    /// El atleta cerro sesion en el telefono.
    ///
    /// Toca SEIS cosas, no una. Si quedara `todaysWorkout`, la pantalla de
    /// "inicia sesion" conviviria con el entreno del anterior en memoria.
    func cerrarSesion() {
        _ = CredentialStore.delete()
        olvidarAlAtletaAnterior()
        state = .signedOut
        log.notice("Sesion cerrada desde el telefono: credencial borrada")
    }

    private func exchange(_ payload: WatchCredentialPayload) async {
        do {
            // El emulador expone los servicios bajo su propio host con el
            // nombre del servicio real como prefijo de path.
            let exchanged = try await FirebaseAuthREST.exchangeCustomToken(
                payload.customToken,
                apiKey: payload.apiKey,
                host: payload.authEmulatorHost
                    .map { "\($0)/identitytoolkit.googleapis.com" }
                    ?? "https://identitytoolkit.googleapis.com"
            )
            try CredentialStore.save(
                WatchCredential(
                    refreshToken: exchanged.refreshToken,
                    uid: payload.uid,
                    apiKey: payload.apiKey,
                    projectId: payload.projectId,
                    authEmulatorHost: payload.authEmulatorHost,
                    firestoreEmulatorHost: payload.firestoreEmulatorHost
                )
            )
            state = .ready(uid: payload.uid)
            Task { await loadTodaysWorkout() }
        } catch {
            state = .failed(message: String(describing: error))
        }
    }

    /// Un cliente de Firestore autenticado y su uid, con token fresco.
    func firestoreClient() async throws -> (FirestoreREST, String) {
        guard let credential = CredentialStore.load() else {
            throw FirebaseAuthREST.AuthError.malformedResponse
        }
        let idToken = try await freshIdToken()
        let client = FirestoreREST(
            projectId: credential.projectId,
            idToken: idToken,
            emulatorHost: credential.firestoreEmulatorHost
        )
        return (client, credential.uid)
    }

    /// Carga el entreno de hoy con la credencial propia del reloj.
    ///
    /// Renueva el idToken en cada carga: dura una hora, y renovar es más barato
    /// que manejar la expiración a mano y equivocarse.
    func loadTodaysWorkout() async {
        guard let credential = CredentialStore.load() else { return }
        // De QUIEN es esta carga. Se captura al empezar y se vuelve a mirar
        // antes de publicar: entre medio pudo cambiar la cuenta, y una carga
        // vieja que aterriza tarde pisaria el dato bueno del atleta nuevo — y
        // encima le borraria el error, dejando el rastro en nada.
        let deQuien = credential.uid

        do {
            let workout = try await resolverEntreno(credential)
            guard CredentialStore.load()?.uid == deQuien else {
                log.notice("Carga descartada: cambio la cuenta mientras se resolvia")
                return
            }
            todaysWorkout = workout
            workoutError = nil
            workoutLoaded = true
        } catch {
            guard CredentialStore.load()?.uid == deQuien else { return }
            todaysWorkout = nil
            workoutError = String(describing: error)
            workoutLoaded = true
            // `error` es privacy-sensitive por defecto en os_log y saldría como
            // "<private>", que es exactamente el silencio que esto viene a
            // romper. Va explícito: son mensajes de Firestore, no datos del
            // atleta.
            log.error("No se pudo cargar el entreno de hoy: \(String(describing: error), privacy: .public)")
        }
    }

    /// Resuelve el entreno, y si Firestore rechaza por credencial lo reintenta
    /// UNA vez con token nuevo.
    ///
    /// El reintento existe porque un token cacheado puede haber quedado del
    /// atleta anterior o haber muerto antes de tiempo, y sin esto el reloj
    /// rebotaba contra el 403 hasta que venciera el TTL —3000 segundos— o hasta
    /// que alguien matara el proceso. Es la misma cura que ya aplica
    /// `WorkoutCoordinator` ante un 401, que solo corria con un entreno abierto.
    private func resolverEntreno(_ credential: WatchCredential) async throws -> TodaysWorkout? {
        func intentar() async throws -> TodaysWorkout? {
            let idToken = try await freshIdToken()
            let client = FirestoreREST(
                projectId: credential.projectId,
                idToken: idToken,
                emulatorHost: credential.firestoreEmulatorHost
            )
            return try await TodaysWorkoutResolver.resolve(
                client: client,
                uid: credential.uid
            )
        }

        do {
            return try await intentar()
        } catch let error as FirestoreREST.FirestoreError {
            guard case .http(let status, _) = error, status == 401 || status == 403 else {
                throw error
            }
            log.notice("Firestore rechazo por credencial (\(status, privacy: .public)): token nuevo y un reintento")
            invalidateIdToken()
            return try await intentar()
        }
    }
}

// MARK: - WCSessionDelegate

extension CredentialCoordinator: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // Acá SI hay algo que hacer, y antes no se hacía.
        //
        // `start()` llama a `activate()` —asincrono— y lee
        // `receivedApplicationContext` en la LINEA SIGUIENTE: esa lectura puede
        // salir vacia. Este es el primer momento en que las properties de la
        // sesion son validas de verdad.
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.revisarContextoPendiente()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        // Llega en una cola de fondo. Saltar al main actor antes de tocar
        // estado publicado.
        Task { @MainActor in
            self.handle(applicationContext: applicationContext)
        }
    }

    /// Mensaje puntual desde el teléfono.
    ///
    /// Van por MENSAJE y no por contexto de aplicación a propósito — el
    /// contexto es uno solo y se pisa entero, y ahí vive la credencial.
    ///
    /// Se discrimina por `kind` porque el canal es compartido: hoy lo usan el
    /// aviso de "relee" (`watchRefresh`) y el cronómetro espejado del teléfono
    /// (`watchTimer`). Un mensaje sin `kind` conocido se ignora entero.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        if let comando = PhoneTimerMirror.parse(message) {
            Task { @MainActor in
                self.recibir(comandoDeCronometro: comando)
            }
            return
        }

        guard message["kind"] as? String == "watchRefresh" else { return }

        // CAMBIO DE CUENTA: no se relee Firestore, se va a mirar el contexto.
        //
        // Releer usaria la credencial VIGENTE, que si este aviso le gana la
        // carrera al contexto es todavia la del atleta ANTERIOR: seria pedirle
        // a Firestore los datos de A justo cuando el atleta ya es B.
        if message["reason"] as? String == "accountChanged" {
            Task { @MainActor in
                self.revisarContextoPendiente()
            }
            return
        }

        Task { @MainActor in
            self.refreshFromPhone()
        }
    }
}

extension CredentialCoordinator {

    /// Relee todo lo que el teléfono pudo haber cambiado.
    ///
    /// No corre durante un entreno en curso para la parte de la rutina: los
    /// ejercicios NO se cambian abajo del atleta a mitad de serie. La señal
    /// para las listas se emite igual, porque esas no están en pantalla
    /// mientras entrena.
    /// Publica la orden de cronometro para que la tome `WorkoutCoordinator`.
    ///
    /// Este coordinador NO aplica la orden: no conoce el estado del entreno.
    /// Publica la senal y la vista la enruta, igual que con `externalRefresh`.
    fileprivate func recibir(comandoDeCronometro comando: PhoneTimerMirror.Command) {
        phoneTimerSecuencia += 1
        phoneTimerSignal = PhoneTimerSignal(
            secuencia: phoneTimerSecuencia,
            command: comando
        )
    }

    fileprivate func refreshFromPhone() {
        externalRefresh += 1
        Task { await loadTodaysWorkout() }
    }
}
