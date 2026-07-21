import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../domain/feed_segment.dart';
import '../domain/post.dart';
import 'friendship_providers.dart';
import 'post_providers.dart';

final feedSegmentProvider = StateProvider<FeedSegment>(
  (ref) => FeedSegment.amigos,
);

final myFriendsFeedProvider = FutureProvider<List<Post>>((ref) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return const <Post>[];

  final friendUids = await ref.watch(acceptedFriendsProvider(auth.uid).future);
  // QA-FEED-003: incluir el propio uid para que los posts AMIGOS del autor
  // aparezcan en su feed AMIGOS (consistente con MI GYM / PÚBLICO, donde los
  // propios sí se ven). Sin esto, el autor publica y no ve nada. No hay
  // early-return por amigos vacíos: un usuario sin amigos igual debe ver sus
  // propios posts privacy=friends. La regla de posts ya permite leer los
  // propios (request.auth.uid == authorUid), así que la query no falla.
  final authorUids = <String>{...friendUids, auth.uid}.toList();
  return await ref.watch(feedForFriendsProvider(friendUidsKey(authorUids)).future);
});

/// Returns the gym-privacy feed for the current user's gym.
///
/// - `null`  = user has no gym (gymId is null on their profile)
/// - `[]`    = user belongs to a gym but it has no posts yet
/// - `[...]` = gym posts, newest first
///
/// Mirrors [myFriendsFeedProvider] in semantics.
final myGymFeedProvider = FutureProvider<List<Post>?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final gymId = profile?.gymId;
  if (gymId == null) return null;
  return ref.watch(feedForGymProvider(gymId).future);
});
