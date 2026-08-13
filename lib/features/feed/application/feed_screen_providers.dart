import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../domain/feed_segment.dart';
import '../domain/post.dart';
import 'follow_providers.dart';
import 'post_providers.dart';

final feedSegmentProvider = StateProvider<FeedSegment>(
  (ref) => FeedSegment.amigos,
);

/// Stable pagination key for the authenticated user's SEGUIDORES segment.
///
/// `null` means unauthenticated. The current UID is intentionally part of the
/// serialized key so the author's own followers-privacy posts remain visible.
///
/// REQ-FOLLOW-011 — el conjunto sale de [followingProvider], o sea de a quiénes
/// SIGO. El viejo `acceptedFriendsProvider` devolvía los DOS lados de la
/// relación, así que alguien que me seguía sin que yo lo siguiera aportaba sus
/// posts a mi feed. Con el grafo dirigido eso deja de pasar, y es la mitad
/// visible del cambio de modelo.
final myFollowingFeedPaginationKeyProvider =
    FutureProvider<String?>((ref) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;

  final friendUids = await ref.watch(followingProvider(auth.uid).future);
  // QA-FEED-003: incluir el propio uid para que los posts del tier SEGUIDORES
  // del autor aparezcan en su propio feed (consistente con MI GYM / PÚBLICO,
  // donde los propios sí se ven). Sin esto, el autor publica y no ve nada. No
  // hay early-return por conjunto vacío: alguien que no sigue a nadie igual
  // debe ver sus propios posts. La regla de posts ya permite leer los propios
  // (request.auth.uid == authorUid), así que la query no falla.
  final authorUids = <String>{...friendUids, auth.uid}.toList();
  return friendsFeedPaginationKey(friendUidsKey(authorUids));
});

final myFollowingFeedProvider = FutureProvider<List<Post>>((ref) async {
  final paginationKey =
      await ref.watch(myFollowingFeedPaginationKeyProvider.future);
  if (paginationKey == null) return const <Post>[];
  final friendKey = paginationKey.substring('friends:'.length);
  return ref.watch(feedForFriendsProvider(friendKey).future);
});

/// Stable pagination key for the current user's MI GYM segment.
///
/// `null` retains the existing "user has no gym" semantic.
final myGymFeedPaginationKeyProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final gymId = profile?.gymId;
  return gymId == null ? null : gymFeedPaginationKey(gymId);
});

/// Returns the gym-privacy feed for the current user's gym.
///
/// - `null`  = user has no gym (gymId is null on their profile)
/// - `[]`    = user belongs to a gym but it has no posts yet
/// - `[...]` = gym posts, newest first
///
/// Mirrors [myFollowingFeedProvider] in semantics.
final myGymFeedProvider = FutureProvider<List<Post>?>((ref) async {
  final paginationKey = await ref.watch(myGymFeedPaginationKeyProvider.future);
  if (paginationKey == null) return null;
  final gymId = paginationKey.substring('gym:'.length);
  return ref.watch(feedForGymProvider(gymId).future);
});

/// Invalida TODO el modelo de lectura de posts tras un write
/// (create/update/delete) — wrappers Y families subyacentes.
///
/// `ref.invalidate` NO cascada a las dependencias (QA-498, #497): invalidar
/// sólo el wrapper ([myFollowingFeedProvider] / [myGymFeedProvider]) re-corre su
/// body, pero su `ref.watch` de la family subyacente ([feedForFriendsProvider]
/// / [feedForGymProvider], no autoDispose) devuelve la instancia cacheada
/// mientras la key no cambie — el query a Firestore no se re-emite y el post
/// recién escrito queda invisible hasta reiniciar la app (bug share-workout,
/// 2026-07-28). Las families se invalidan sin argumento: baja cardinalidad,
/// tumba todas las instancias y las que tienen listeners re-fetchean solas.
///
/// Único punto de invalidación para los tres writers (`CreatePostNotifier`,
/// `PostWorkoutNotifier`, `PostActionsNotifier`) — antes cada uno mantenía su
/// propia lista y ya habían divergido (ADR-CP-006 pedía todos los feeds y
/// shareWorkout invalidaba sólo 2 wrappers).
void invalidateAllFeedProviders(Ref ref) {
  // Estado acumulado — invalidar la family descarta cursor y páginas previas.
  ref.invalidate(feedPaginationProvider);
  // Families subyacentes — acá vive el resultado del query.
  ref.invalidate(feedForFriendsProvider);
  ref.invalidate(feedForGymProvider);
  ref.invalidate(feedPublicProvider);
  // Wrappers — recomputan solos vía las families, pero invalidarlos cubre el
  // caso en que quedaron en error antes de llegar a watchear la family.
  ref.invalidate(myFollowingFeedPaginationKeyProvider);
  ref.invalidate(myGymFeedPaginationKeyProvider);
  ref.invalidate(myFollowingFeedProvider);
  ref.invalidate(myGymFeedProvider);
  // Read models por autor (ACTIVIDAD del perfil) — autoDispose; se invalidan
  // por si un perfil abierto los está renderizando en este momento.
  ref.invalidate(postsByAuthorProvider);
  ref.invalidate(visiblePostsByAuthorProvider);
}
