//
//  FirestoreREST.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F2.
//

import Foundation

/// Cliente HTTP mínimo contra Firestore. **Sin SDK de Firebase.**
///
/// Firestore no figura entre los productos Firebase soportados en watchOS
/// (Locked Decision #9), así que el reloj habla su REST API. Lo que se pierde
/// respecto del SDK: persistencia offline y listeners en tiempo real. Ambos hay
/// que construirlos acá si hacen falta.
///
/// Las Security Rules SE APLICAN a estas requests — verificado contra el
/// emulador en `functions/src/__tests__/watch-rest-*.test.ts`.
struct FirestoreREST {

    let projectId: String
    let idToken: String
    /// Host alternativo para desarrollo local. Nil = producción.
    let emulatorHost: String?

    private var base: String {
        let host = emulatorHost ?? "https://firestore.googleapis.com"
        return "\(host)/v1/projects/\(projectId)/databases/(default)/documents"
    }

    enum FirestoreError: Error {
        case http(status: Int, body: String)
        case malformedResponse
    }

    // MARK: - Lecturas

    /// Trae un documento por path (ej. `routines/abc123`).
    ///
    /// Devuelve nil ante un 404: en Firestore "no existe" es una respuesta
    /// legítima, no un error. Ojo que las rules de TREINO distinguen 404 de 403
    /// a propósito — un doc inexistente devuelve "no existe" y no "prohibido".
    func document(
        _ path: String,
        session: URLSession = .shared
    ) async throws -> [String: Any]? {
        var request = URLRequest(url: URL(string: "\(base)/\(path)")!)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { return nil }
            guard http.statusCode == 200 else {
                throw FirestoreError.http(
                    status: http.statusCode,
                    body: String(data: data, encoding: .utf8) ?? ""
                )
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw FirestoreError.malformedResponse }
        return json["fields"] as? [String: Any]
    }

    /// Corre una structuredQuery y devuelve cada documento con su ID.
    ///
    /// El ID sale del PATH del documento, no de un campo: los docs creados por
    /// la app NO guardan `id` adentro — solo los sembrados por el script de
    /// seed lo tienen. Leerlo de los campos hacia que las rutinas reales
    /// quedaran con id vacio y no matchearan nunca contra el marcador de
    /// rutina activa.
    ///
    /// Las filas sin `document` se descartan: la respuesta de `runQuery`
    /// intercala entradas de solo-metadata (readTime) que no son resultados.
    /// [parent] es el path del documento padre para consultar una
    /// SUBCOLECCIÓN (ej. `users/abc` para `users/abc/sessions`). Sin él, la
    /// query corre sobre la raíz — y una subcolección consultada desde la raíz
    /// se convierte en collection-group, que las rules de TREINO rechazan con
    /// 403. Verificado contra el emulador.
    func runQuery(
        _ structuredQuery: [String: Any],
        parent: String? = nil,
        session: URLSession = .shared
    ) async throws -> [FirestoreDocument] {
        let endpoint = parent.map { "\(base)/\($0):runQuery" } ?? "\(base):runQuery"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["structuredQuery": structuredQuery]
        )

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FirestoreError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw FirestoreError.malformedResponse }

        return rows.compactMap { row -> FirestoreDocument? in
            guard let doc = row["document"] as? [String: Any],
                  let name = doc["name"] as? String
            else { return nil }
            return FirestoreDocument(
                id: name.split(separator: "/").last.map(String.init) ?? "",
                fields: doc["fields"] as? [String: Any] ?? [:]
            )
        }
    }

    // MARK: - Escrituras

    /// Crea un documento con id autogenerado y devuelve ese id.
    func createDocument(
        collectionPath: String,
        fields: [String: Any],
        session: URLSession = .shared
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "\(base)/\(collectionPath)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FirestoreError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String
        else { throw FirestoreError.malformedResponse }
        return name.split(separator: "/").last.map(String.init) ?? ""
    }

    /// Actualiza SOLO los campos dados, sin tocar el resto del documento.
    ///
    /// A diferencia de `setDocument`, que pisa el doc entero: aca hace falta
    /// preservar lo que ya estaba (routineId, startedAt, dayNumber...) y
    /// cambiar unos pocos campos. Se logra con `updateMask.fieldPaths`.
    func patchFields(
        path: String,
        fields: [String: Any],
        session: URLSession = .shared
    ) async throws {
        let mask = fields.keys
            .map { "updateMask.fieldPaths=\($0)" }
            .joined(separator: "&")
        var request = URLRequest(url: URL(string: "\(base)/\(path)?\(mask)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FirestoreError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    /// Crea o PISA un documento en un path conocido.
    ///
    /// Es la operacion que hace idempotentes las escrituras del reloj: con un
    /// id deterministico, reintentar no duplica.
    func setDocument(
        path: String,
        fields: [String: Any],
        session: URLSession = .shared
    ) async throws {
        var request = URLRequest(url: URL(string: "\(base)/\(path)")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw FirestoreError.http(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}

/// Un documento de Firestore con su ID resuelto desde el path.
struct FirestoreDocument {
    let id: String
    let fields: [String: Any]
}

// MARK: - Desempaquetado de los value-wrappers de Firestore

/// Firestore envuelve cada valor en un objeto con el nombre del tipo
/// (`{"stringValue": "x"}`). Estos helpers desarman eso.
///
/// Cuidado con los enteros: viajan como **string** dentro de `integerValue`,
/// no como número. Leerlos como Int directo devuelve nil y el bug es
/// silencioso — un dayNumber que no parsea se vuelve 0 y el reloj muestra
/// cualquier cosa.
enum FS {
    static func string(_ field: Any?) -> String? {
        (field as? [String: Any])?["stringValue"] as? String
    }

    static func int(_ field: Any?) -> Int? {
        guard let wrapper = field as? [String: Any] else { return nil }
        if let raw = wrapper["integerValue"] as? String { return Int(raw) }
        if let raw = wrapper["integerValue"] as? Int { return raw }
        return nil
    }

    static func double(_ field: Any?) -> Double? {
        guard let wrapper = field as? [String: Any] else { return nil }
        if let raw = wrapper["doubleValue"] as? Double { return raw }
        // Un entero redondo puede llegar como integerValue aunque el campo sea
        // numerico: Firestore no preserva "era double" si el valor no tiene
        // decimales.
        if let raw = wrapper["integerValue"] as? String { return Double(raw) }
        if let raw = wrapper["integerValue"] as? Int { return Double(raw) }
        return nil
    }

    static func array(_ field: Any?) -> [Any]? {
        guard let wrapper = field as? [String: Any],
              let arrayValue = wrapper["arrayValue"] as? [String: Any]
        else { return nil }
        // Un array vacío viene SIN la clave `values`, no con una lista vacía.
        return arrayValue["values"] as? [Any] ?? []
    }

    /// Desarma un `mapValue` y devuelve sus campos.
    static func mapFields(_ field: Any?) -> [String: Any]? {
        guard let wrapper = field as? [String: Any],
              let mapValue = wrapper["mapValue"] as? [String: Any]
        else { return nil }
        return mapValue["fields"] as? [String: Any]
    }

    /// Si el campo está VACÍO: ausente del documento, o presente con
    /// `nullValue`.
    ///
    /// ⚠️ **Los dos clientes de TREINO escriben el nulo distinto, y confundirlos
    /// rompe cosas silenciosamente.**
    ///
    /// El reloj OMITE el campo cuando no hay valor. El teléfono lo escribe con
    /// `nullValue` explícito: `json_serializable` incluye la clave siempre. Por
    /// eso preguntar `campo == nil` solo detecta el caso del reloj — un
    /// documento del teléfono devuelve el envoltorio `["nullValue": ...]`, que
    /// NO es nil, y la comparación da lo contrario de lo que uno quiere.
    ///
    /// Lo que rompía: una sesión ACTIVA creada en el teléfono se leía como
    /// terminada. El reloj no la adoptaba —mostraba "Empezar" mientras el
    /// atleta ya estaba entrenando—, creaba una sesión DUPLICADA al empezar el
    /// mismo día, y contaba esa sesión en curso como "última terminada", con lo
    /// que adelantaba el día del plan a mitad de entreno.
    ///
    /// Las mismas rules ya documentan esta trampa del lado servidor:
    /// `assignedTo == null` se compara contra null y no con un default, porque
    /// la clave EXISTE.
    static func isEmpty(_ field: Any?) -> Bool {
        guard let wrapper = field as? [String: Any] else { return true }
        return wrapper.keys.contains("nullValue") || wrapper.isEmpty
    }

    /// Lo contrario de [isEmpty]: el campo trae un valor de verdad.
    static func isPresent(_ field: Any?) -> Bool { !isEmpty(field) }
}
