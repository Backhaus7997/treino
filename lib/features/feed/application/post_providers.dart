import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../data/post_repository.dart';
import '../domain/friendship_status.dart';
import '../domain/post.dart';
import '../domain/post_privacy.dart';
import 'public_profile_providers.dart';

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(firestore: ref.watch(firestoreProvider)),
);

/// All public posts, ordered newest-first (createdAt desc) server-side.
/// Requires the posts (privacy, createdAt desc) composite index in
/// firestore.indexes.json.
final feedPublicProvider = FutureProvider<List<Post>>((ref) {
  return ref.watch(postRepositoryProvider).feedPublic();
});

/// Friends-privacy posts for the given set of friend UIDs.
///
/// The family is keyed on a `String` — the UIDs sorted and joined with a single
/// space — rather than `List<String>`. Dart `List` has identity equality, so a
/// list-keyed family would treat every new list instance as a distinct key;
/// `acceptedFriendsProvider` is a stream that emits a fresh `List` on every
/// Firestore snapshot, which would thrash the cache and re-issue the feed query
/// on each emission. A sorted+joined `String` key has value equality and is
/// order-independent, so the cached result is reused across re-emissions.
///
/// Use [friendUidsKey] to build the key from a UID list.
final feedForFriendsProvider =
    FutureProvider.family<List<Post>, String>((ref, friendUidsKey) {
  final friendUids =
      friendUidsKey.isEmpty ? const <String>[] : friendUidsKey.split(' ');
  return ref.watch(postRepositoryProvider).feedForFriends(friendUids);
});

/// Builds a stable, value-equal key for [feedForFriendsProvider] from a list of
/// friend UIDs. Sorts so the key is independent of Firestore emission order.
String friendUidsKey(List<String> friendUids) =>
    (List<String>.from(friendUids)..sort()).join(' ');

/// Gym-privacy posts for the given gym ID.
final feedForGymProvider =
    FutureProvider.family<List<Post>, String>((ref, gymId) {
  return ref.watch(postRepositoryProvider).feedForGym(gymId);
});

/// All posts authored by a given UID.
///
/// `autoDispose` so that when a consumer un-mounts (e.g. the viewer leaves
/// the public profile screen) the future is torn down and the next visit
/// re-issues the underlying `posts.where(authorUid == uid).get()` query
/// instead of serving a stale cached list. Without `autoDispose` a viewer
/// who opened the profile BEFORE the target posted would never see new
/// posts appear on subsequent visits.
final postsByAuthorProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, uid) {
  return ref.watch(postRepositoryProvider).byAuthor(uid);
});

/// Posts authored by [targetUid], visible to the current viewer per each
/// post's [PostPrivacy] rule (Option X):
/// - `public` → always visible
/// - `friends` → visible if the viewer is an accepted follower OR is self
/// - `gym` → visible if viewer.gymId == target.authorGymId OR is self
///
/// Returned newest-first (post_repository.byAuthor returns unordered, we
/// sort here). Empty list when viewer is unauthenticated. Powers the
/// "ACTIVIDAD" tab of another user's public profile screen.
///
/// Client-side filter is safe here because the volume is bounded by uid —
/// no user is expected to have thousands of own posts, and the alternative
/// (three separate parallel queries per privacy tier) would issue more reads
/// than needed while adding complexity to reconcile the timelines.
final visiblePostsByAuthorProvider =
    FutureProvider.autoDispose.family<List<Post>, String>(
  (ref, targetUid) async {
    final viewerAuth = await ref.watch(authStateChangesProvider.future);
    if (viewerAuth == null) return const [];
    final viewerUid = viewerAuth.uid;
    final isSelf = viewerUid == targetUid;

    final all =
        await ref.watch(postsByAuthorProvider(targetUid).future);
    if (all.isEmpty) return const [];

    // Fast paths: viewer is the target user OR every post is public.
    if (isSelf) {
      final sorted = List<Post>.of(all)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    }

    // Relationship signals — only fetched when there is at least one
    // non-public post; keeps the common case cheap.
    final needsRelationships =
        all.any((p) => p.privacy != PostPrivacy.public);
    var isAcceptedFriend = false;
    String? viewerGymId;
    if (needsRelationships) {
      final friendship = await ref.watch(
        friendshipByPairProvider(
          (viewerUid: viewerUid, targetUid: targetUid),
        ).future,
      );
      isAcceptedFriend = friendship?.status == FriendshipStatus.accepted;
      final viewerProfile =
          await ref.watch(userPublicProfileProvider(viewerUid).future);
      viewerGymId = viewerProfile?.gymId;
    }

    final visible = <Post>[];
    for (final post in all) {
      switch (post.privacy) {
        case PostPrivacy.public:
          visible.add(post);
        case PostPrivacy.friends:
          if (isAcceptedFriend) visible.add(post);
        case PostPrivacy.gym:
          if (viewerGymId != null &&
              post.authorGymId != null &&
              viewerGymId == post.authorGymId) {
            visible.add(post);
          }
      }
    }
    visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  },
);
