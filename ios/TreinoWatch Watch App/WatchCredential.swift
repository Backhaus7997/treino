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
    }

    /// Init directo, para tests y para reconstruir desde almacenamiento.
    init(customToken: String, uid: String, apiKey: String, projectId: String) {
        self.customToken = customToken
        self.uid = uid
        self.apiKey = apiKey
        self.projectId = projectId
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
}
