import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../data/friendship_repository.dart';
import '../domain/friendship.dart';
import '../domain/post.dart';
import '../domain/public_profile_view.dart';

/// Stable record key for the `friendshipByPairProvider.family`. Riverpod
/// requires the family parameter to be hashable; named records satisfy this.
typedef FriendshipPair = ({String viewerUid, String targetUid});

final _friendshipRepositoryProvider = Provider<FriendshipRepository>(
  (ref) => FriendshipRepository(firestore: ref.watch(firestoreProvider)),
);

/// Returns the friendship doc (if any) between two uids. Auth-gated: returns
/// null when the viewer isn't signed in. Reads exactly 1 doc via the
/// deterministic `sortedDocId(uidA, uidB)`.
final friendshipByPairProvider =
    FutureProvider.family<Friendship?, FriendshipPair>((ref, pair) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;
  return ref
      .watch(_friendshipRepositoryProvider)
      .getByPair(pair.viewerUid, pair.targetUid);
});

/// Returns the most-recent `Post` authored by [targetUid], or null if the
/// target has never posted. Used to extract denormalized author fields
/// (displayName, avatarUrl, gymId) for the public profile screen.
///
/// Auth-gated: returns null when unauthenticated (route is auth-gated anyway,
/// but defensive null avoids leaking data on race conditions).
final firstPostByAuthorProvider =
    FutureProvider.family<Post?, String>((ref, targetUid) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;

  final firestore = ref.watch(firestoreProvider);
  final snap = await firestore
      .collection('posts')
      .where('authorUid', isEqualTo: targetUid)
      .orderBy('createdAt', descending: true)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return null;
  return Post.fromJson(snap.docs.first.data());
});

/// Composes [userPublicProfileProvider] + [friendshipByPairProvider] into a
/// single view-model the `PublicProfileScreen` watches. Resolves:
///   - `authorDisplayName` (`'Anónimo'` fallback when no public profile doc)
///   - `authorAvatarUrl` / `authorGymId` (from userPublicProfiles; null if none)
///   - `friendship` (null on self-visit or if no friendship doc exists)
///   - `isSelf` flag for the view layer to hide SEGUIR/MENSAJE buttons.
///
/// Sources author identity from `userPublicProfileProvider(targetUid)` — NOT
/// from `firstPostByAuthorProvider`. REQ-UPP-017, REQ-UPP-018.
final publicProfileViewProvider =
    FutureProvider.family<PublicProfileView, String>((ref, targetUid) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) {
    return const PublicProfileView(
      authorDisplayName: 'Anónimo',
      authorAvatarUrl: null,
      authorGymId: null,
      friendship: null,
      isSelf: false,
    );
  }

  final viewerUid = auth.uid;
  final isSelf = viewerUid == targetUid;

  // Parallel reads. Skip the friendship lookup entirely on self-visit.
  final publicProfileFuture =
      ref.watch(userPublicProfileProvider(targetUid).future);
  final friendshipFuture = isSelf
      ? Future<Friendship?>.value(null)
      : ref.watch(friendshipByPairProvider(
          (viewerUid: viewerUid, targetUid: targetUid),
        ).future);

  final publicProfile = await publicProfileFuture;
  final friendship = await friendshipFuture;

  return PublicProfileView(
    authorDisplayName: publicProfile?.displayName ?? 'Anónimo',
    authorAvatarUrl: publicProfile?.avatarUrl,
    authorGymId: publicProfile?.gymId,
    friendship: friendship,
    isSelf: isSelf,
  );
});
