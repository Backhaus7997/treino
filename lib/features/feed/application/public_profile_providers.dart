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

/// Live stream of the friendship doc (if any) between two uids. Auth-gated:
/// emits null when the viewer isn't signed in. Subscribes via `.snapshots()`
/// so cross-device mutations propagate automatically.
///
/// `autoDispose` bounds the Firestore listener to consumer lifetime — no
/// persistent listener remains for orphaned `(viewerUid, targetUid)` pairs.
final friendshipByPairProvider =
    StreamProvider.family.autoDispose<Friendship?, FriendshipPair>(
  (ref, pair) async* {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      yield null;
      return;
    }
    yield* ref
        .watch(_friendshipRepositoryProvider)
        .watchByPair(pair.viewerUid, pair.targetUid);
  },
);

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
  // Inject the doc id so seed-written posts (which strip `id` from the body
  // and store it only as the doc ID) deserialize correctly — matches
  // PostRepository._fromDoc. Post.id is required with no default.
  final doc = snap.docs.first;
  return Post.fromJson({...doc.data(), 'id': doc.id});
});

/// AsyncNotifier that composes [userPublicProfileProvider] and
/// [friendshipByPairProvider] into a single view-model that the
/// `PublicProfileScreen` watches. Re-runs `build` on every upstream
/// stream emission — live propagation with zero rxdart.
///
/// Sources author identity from `userPublicProfileProvider(targetUid)`.
/// `isSelf` branch skips [friendshipByPairProvider] entirely.
/// REQ-FPS-007, ADR-FPS-002, ADR-FPS-003.
class PublicProfileViewNotifier
    extends AutoDisposeFamilyAsyncNotifier<PublicProfileView, String> {
  @override
  Future<PublicProfileView> build(String targetUid) async {
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

    // ref.watch on a StreamProvider's .future re-runs build on each upstream
    // emission — no ref.listen plumbing needed (ADR-FPS-003).
    final profile =
        await ref.watch(userPublicProfileProvider(targetUid).future);
    final friendship = isSelf
        ? null
        : await ref.watch(
            friendshipByPairProvider(
              (viewerUid: viewerUid, targetUid: targetUid),
            ).future,
          );

    return PublicProfileView(
      authorDisplayName: profile?.displayName ?? 'Anónimo',
      authorAvatarUrl: profile?.avatarUrl,
      authorGymId: profile?.gymId,
      friendship: friendship,
      isSelf: isSelf,
      workoutsCount: profile?.workoutsCount,
      racha: profile?.racha,
      followersCount: profile?.followersCount,
      followingCount: profile?.followingCount,
      // Missing profile → default true (matches UserPublicProfile default);
      // legacy docs without the field decode as public and stay discoverable.
      isPublic: profile?.isProfilePublic ?? true,
    );
  }
}

final publicProfileViewProvider = AsyncNotifierProvider.family
    .autoDispose<PublicProfileViewNotifier, PublicProfileView, String>(
  PublicProfileViewNotifier.new,
);
