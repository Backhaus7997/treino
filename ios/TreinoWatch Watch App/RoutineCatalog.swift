//
//  RoutineCatalog.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, fase F5.
//

import Foundation

/// De dónde salió una rutina. Define la chapita que se muestra y el orden.
enum RoutineOrigin: String {
    /// Plan que un PF le asignó al atleta.
    case coach
    /// Rutina que el atleta se armó él mismo en el teléfono.
    case own
    /// Plantilla que un entrenador publicó al catálogo público.
    case community
    /// Plantilla del catálogo de TREINO.
    case system

    var badge: String? {
        switch self {
        case .coach: return "COACH"
        case .own: return "MÍA"
        case .community: return "PF"
        case .system: return nil
        }
    }
}

/// Una rutina en las listas del reloj, sin resolver todavía qué día toca.
///
/// Es deliberadamente flaca: resolver el entreno de una rutina cuesta una query
/// más (la última sesión terminada de ESA rutina), y no tiene sentido pagarla
/// por cada fila de una lista que el atleta va a mirar de paso.
struct RoutineSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let numWeeks: Int
    let dayCount: Int
    let origin: RoutineOrigin
}

/// Las listas de rutinas que el reloj le ofrece al atleta.
///
/// ⚠️ **Las queries de acá son un PUERTO de `RoutineRepository` del teléfono.**
/// Los filtros tienen que coincidir campo por campo: `resolveActiveRoutineId`
/// decide sobre estas listas, así que una lista distinta produce una rutina
/// activa distinta aunque la función de decisión sea idéntica. El contrato de
/// conformidad cubre la DECISIÓN, no de dónde salen los datos — que es
/// exactamente el agujero por el que ya se coló un bug (leer el id de los
/// campos en vez del path).
///
/// Correspondencia exacta con `lib/features/workout/data/routine_repository.dart`:
///
/// | acá                  | teléfono                    | filtros                                          |
/// |----------------------|-----------------------------|--------------------------------------------------|
/// | `assignedPlans`      | `listAssignedTo`            | assignedTo == uid, source == trainer-assigned    |
/// | `selfCreatedPlans`   | `listUserCreated`           | createdBy == uid, source == user-created, active |
/// | `systemTemplates`    | `listSystemTemplates`       | source == system, visibility == public           |
/// | `communityTemplates` | `listPublishedTemplates`    | source == trainer-template, visibility == public |
///
/// Los índices compuestos que estas queries necesitan ya están declarados en
/// `firestore.indexes.json` — son los mismos que usa el teléfono.
enum RoutineCatalog {

    // MARK: - Planes del atleta

    /// Planes a nombre del atleta: los del PF primero, después los suyos.
    ///
    /// Es el MISMO orden que arma `unifiedRoutinesProvider` en el teléfono, y el
    /// mismo que consume `resolveActiveRoutineId` (asignadas antes que propias).
    static func plans(
        client: FirestoreREST,
        uid: String
    ) async throws -> [RoutineSummary] {
        let assigned = try await assignedPlans(client: client, uid: uid)
        let own = try await selfCreatedPlans(client: client, uid: uid)
        return assigned.map { summary($0, origin: .coach) }
            + own.map { summary($0, origin: .own) }
    }

    static func assignedPlans(
        client: FirestoreREST,
        uid: String
    ) async throws -> [FirestoreDocument] {
        try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": allOf([
                equals("assignedTo", uid),
                equals("source", "trainer-assigned"),
            ]),
            "orderBy": [descending("createdAt")],
            "limit": 20,
        ])
    }

    static func selfCreatedPlans(
        client: FirestoreREST,
        uid: String
    ) async throws -> [FirestoreDocument] {
        try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": allOf([
                equals("createdBy", uid),
                equals("source", "user-created"),
                // `status == 'active'` NO es opcional: sin él las rutinas
                // archivadas entran en la lista del reloj pero no en la del
                // teléfono, y `resolveActiveRoutineId` —que cuenta cuántas
                // auto-creadas hay— resuelve distinto en cada lado.
                equals("status", "active"),
            ]),
            "orderBy": [descending("createdAt")],
            "limit": 50,
        ])
    }

    // MARK: - Plantillas

    /// Plantillas para arrancar sin que sean un plan del atleta: el catálogo de
    /// TREINO más las que los entrenadores publicaron.
    ///
    /// NO incluye las que un PF comparte SOLO con sus atletas
    /// (`sharedTemplatesWithAthletes`): esas exigen resolver el vínculo
    /// atleta–entrenador primero, y son otra cosa que "las publicadas".
    static func templates(client: FirestoreREST) async throws -> [RoutineSummary] {
        let community = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": allOf([
                equals("source", "trainer-template"),
                equals("visibility", "public"),
            ]),
            "limit": 50,
        ])
        let system = try await client.runQuery([
            "from": [["collectionId": "routines"]],
            "where": allOf([
                equals("source", "system"),
                equals("visibility", "public"),
            ]),
            "limit": 50,
        ])
        // Las publicadas por entrenadores van primero, igual que en el grid del
        // teléfono: el catálogo de TREINO es el fondo, no el titular.
        return community.map { summary($0, origin: .community) }
            + system.map { summary($0, origin: .system) }
    }

    // MARK: - Activación

    /// Marca una rutina como la activa del atleta.
    ///
    /// Escribe el MISMO campo que el teléfono (`users/{uid}.activeRoutineId`),
    /// así que el cambio se ve en los dos lados. Se usa `patchFields` con
    /// máscara para no tocar el resto del perfil: las rules bloquean cualquier
    /// update que altere `uid`, `role`, `email`, `createdAt` o `subscription`,
    /// y un PATCH sin máscara los mandaría todos.
    static func setActiveRoutine(
        client: FirestoreREST,
        uid: String,
        routineId: String
    ) async throws {
        try await client.patchFields(
            path: "users/\(uid)",
            fields: ["activeRoutineId": ["stringValue": routineId]]
        )
    }

    // MARK: - Internos

    private static func summary(
        _ doc: FirestoreDocument,
        origin: RoutineOrigin
    ) -> RoutineSummary {
        RoutineSummary(
            id: doc.id,
            name: FS.string(doc.fields["name"]) ?? "Rutina",
            numWeeks: FS.int(doc.fields["numWeeks"]) ?? 1,
            dayCount: (FS.array(doc.fields["days"]) ?? []).count,
            origin: origin
        )
    }

    static func equals(_ path: String, _ value: String) -> [String: Any] {
        [
            "fieldFilter": [
                "field": ["fieldPath": path],
                "op": "EQUAL",
                "value": ["stringValue": value],
            ],
        ]
    }

    static func allOf(_ filters: [[String: Any]]) -> [String: Any] {
        ["compositeFilter": ["op": "AND", "filters": filters]]
    }

    static func descending(_ path: String) -> [String: Any] {
        ["field": ["fieldPath": path], "direction": "DESCENDING"]
    }
}
