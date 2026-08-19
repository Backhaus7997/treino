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

    /// El idToken vigente y cuando se emitió. Ver `TokenFreshness`.
    private var idTokenCacheado: (token: String, emitidoEn: Date)?

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
        if let cache = idTokenCacheado,
           !TokenFreshness.shouldRefresh(emitidoEn: cache.emitidoEn, ahora: Date()) {
            return cache.token
        }

        guard let credential = CredentialStore.load() else {
            throw FirebaseAuthREST.AuthError.malformedResponse
        }
        let token = try await FirebaseAuthREST.refreshIdToken(
            refreshToken: credential.refreshToken,
            apiKey: credential.apiKey,
            host: credential.authEmulatorHost.map { "\($0)/securetoken.googleapis.com" }
                ?? "https://securetoken.googleapis.com"
        )
        idTokenCacheado = (token: token, emitidoEn: Date())
        return token
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
        guard let payload = WatchCredentialPayload(applicationContext: applicationContext)
        else { return }

        // Si ya hay credencial de este mismo usuario, no se re-canjea: el
        // teléfono reenvía el contexto en cada arranque y canjear de nuevo
        // invalidaría el refresh token que ya funciona.
        if let existing = CredentialStore.load(), existing.uid == payload.uid {
            state = .ready(uid: existing.uid)
            return
        }

        state = .exchanging
        Task { await exchange(payload) }
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
        do {
            let idToken = try await freshIdToken()
            let client = FirestoreREST(
                projectId: credential.projectId,
                idToken: idToken,
                emulatorHost: credential.firestoreEmulatorHost
            )
            todaysWorkout = try await TodaysWorkoutResolver.resolve(
                client: client,
                uid: credential.uid
            )
            workoutError = nil
            workoutLoaded = true
        } catch {
            workoutError = String(describing: error)
            // `error` es privacy-sensitive por defecto en os_log y saldría como
            // "<private>", que es exactamente el silencio que esto viene a
            // romper. Va explícito: son mensajes de Firestore, no datos del
            // atleta.
            log.error("No se pudo cargar el entreno de hoy: \(String(describing: error), privacy: .public)")
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
        // No hay nada que hacer acá: el contexto se procesa en `start()` y en
        // el callback de abajo. Se implementa porque el protocolo lo exige.
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
    /// Hoy solo se usa para el aviso de "relee": el teléfono lo manda cuando el
    /// atleta cambia su rutina activa. Va por MENSAJE y no por contexto de
    /// aplicación a propósito — el contexto es uno solo y se pisa entero, y ahí
    /// vive la credencial.
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        guard message["kind"] as? String == "watchRefresh" else { return }
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
    fileprivate func refreshFromPhone() {
        externalRefresh += 1
        Task { await loadTodaysWorkout() }
    }
}
