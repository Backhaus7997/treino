//
//  WorkoutSession.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F3.
//

import Foundation

/// Una serie efectivamente hecha por el atleta.
///
/// La identidad lógica es `exerciseId + setNumber`, LA MISMA clave de
/// idempotencia que usa `SessionNotifier.logSet` en el teléfono. Cuando F4
/// sincronice al historial, esa coincidencia es lo que evita duplicados si el
/// mismo entreno se tocó desde los dos lados.
struct LoggedSet: Codable, Equatable {
    let exerciseId: String
    /// 1-based, igual que en el teléfono.
    let setNumber: Int
    let reps: Int?
    let weightKg: Double?
    let completedAt: Date

    /// Si ya llego al historial. Las que quedan en false son LA COLA: se
    /// reintentan en cada sync hasta que entran. Por eso la serie se registra
    /// primero local y se sube despues — si se hiciera al reves, una escritura
    /// fallida perderia la serie que el atleta ya hizo.
    var synced: Bool = false
}

/// La sesión de entrenamiento que el reloj mantiene por su cuenta.
///
/// Vive SOLO en el reloj por ahora (F3). Escribirla al historial es F4, y ahí
/// aparece el problema difícil: no duplicar si el teléfono también abrió una.
struct WorkoutSession: Codable, Equatable {
    let localId: String
    let routineId: String
    let routineName: String
    let dayName: String
    let dayNumber: Int
    let weekNumber: Int
    let startedAt: Date
    var loggedSets: [LoggedSet]

    /// Id de la sesion en Firestore. Nil mientras no se pudo crear/adoptar
    /// (sin red al empezar): se resuelve en el proximo sync.
    var remoteId: String?

    var pendingSets: [LoggedSet] { loggedSets.filter { !$0.synced } }

    /// Si esa serie de ese ejercicio ya está cargada.
    ///
    /// Se compara por identidad lógica y no por posición en la lista: es lo que
    /// hace que cargar dos veces la misma serie sea idempotente, igual que en
    /// el teléfono.
    func isLogged(exerciseId: String, setNumber: Int) -> Bool {
        loggedSets.contains {
            $0.exerciseId == exerciseId && $0.setNumber == setNumber
        }
    }

    func loggedCount(exerciseId: String) -> Int {
        loggedSets.filter { $0.exerciseId == exerciseId }.count
    }
}

/// Guarda la sesión en curso en disco, para que sobreviva a que la app del
/// reloj se cierre o el sistema la descarte.
///
/// Va a un archivo JSON y no al Keychain: no es un secreto, y el Keychain
/// sobrevive incluso a la desinstalación, lo que acá sería un estorbo.
enum WorkoutSessionStore {

    private static var url: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("workout-session.json")
    }

    static func save(_ session: WorkoutSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> WorkoutSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkoutSession.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
