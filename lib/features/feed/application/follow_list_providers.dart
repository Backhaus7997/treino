import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/user_public_profile.dart';
import 'follow_providers.dart';

/// Cuál de las dos listas del perfil se está mirando.
enum FollowListKind { followers, following }

/// Key de family para las listas: `'{followers|following}:{uid}'`.
///
/// **Las keys de family son `String`, nunca un record ni una `List`** — Riverpod
/// compara por igualdad y una `List` usa identidad, así que dos keys con el
/// mismo contenido serían distintas y se abrirían listeners de Firestore de
/// más. Acá hacen falta dos datos (dirección + uid), así que se serializan.
String followListKey(FollowListKind kind, String uid) => '${kind.name}:$uid';

/// Inversa de [followListKey]. Corta en el PRIMER `:` para que un uid con dos
/// puntos —que Firebase no genera, pero que nadie garantiza— no rompa el
/// parseo.
({FollowListKind kind, String uid}) parseFollowListKey(String key) {
  final i = key.indexOf(':');
  final name = key.substring(0, i);
  return (
    kind: FollowListKind.values.byName(name),
    uid: key.substring(i + 1),
  );
}

/// Los UIDs de una de las dos listas, en vivo.
///
/// Va al repositorio directo en vez de reenviar a [followingProvider]: ese
/// provider expone un `AsyncValue`, y encadenarlo obligaría a `.stream`, que
/// está deprecado y desaparece en Riverpod 3. El costo es un listener más
/// sobre la misma query mientras la pantalla está abierta.
///
/// Existe separado de [followListProvider] para que el orden que devuelve
/// Firestore sea observable y testeable sin pasar por la resolución de
/// perfiles.
final followListUidsProvider =
    StreamProvider.family.autoDispose<List<String>, String>((ref, key) {
  final (:kind, :uid) = parseFollowListKey(key);
  final repo = ref.watch(followRepositoryProvider);
  return switch (kind) {
    FollowListKind.followers => repo.watchFollowersOf(uid),
    FollowListKind.following => repo.watchFollowingOf(uid),
  };
});

/// Una de las dos listas ya resuelta a perfiles públicos, lista para pintar.
///
/// **No pagina.** La query de `follows` se trae todas las aristas aceptadas y
/// [userPublicProfilesBatchProvider] resuelve los perfiles de a 30 (el tope de
/// `whereIn`). Con el volumen actual de TREINO eso es una sola query; a escala
/// de miles de seguidores habría que paginar las dos cosas. Se deja explícito
/// en vez de meter un tope silencioso, que se leería como "está todo" cuando
/// no lo está.
final followListProvider =
    FutureProvider.family.autoDispose<List<UserPublicProfile>, String>(
  (ref, key) async {
    final uids = await ref.watch(followListUidsProvider(key).future);
    if (uids.isEmpty) return const [];

    final byUid = await ref.watch(
      userPublicProfilesBatchProvider(uids.join(',')).future,
    );

    // Se recorre `uids`, no `byUid.values`: el batch devuelve un Map (sin
    // orden garantizado) y la lista tiene que salir en el orden de la query.
    // Un uid sin perfil —arista que sobrevivió a una cuenta borrada— se omite
    // en vez de romper la lista entera.
    return uids
        .map((uid) => byUid[uid])
        .whereType<UserPublicProfile>()
        .toList();
  },
);
