//
//  RestRules.swift
//  TreinoWatch Watch App
//
//  El descanso entre series, COMPARTIDO con el telefono (#1616).
//
//  ── Por que existe ───────────────────────────────────────────────────────
//
//  Antes cada aparato tenia su descanso: el reloj contaba ticks con un `Timer`
//  y el telefono contaba contra su propio instante de fin. Si el atleta
//  entrenaba con los dos corrian DOS descansos: Saltar en uno no se veia en el
//  otro, y cada uno vibraba por su cuenta.
//
//  Ahora el descanso es ESTADO de la sesion, como el cronometro del ejercicio
//  por tiempo: un instante de fin en tiempo de pared en el documento que los
//  dos ya leen. Cada uno lo espeja contra su propio reloj, asi que avisan en el
//  mismo instante. El documento es un registro unico y GANA EL QUE ESCRIBE
//  ULTIMO; espejar nunca escribe, asi que no hay rebote.
//
//  La regla vive aparte y PURA —solo Foundation, sin red— para medirla en el
//  host. Contrato con Dart en `conformance/rest_timer.json`; implementacion
//  hermana en `lib/features/workout/domain/rest_rules.dart`.
//
//  ⚠️ Los milisegundos desde epoch rondan 1,8e12 y NO entran en 32 bits, y en
//  watchOS `Int` es de 32 bits (arm64_32). Por eso aca todo instante viaja como
//  `Int64` — `FS.int` del cliente REST devolveria nil en la muneca.
//

import Foundation

/// Que aparato arranco el descanso. El valor crudo es el que va a la sesion.
enum RestOwner: String {
    case telefono = "phone"
    /// Cualquiera de los dos relojes: desde la sesion no se distinguen.
    case reloj = "watch"
}

/// El descanso tal como queda anotado en la sesion.
struct SharedRest: Equatable {
    let exerciseId: String
    let setNumber: Int
    /// Duracion total, contando los +15 s.
    let totalSeconds: Int
    /// Cuando termina. La fuente de la verdad.
    let endsAt: Date
    let owner: RestOwner

    /// Instante de fin en milisegundos desde epoch, como viaja.
    var endsAtMs: Int64 { RestRules.millis(endsAt) }
}

/// Que hacer con el descanso que dice la sesion.
enum RestMirrorAction: String {
    /// Nada: lo que se muestra ya es lo que dice la sesion.
    case keep
    /// Pasar a mostrar el de la sesion (arranco, se estiro o es otro).
    case adopt
    /// Cortar el propio: en la sesion ya no hay (lo saltaron del otro lado).
    case stop
}

enum RestRules {

    // MARK: - Campos del documento de sesion

    static let fieldExerciseId = "restExerciseId"
    static let fieldSetNumber = "restSetNumber"
    static let fieldTotalSeconds = "restTotalSeconds"
    static let fieldEndsAtMs = "restEndsAtMs"
    static let fieldOwner = "restOwner"

    /// Los cinco, para borrarlos juntos al Saltar.
    static let allFields = [
        fieldExerciseId, fieldSetNumber, fieldTotalSeconds, fieldEndsAtMs, fieldOwner,
    ]

    /// Cuanto suma «+15 s» en el telefono.
    static let extraSeconds = 15

    /// Hasta donde dos instantes de fin son EL MISMO descanso. Ver el porque
    /// en `rest_rules.dart`.
    static let mirrorToleranceMs: Int64 = 500

    // MARK: - Aritmetica

    /// Cuando termina un descanso de `totalSeconds` arrancado en `start`,
    /// redondeado al milisegundo mas cercano — la resolucion con la que viaja.
    /// Al mas cercano y no truncado: un `Date` es un `Double` de segundos, y
    /// 1800000000,123 s puede guardarse como ...122,9999 ms.
    static func endsAt(start: Date, totalSeconds: Int) -> Date {
        let finMs = millis(start) + Int64(totalSeconds) * 1000
        return date(fromMillis: finMs)
    }

    /// Segundos que faltan, hacia ARRIBA y nunca negativos. La MISMA regla que
    /// el ejercicio por tiempo, para que los dos numeros no se separen.
    static func remaining(endsAt: Date, now: Date) -> Int {
        CountdownRules.remaining(endsAt: endsAt, now: now)
    }

    static func isFinished(endsAt: Date, now: Date) -> Bool {
        CountdownRules.isFinished(endsAt: endsAt, now: now)
    }

    /// «+15 s», o nil si no hay descanso vivo que estirar.
    static func extend(
        endsAt: Date,
        totalSeconds: Int,
        seconds: Int,
        now: Date
    ) -> (endsAt: Date, totalSeconds: Int)? {
        if isFinished(endsAt: endsAt, now: now) { return nil }
        if seconds <= 0 { return (endsAt, totalSeconds) }
        let finMs = millis(endsAt) + Int64(seconds) * 1000
        return (date(fromMillis: finMs), totalSeconds + seconds)
    }

    /// Que hacer con el descanso de la sesion.
    ///
    /// `localPending` es un cambio local que todavia no se pudo escribir —este
    /// reloj escribe por REST y puede tener un Saltar o un descanso propio en
    /// vuelo—. Ese cambio es el mas nuevo y va a ganar cuando llegue, asi que lo
    /// que diga la sesion mientras tanto es viejo.
    static func decide(
        local: Date?,
        remote: Date?,
        localPending: Bool,
        now: Date
    ) -> RestMirrorAction {
        if localPending { return .keep }

        var localVivo = false
        if let local { localVivo = !isFinished(endsAt: local, now: now) }

        if let remote, !isFinished(endsAt: remote, now: now) {
            if let local, localVivo,
               abs(millis(local) - millis(remote)) <= mirrorToleranceMs {
                return .keep
            }
            return .adopt
        }
        // En la sesion no hay descanso vivo: si aca si, alguien lo salto.
        return localVivo ? .stop : .keep
    }

    // MARK: - Documento REST de Firestore

    /// El descanso que dice la sesion, o nil.
    ///
    /// Recibe los `fields` crudos del documento, con los envoltorios de la REST
    /// API (`{"integerValue": "..."}`). Cualquier campo faltante o invalido se
    /// lee como "no hay descanso", igual que del lado Dart: medio descanso no
    /// se espeja.
    static func parse(fields: [String: Any]) -> SharedRest? {
        guard
            let exerciseId = string(fields[fieldExerciseId]), !exerciseId.isEmpty,
            let setNumber = int64(fields[fieldSetNumber]), setNumber > 0,
            let total = int64(fields[fieldTotalSeconds]), total > 0,
            let endsAtMs = int64(fields[fieldEndsAtMs]),
            let ownerRaw = string(fields[fieldOwner]),
            let owner = RestOwner(rawValue: ownerRaw)
        else { return nil }
        return SharedRest(
            exerciseId: exerciseId,
            setNumber: Int(setNumber),
            totalSeconds: Int(total),
            endsAt: date(fromMillis: endsAtMs),
            owner: owner
        )
    }

    /// Lo que se escribe, con los envoltorios de la REST API. Los enteros van
    /// como STRING dentro de `integerValue`: es lo que pide la API, y lo que el
    /// SDK del telefono lee como `int`.
    static func encode(_ rest: SharedRest) -> [String: Any] {
        [
            fieldExerciseId: ["stringValue": rest.exerciseId],
            fieldSetNumber: ["integerValue": String(rest.setNumber)],
            fieldTotalSeconds: ["integerValue": String(rest.totalSeconds)],
            fieldEndsAtMs: ["integerValue": String(rest.endsAtMs)],
            fieldOwner: ["stringValue": rest.owner.rawValue],
        ]
    }

    // MARK: - Internos

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(fromMillis ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    private static func string(_ field: Any?) -> String? {
        (field as? [String: Any])?["stringValue"] as? String
    }

    /// Entero de 64 bits de un envoltorio `integerValue`, que la API manda
    /// como string. Ver el ⚠️ del encabezado: `Int(raw)` en la muneca da nil.
    private static func int64(_ field: Any?) -> Int64? {
        guard let wrapper = field as? [String: Any] else { return nil }
        if let raw = wrapper["integerValue"] as? String { return Int64(raw) }
        if let raw = wrapper["integerValue"] as? Int64 { return raw }
        if let raw = wrapper["integerValue"] as? Int { return Int64(raw) }
        return nil
    }
}
