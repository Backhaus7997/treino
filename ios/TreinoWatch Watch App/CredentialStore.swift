//
//  CredentialStore.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F1.
//

import Foundation
import Security

/// Guarda la credencial del reloj en el Keychain.
///
/// El refresh token es lo que hace autónomo al reloj: con él renueva para
/// siempre sin el teléfono. Por eso NO va en UserDefaults — va al Keychain,
/// que es almacenamiento cifrado y respaldado por el hardware.
///
/// `kSecAttrAccessibleAfterFirstUnlock` es deliberado: el reloj tiene que
/// poder renovar su credencial en segundo plano, cuando el usuario no lo tiene
/// desbloqueado en la muñeca. Con `WhenUnlocked` la renovación fallaría
/// justo en mitad de un entreno.
enum CredentialStore {

    private static let service = "com.backhaus.treino.watch"
    private static let account = "credential"

    enum StoreError: Error {
        case keychain(OSStatus)
    }

    /// Guarda (o pisa) la credencial.
    static func save(_ credential: WatchCredential) throws {
        var payload: [String: String] = [
            "refreshToken": credential.refreshToken,
            "uid": credential.uid,
            "apiKey": credential.apiKey,
            "projectId": credential.projectId,
        ]
        // Se persiste para que las renovaciones de arranques posteriores
        // apunten al mismo host que el canje inicial. Sin esto, tras reabrir la
        // app el reloj renovaría contra producción con un refresh token del
        // emulador.
        if let host = credential.authEmulatorHost {
            payload["authEmulatorHost"] = host
        }
        if let host = credential.firestoreEmulatorHost {
            payload["firestoreEmulatorHost"] = host
        }
        let data = try JSONSerialization.data(withJSONObject: payload)

        // Se borra primero para que guardar sea idempotente: SecItemAdd falla
        // con errSecDuplicateItem si el ítem ya existe, y un re-pairing tiene
        // que poder pisar la credencial vieja sin ceremonia.
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.keychain(status)
        }
    }

    /// Devuelve la credencial guardada, o nil si el reloj todavía no fue
    /// emparejado (o si el usuario cerró sesión).
    static func load() -> WatchCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let refreshToken = json["refreshToken"],
            let uid = json["uid"],
            let apiKey = json["apiKey"],
            let projectId = json["projectId"]
        else {
            return nil
        }

        return WatchCredential(
            refreshToken: refreshToken,
            uid: uid,
            apiKey: apiKey,
            projectId: projectId,
            authEmulatorHost: json["authEmulatorHost"],
            firestoreEmulatorHost: json["firestoreEmulatorHost"]
        )
    }

    /// Borra la credencial. Se usa al re-emparejar y al cerrar sesión.
    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
