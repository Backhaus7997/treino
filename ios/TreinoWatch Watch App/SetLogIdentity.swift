//
//  SetLogIdentity.swift
//  TreinoWatch Watch App
//
//  Change `watch-standalone-client`, tanda de bugfixes de sincronizacion.
//

import Foundation

/// Identidad de un documento de `setLogs` compartida entre los DOS clientes.
///
/// El reloj escribe las series con un id DETERMINISTICO derivado de la identidad
/// logica de la serie (`exerciseId + setNumber`); el telefono usa uno
/// autogenerado. Esa asimetria es deliberada y no se puede cerrar por el lado
/// del telefono: borrar una serie renumera las siguientes, y con ids
/// deterministicos eso obligaria a MOVER documentos (HANDOFF §4.3).
///
/// Lo que si tiene que ser identico en los dos lenguajes es COMO se arma ese id.
/// Si divergen, el telefono busca la serie del reloj en una ruta donde no esta,
/// no la encuentra, y crea un segundo documento de la misma serie. Como la
/// formula vive escrita dos veces (aca y en
/// `lib/features/workout/domain/set_log_identity.dart`), esta bajo el contrato
/// de conformidad `conformance/set_log_identity.json`, que corre contra las dos.

/// Id del documento con el que el RELOJ escribe la serie `setNumber` de
/// `exerciseId`.
///
/// El separador es DOBLE guion bajo a proposito: los `exerciseId` reales
/// contienen guiones bajos simples (`press_banca`), asi que un separador simple
/// haria el id ambiguo de leer al depurar — y el id del documento es justamente
/// lo que se mira para saber que cliente escribio que.
///
/// Va suelta y no dentro de `HistorySync` para que el corredor de conformidad la
/// compile sin arrastrar el cliente HTTP. Puerto Swift de
/// `setLogDeterministicDocId` en Dart.
func setLogDeterministicDocId(exerciseId: String, setNumber: Int) -> String {
    "\(exerciseId)__\(setNumber)"
}

/// Una serie tal como esta EN EL HISTORIAL: su identidad logica y el id del
/// documento que la contiene.
///
/// Existe para poder decidir donde escribir sin depender de `LoggedSet`, que
/// arrastra el estado local (`synced`, `completedAt`) y no hace falta para esto.
struct RemoteSetLogRef: Equatable {
    let docId: String
    let exerciseId: String
    let setNumber: Int
}

/// Donde tiene que escribir el reloj la serie `setNumber` de `exerciseId`, dado
/// lo que el historial YA tiene.
///
/// Las tres respuestas posibles, en orden de precedencia:
///
/// 1. **`.alreadyThere(docId:)`** — el historial ya tiene esa serie logica. La
///    escribio el telefono (id autogenerado) o un intento anterior del reloj.
///    No hay nada que subir: el dato ya esta. Volver a escribirlo solo podria
///    pisar una correccion que el atleta hizo en el celular.
/// 2. **`.write(docId:)` con un id propio** — la ruta deterministica esta
///    ocupada por OTRA serie logica. Pasa despues de que el telefono borre una
///    serie: al renumerar conserva el id del documento y baja el campo
///    `setNumber`, asi que `sentadilla__3` puede contener la serie 2. Escribir
///    ahi la perderia.
/// 3. **`.write(docId:)` con el deterministico** — el caso normal.
///
/// Es una funcion PURA para poder medirla en el host: la decision de donde
/// escribir es justo lo que no se puede verificar comodo corriendo el reloj.
enum SetLogWriteTarget: Equatable {
    /// La serie ya esta en el historial, en este documento. No escribir.
    case alreadyThere(docId: String)
    /// Escribir en este documento.
    case write(docId: String)
}

/// Si una serie que el reloj tiene cargada hay que SACARLA porque el telefono la
/// borro.
///
/// El reloj no puede borrar ni agregar series: son gestos del telefono. Asi que
/// una serie que ya se subio y ya NO esta en el historial solo pudo haberla
/// borrado el celular, y el reloj se quedaba mostrandola hecha para siempre.
///
/// `synced == false` NUNCA se saca: esa es la cola de pendientes. Una serie
/// cargada en la muñeca y todavia sin subir no puede desaparecer porque el
/// remoto aun no la tiene — perder una serie que el atleta hizo es peor que
/// mostrar de mas. Esa era la razon por la que la sincronizacion solo AGREGABA;
/// la razon es correcta, lo que estaba mal era aplicarla tambien a las que ya
/// estaban arriba.
func setLogWasDeletedRemotely(
    exerciseId: String,
    setNumber: Int,
    synced: Bool,
    remote: [RemoteSetLogRef]
) -> Bool {
    guard synced else { return false }
    return !remote.contains {
        $0.exerciseId == exerciseId && $0.setNumber == setNumber
    }
}

func resolveSetLogWriteTarget(
    exerciseId: String,
    setNumber: Int,
    remote: [RemoteSetLogRef]
) -> SetLogWriteTarget {
    // Por identidad LOGICA, no por id: si la escribio el telefono su documento
    // tiene un id autogenerado y por id no matchearia nunca. Es exactamente el
    // agujero que dejaba dos documentos de la misma serie.
    if let mine = remote.first(
        where: { $0.exerciseId == exerciseId && $0.setNumber == setNumber }
    ) {
        return .alreadyThere(docId: mine.docId)
    }

    let deterministic = setLogDeterministicDocId(
        exerciseId: exerciseId, setNumber: setNumber
    )
    // Ocupada por otra serie logica (renumeracion del telefono): un id propio
    // antes que pisar un dato del atleta. El sufijo lo hace estable para el
    // mismo par ejercicio/serie, asi que reintentar sigue siendo idempotente.
    if remote.contains(where: { $0.docId == deterministic }) {
        return .write(docId: "\(deterministic)__alt")
    }

    return .write(docId: deterministic)
}
