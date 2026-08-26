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

/// Una serie tal como está EN EL HISTORIAL: su identidad lógica y el documento
/// que la contiene.
///
/// Puerto Dart de `RemoteSetLogRef` en `SetLogIdentity.swift`.
class RemoteSetLogRef {
  const RemoteSetLogRef({
    required this.docId,
    required this.exerciseId,
    required this.setNumber,
  });

  final String docId;
  final String exerciseId;
  final int setNumber;
}

/// Dónde tiene que escribir un reloj la serie [setNumber] de [exerciseId].
///
/// Puerto Dart de `SetLogWriteTarget`. Ver [resolveSetLogWriteTarget].
sealed class SetLogWriteTarget {
  const SetLogWriteTarget(this.docId);

  /// El documento involucrado. En [SetLogAlreadyThere] es dónde YA está.
  final String docId;
}

/// La serie ya está en el historial, en este documento. **No escribir.**
class SetLogAlreadyThere extends SetLogWriteTarget {
  const SetLogAlreadyThere(super.docId);
}

/// Escribir en este documento.
class SetLogWriteTo extends SetLogWriteTarget {
  const SetLogWriteTo(super.docId);
}

/// Dónde tiene que escribir el reloj la serie [setNumber] de [exerciseId], dado
/// lo que el historial YA tiene.
///
/// Puerto Dart de `resolveSetLogWriteTarget` en
/// `ios/TreinoWatch Watch App/SetLogIdentity.swift`. Los fixtures compartidos de
/// `conformance/set_log_write_target.json` son el contrato entre ambas.
///
/// El reloj de Wear OS **no puede** usar `SessionRepository.addSetLog`: ese
/// método es el camino del TELÉFONO, que cae a un id autogenerado cuando la ruta
/// determinística está libre. Si el reloj escribiera así, el teléfono no lo
/// encontraría en esa ruta, la adopción no dispararía, y volverían los
/// duplicados que costaron 24 documentos de más y 11.450 kg fantasma.
///
/// Las tres respuestas, en orden de precedencia:
///
/// 1. **[SetLogAlreadyThere]** — el historial ya tiene esa serie lógica. La
///    escribió el teléfono (con id autogenerado) o un intento anterior del
///    reloj. No hay nada que subir, y volver a escribirla sólo podría pisar una
///    corrección que el atleta hizo en el celular.
/// 2. **[SetLogWriteTo] con un id propio** — la ruta determinística está ocupada
///    por OTRA serie lógica. Pasa después de que el teléfono borre una serie: al
///    renumerar conserva el id del documento y baja el campo `setNumber`, así
///    que `sentadilla__3` puede contener la serie 2. Escribir ahí la perdería, y
///    perder una serie que el atleta hizo es peor que un duplicado.
/// 3. **[SetLogWriteTo] con el determinístico** — el caso normal.
///
/// Es PURA para poder medirla en el host: dónde escribir es justo lo que no se
/// puede verificar cómodo corriendo el reloj.
SetLogWriteTarget resolveSetLogWriteTarget({
  required String exerciseId,
  required int setNumber,
  required List<RemoteSetLogRef> remote,
}) {
  // Por identidad LÓGICA, no por id: si la escribió el teléfono, su documento
  // tiene un id autogenerado y por id no matchearía nunca. Ése es exactamente
  // el agujero que dejaba dos documentos de la misma serie.
  for (final ref in remote) {
    if (ref.exerciseId == exerciseId && ref.setNumber == setNumber) {
      return SetLogAlreadyThere(ref.docId);
    }
  }

  final deterministic =
      setLogDeterministicDocId(exerciseId: exerciseId, setNumber: setNumber);

  // Ocupada por otra serie lógica (renumeración del teléfono): un id propio
  // antes que pisar un dato del atleta. El sufijo lo hace estable para el mismo
  // par ejercicio/serie, así que reintentar sigue siendo idempotente.
  for (final ref in remote) {
    if (ref.docId == deterministic) {
      return SetLogWriteTo('${deterministic}__alt');
    }
  }

  return SetLogWriteTo(deterministic);
}
