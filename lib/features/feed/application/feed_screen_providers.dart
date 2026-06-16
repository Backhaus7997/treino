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
  if (friendUids.isEmpty) return const <Post>[];

  return await ref.watch(feedForFriendsProvider(friendUidsKey(friendUids)).future);
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
