//
//  FirebaseAuthREST.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Foundation

/// Cliente HTTP mínimo contra Firebase Auth. **Sin SDK de Firebase.**
///
/// Firebase en watchOS es community-supported y Firestore ni siquiera figura
/// entre sus productos soportados, así que el reloj no lo usa para nada
/// (Locked Decision #9). Las dos operaciones que necesita son endpoints REST
/// estables de Google, y esto es todo lo que hace falta para hablarles.
///
/// Verificado contra el emulador antes de escribirse: el canje de un custom
/// token devuelve `refreshToken`, y con ese refresh token se obtienen idTokens
/// frescos indefinidamente (`expires_in` 3600).
enum FirebaseAuthREST {

    enum AuthError: Error, Equatable {
        /// El backend respondió con un status != 200.
        case http(status: Int, body: String)
        /// La respuesta llegó bien pero sin los campos esperados.
        case malformedResponse
    }

    /// Resultado del canje inicial: el reloj pasa a tener credencial propia.
    struct ExchangedCredential: Equatable {
        let idToken: String
        let refreshToken: String
    }

    /// Canjea el custom token que mandó el teléfono por credenciales PROPIAS
    /// del reloj.
    ///
    /// Se hace una sola vez, en el pairing. A partir de acá el reloj no
    /// necesita más al teléfono para autenticarse.
    static func exchangeCustomToken(
        _ customToken: String,
        apiKey: String,
        host: String = "https://identitytoolkit.googleapis.com",
        session: URLSession = .shared
    ) async throws -> ExchangedCredential {
        let url = URL(string: "\(host)/v1/accounts:signInWithCustomToken?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": customToken,
            "returnSecureToken": true,
        ])

        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let idToken = json["idToken"] as? String,
            let refreshToken = json["refreshToken"] as? String
        else {
            throw AuthError.malformedResponse
        }

        return ExchangedCredential(idToken: idToken, refreshToken: refreshToken)
    }

    /// Renueva el idToken (dura una hora) usando el refresh token guardado.
    ///
    /// Esta es la operación que hace autónomo al reloj: no involucra al
    /// teléfono ni al SDK.
    static func refreshIdToken(
        refreshToken: String,
        apiKey: String,
        host: String = "https://securetoken.googleapis.com",
        session: URLSession = .shared
    ) async throws -> String {
        let url = URL(string: "\(host)/v1/token?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let encoded = refreshToken.addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        ) ?? refreshToken
        request.httpBody = "grant_type=refresh_token&refresh_token=\(encoded)"
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try checkStatus(response, data: data)

        // Ojo: este endpoint responde en snake_case (`id_token`), a diferencia
        // de identitytoolkit que usa camelCase (`idToken`). Son APIs distintas.
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let idToken = json["id_token"] as? String
        else {
            throw AuthError.malformedResponse
        }

        return idToken
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw AuthError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
