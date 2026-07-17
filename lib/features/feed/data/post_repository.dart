import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/post.dart';
import '../domain/post_privacy.dart';

class PostRepository {
  PostRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _posts =>
      _firestore.collection('posts');

  /// Creates a post doc. Reads `users/{uid}.gymId` once to denormalize
  /// `authorGymId`. Returns the persisted post with its assigned id.
  Future<Post> create(Post input) async {
    // Read gymId from the user doc for denormalization (ADR: authorGymId)
    final userSnap =
        await _firestore.collection('users').doc(input.authorUid).get();
    final gymId = userSnap.data()?['gymId'] as String?;

    // If input already has an explicit authorGymId (e.g., from tests), keep it;
    // otherwise use the value from the user doc.
    final resolvedGymId = input.authorGymId ?? gymId;

    final ref = _posts.doc(input.id.isEmpty ? null : input.id);
    final post = input.copyWith(
      id: ref.id,
      authorGymId: resolvedGymId,
    );
    await ref.set(post.toJson());
    return post;
  }

  /// Deletes the post doc at `posts/{postId}`. No-op if it doesn't exist —
  /// Firestore `delete()` does not throw for a missing doc.
  Future<void> delete(String postId) async {
    await _posts.doc(postId).delete();
  }

  /// Updates the editable fields of an existing post: `text`, `privacy`, and
  /// `routineTag`. Author fields, `authorGymId`, `createdAt`, and `id` are
  /// immutable on edit — this writes an explicit partial map (not
  /// `post.toJson()`) so those fields are never clobbered.
  Future<Post> update(Post post) async {
    await _posts.doc(post.id).update({
      'text': post.text,
      'privacy': post.privacy.toJson(),
      'routineTag': post.routineTag?.toJson(),
    });
    return post;
  }

  Future<List<Post>> byAuthor(String uid) async {
    final snap = await _posts.where('authorUid', isEqualTo: uid).get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  /// Posts by [uid] of a single [privacy] tier. QA-FEED-001: a viewer who is
  /// not the author can only read the tiers firestore.rules allows, so the
  /// profile provider must query per tier (not fetch-all-then-filter, which the
  /// enforced read rule now rejects). Two equality filters need no composite
  /// index (zigzag merge); results are sorted by the caller.
  ///
  /// Only for the `public` and `friends` tiers — the `gym` tier must be
  /// constrained by [byAuthorGymTier] so the query never pulls a row the read
  /// rule would reject.
  Future<List<Post>> byAuthorAndPrivacy(String uid, PostPrivacy privacy) async {
    final snap = await _posts
        .where('authorUid', isEqualTo: uid)
        .where('privacy', isEqualTo: privacy.toJson())
        .get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  /// Gym-tier posts by [uid] whose `authorGymId == gymId`. QA-FEED-001: the
  /// read rule only lets a viewer read a gym post when their own gym matches the
  /// post's `authorGymId`. The profile query must therefore be constrained to
  /// the viewer's gym — querying every gym post and filtering client-side would
  /// pull rows authored for other gyms, which the rule rejects, failing the
  /// whole query. Three equality filters need no composite index (zigzag
  /// merge); results are sorted by the caller.
  Future<List<Post>> byAuthorGymTier(String uid, String gymId) async {
    final snap = await _posts
        .where('authorUid', isEqualTo: uid)
        .where('privacy', isEqualTo: PostPrivacy.gym.toJson())
        .where('authorGymId', isEqualTo: gymId)
        .get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  Future<List<Post>> feedPublic() async {
    final snap = await _posts
        .where('privacy', isEqualTo: PostPrivacy.public.toJson())
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  /// Returns friends-privacy posts authored by any of the given UIDs.
  /// Chunks into batches of ≤10 due to Firestore `in` operator limit.
  Future<List<Post>> feedForFriends(List<String> friendUids) async {
    if (friendUids.isEmpty) return const [];

    const chunkSize = 10;
    final results = <Post>[];

    for (var i = 0; i < friendUids.length; i += chunkSize) {
      final chunk = friendUids.sublist(
        i,
        (i + chunkSize).clamp(0, friendUids.length),
      );
      final snap = await _posts
          .where('privacy', isEqualTo: PostPrivacy.friends.toJson())
          .where('authorUid', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .get();
      results.addAll(snap.docs.map(_fromDoc).whereType<Post>());
    }

    // Each chunk is sorted server-side, but the merged list across chunks is
    // not globally ordered — re-sort newest-first client-side.
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  /// Returns gym-privacy posts where `authorGymId == gymId`.
  /// Posts with null `authorGymId` are excluded (user has no gym).
  Future<List<Post>> feedForGym(String gymId) async {
    final snap = await _posts
        .where('privacy', isEqualTo: PostPrivacy.gym.toJson())
        .where('authorGymId', isEqualTo: gymId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  Post? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // Inject snap.id so seed-written docs (which strip `id` from the body
    // and store it only as the doc ID) deserialize correctly. App-created
    // posts already carry `id` in the body via `create()` — this is a no-op
    // override for those.
    return Post.fromJson({...data, 'id': snap.id});
  }
}
