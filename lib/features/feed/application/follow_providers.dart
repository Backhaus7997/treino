import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/follow_repository.dart';
import '../domain/follow.dart';

/// Providers del grafo social dirigido.
///
/// **Todas las keys de family son `String`**, nunca un record ni una `List`.
/// Riverpod compara las keys por igualdad, y una `List` usa identidad: dos
/// listas con el mismo contenido son keys distintas, así que el cache se
/// thrashea y se abren listeners de Firestore de más. Cuando hace falta una
/// key compuesta —como el par de uids de una arista— se pasa el doc id ya
/// armado con `Follow.edgeId(...)`.
final followRepositoryProvider = Provider<FollowRepository>(
  (ref) => FollowRepository(firestore: ref.watch(firestoreProvider)),
);

/// Una arista puntual, en vivo, por doc id (`'{follower}_{followee}'`).
///
/// Es el provider que responde "¿lo sigo?" y —consultando el id invertido—
/// "¿me sigue?". Los cuatro estados posibles entre dos usuarios salen de
/// combinar las dos consultas; por eso no existe un provider "de la relación"
/// que devuelva un solo objeto: eso volvería a colapsar las dos direcciones,
/// que es justo el bug del modelo viejo.
final followEdgeProvider =
    StreamProvider.family.autoDispose<Follow?, String>((ref, edgeId) {
  return ref.watch(followRepositoryProvider).watchEdge(edgeId);
});

/// UIDs a los que [uid] sigue, con la relación ya aceptada.
///
/// Reemplaza a `acceptedFriendsProvider` con una diferencia semántica que hay
/// que tener presente al migrar consumidores: el viejo devolvía a los dos lados
/// de la relación; este devuelve SOLO a quienes el usuario sigue.
final followingProvider =
    StreamProvider.family.autoDispose<List<String>, String>((ref, uid) {
  return ref.watch(followRepositoryProvider).watchFollowingOf(uid);
});

/// Solicitudes de follow que [uid] recibió y todavía no resolvió. Alimenta el
/// inbox. `autoDispose` porque el inbox es de alcance de pantalla.
final pendingReceivedStreamProvider =
    StreamProvider.family.autoDispose<List<Follow>, String>((ref, uid) {
  return ref.watch(followRepositoryProvider).watchPendingReceivedFor(uid);
});

/// Cantidad de solicitudes recibidas. Derivado en sincrónico del stream de
/// arriba; devuelve 0 mientras carga o si falla, para que el badge no
/// parpadee.
final pendingFollowRequestCountProvider =
    Provider.family.autoDispose<int, String>((ref, uid) {
  return ref.watch(pendingReceivedStreamProvider(uid)).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});
