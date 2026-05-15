import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
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

  return await ref.watch(feedForFriendsProvider(friendUids).future);
});
