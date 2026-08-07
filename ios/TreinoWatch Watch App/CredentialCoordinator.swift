//
//  CredentialCoordinator.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Combine
import Foundation
import WatchConnectivity

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

    /// Devuelve un idToken fresco para hablar con Firestore.
    ///
    /// Cada llamada renueva: los idTokens duran una hora y la renovación es
    /// barata comparada con manejar expiración a mano y equivocarse.
    func freshIdToken() async throws -> String {
        guard let credential = CredentialStore.load() else {
            throw FirebaseAuthREST.AuthError.malformedResponse
        }
        return try await FirebaseAuthREST.refreshIdToken(
            refreshToken: credential.refreshToken,
            apiKey: credential.apiKey,
            host: credential.authEmulatorHost.map { "\($0)/securetoken.googleapis.com" }
                ?? "https://securetoken.googleapis.com"
        )
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
        } catch {
            workoutError = String(describing: error)
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
}
