//
//  WatchCredential.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Foundation

/// Lo que el teléfono entrega por WatchConnectivity para que el reloj consiga
/// credencial propia.
///
/// CONTRATO ENTRE LENGUAJES. Este shape tiene que coincidir exactamente con
/// `lib/features/watch/domain/watch_credential_payload.dart`. Si cambia de un
/// lado y no del otro, el handoff falla en silencio.
///
/// `apiKey` y `projectId` viajan en el payload porque el reloj NO usa el SDK
/// de Firebase: Firestore ni figura entre los productos soportados en watchOS,
/// así que todo va por HTTP y hace falta la config a mano. No son secretos —
/// son identificadores públicos; la seguridad la dan las Security Rules.
struct WatchCredentialPayload: Equatable {
    static let kind = "watchCredential"

    let customToken: String
    let uid: String
    let apiKey: String
    let projectId: String

    /// Host del emulador de Auth, SOLO desarrollo local. Nil en producción.
    ///
    /// Se ignora por completo en builds de release (ver el init de abajo): sin
    /// ese guard, un payload malicioso podría redirigir la autenticación del
    /// reloj a un host cualquiera. Con el guard, el campo es inofensivo por
    /// construcción en vez de depender de que nadie lo mande.
    let authEmulatorHost: String?

    /// Parsea el diccionario que llega por `didReceiveApplicationContext`.
    ///
    /// Devuelve nil ante cualquier campo faltante o vacío en vez de construir
    /// un payload a medias: un token vacío falla mucho después, lejos de la
    /// causa y sin nadie mirando.
    init?(applicationContext: [String: Any]) {
        guard applicationContext["kind"] as? String == Self.kind else { return nil }

        func nonEmpty(_ key: String) -> String? {
            guard let value = applicationContext[key] as? String, !value.isEmpty else {
                return nil
            }
            return value
        }

        guard let customToken = nonEmpty("customToken"),
              let uid = nonEmpty("uid"),
              let apiKey = nonEmpty("apiKey"),
              let projectId = nonEmpty("projectId")
        else { return nil }

        self.customToken = customToken
        self.uid = uid
        self.apiKey = apiKey
        self.projectId = projectId

        #if DEBUG
        self.authEmulatorHost = nonEmpty("authEmulatorHost")
        #else
        // En release NUNCA se honra un host recibido por el canal: siempre
        // producción.
        self.authEmulatorHost = nil
        #endif
    }

    /// Init directo, para tests y para reconstruir desde almacenamiento.
    init(
        customToken: String,
        uid: String,
        apiKey: String,
        projectId: String,
        authEmulatorHost: String? = nil
    ) {
        self.customToken = customToken
        self.uid = uid
        self.apiKey = apiKey
        self.projectId = projectId
        self.authEmulatorHost = authEmulatorHost
    }
}

/// La credencial que el reloj mantiene por su cuenta después del canje.
///
/// El `refreshToken` es lo que hace autónomo al reloj: con él renueva el
/// `idToken` (que dura una hora) para siempre, sin volver a depender del
/// teléfono.
struct WatchCredential: Equatable {
    let refreshToken: String
    let uid: String
    let apiKey: String
    let projectId: String

    /// Se persiste junto con la credencial para que la renovación en arranques
    /// posteriores siga apuntando al mismo lado que el canje inicial.
    let authEmulatorHost: String?

    init(
        refreshToken: String,
        uid: String,
        apiKey: String,
        projectId: String,
        authEmulatorHost: String? = nil
    ) {
        self.refreshToken = refreshToken
        self.uid = uid
        self.apiKey = apiKey
        self.projectId = projectId
        self.authEmulatorHost = authEmulatorHost
    }
}
