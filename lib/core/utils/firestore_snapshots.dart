import 'package:cloud_firestore/cloud_firestore.dart';

/// Listener de un documento que NO confunde "todavía no sé" con "no existe".
///
/// Con la caché local fría (o con una caché que nunca vio ese doc) la PRIMERA
/// snapshot de un documento inexistente llega con `exists == false` e
/// `isFromCache == true`, antes de que el servidor conteste. Emitirla como un
/// hecho manda a un usuario existente a /profile-setup, o a un alumno que paga
/// a `free`. Por eso se descarta: sólo una snapshot confirmada por el servidor
/// puede decir que el documento no está.
///
/// **`includeMetadataChanges: true` es lo que hace que la guarda no cuelgue.**
/// Cuando el servidor confirma ese mismo "no existe", los DATOS no cambiaron:
/// sólo la metadata (`isFromCache` pasa de true a false). Sin la opción el SDK
/// no emite ese cambio, la única snapshot ya se descartó y el stream queda en
/// loading para siempre. (Mismo comportamiento documentado en
/// `FollowRepository.watchConfirmedFollowingOf`.)
///
/// Costo: ahora también llegan las snapshots que sólo cambian la metadata
/// (`hasPendingWrites`, `isFromCache`). Quien consume tiene que deduplicar
/// sobre el valor ya mapeado (`.map(...).distinct()`), que es lo que casi
/// todos los providers hacen igual.
extension SnapshotsSinCacheVacia<T extends Object?> on DocumentReference<T> {
  Stream<DocumentSnapshot<T>> snapshotsSinCacheVacia() {
    return snapshots(includeMetadataChanges: true)
        .where((snap) => snap.exists || !snap.metadata.isFromCache);
  }
}
