/// Identidad de un documento de `setLogs` compartida entre los DOS clientes.
///
/// El reloj escribe las series con un id DETERMINÍSTICO derivado de la identidad
/// lógica de la serie (`exerciseId + setNumber`); el teléfono usa uno
/// autogenerado. Esa asimetría es deliberada y no se puede cerrar por el lado
/// del teléfono: borrar una serie renumera las siguientes, y con ids
/// determinísticos eso obligaría a MOVER documentos (ver
/// `openspec/changes/watch-standalone-client/HANDOFF.md` §4.3).
///
/// Lo que sí tiene que ser idéntico en los dos lenguajes es CÓMO se arma ese id.
/// Si divergen, el teléfono busca la serie del reloj en una ruta donde no está,
/// no la encuentra, y crea un segundo documento de la misma serie — el bug que
/// este archivo existe para cerrar. Como la fórmula vive escrita dos veces (acá
/// y en `ios/TreinoWatch Watch App/SetLogIdentity.swift`), está bajo el contrato
/// de conformidad `conformance/set_log_identity.json`, que corre contra las dos.
library;

/// Id del documento con el que el RELOJ escribe la serie [setNumber] de
/// [exerciseId].
///
/// El separador es DOBLE guion bajo a propósito: los `exerciseId` reales
/// contienen guiones bajos simples (`press_banca`), así que un separador simple
/// haría el id ambiguo de leer al depurar — y el id del documento es justamente
/// lo que se mira para saber qué cliente escribió qué.
///
/// Puerto Dart de `setLogDeterministicDocId` en Swift. Las dos están bajo
/// `conformance/set_log_identity.json`.
String setLogDeterministicDocId({
  required String exerciseId,
  required int setNumber,
}) =>
    '${exerciseId}__$setNumber';

/// Si el documento leído en una ruta determinística corresponde de verdad a la
/// serie [exerciseId] / [setNumber] que se está por escribir.
///
/// NO es una comparación redundante con la ruta. Un documento puede quedar en
/// una ruta que ya no describe su contenido: al borrar una serie, el teléfono
/// renumera las sobrevivientes con `updateSetLog`, que conserva el id del
/// documento y baja el campo `setNumber`. Después de eso, el documento
/// `sentadilla__3` puede contener la serie 2.
///
/// Escribir ahí confiando en la ruta PISARÍA esa serie: se perdería un dato que
/// el atleta cargó, que es peor que el duplicado que estamos arreglando. Por eso
/// la identidad se decide siempre por los CAMPOS, nunca por el path.
bool setLogDocHoldsSet({
  required Object? docExerciseId,
  required Object? docSetNumber,
  required String exerciseId,
  required int setNumber,
}) =>
    docExerciseId == exerciseId && docSetNumber == setNumber;
