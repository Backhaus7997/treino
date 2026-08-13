import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../domain/post.dart';
import '../domain/post_page.dart';
import '../domain/post_privacy.dart';

class PostRepository {
  PostRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _posts =>
      _firestore.collection('posts');

  /// Allocates a post doc id client-side WITHOUT writing anything. For flows
  /// that need the id before the doc exists — the post photo uploads to
  /// `postPhotos/{uid}/{postId}.{ext}` first, then `create()` persists the
  /// doc under this same id.
  String newPostId() => _posts.doc().id;

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

  /// Watches a single post so reaction-count updates are reflected without a
  /// manual refresh. A missing document and a malformed document both degrade
  /// to `null`; Firestore errors (including permission-denied) remain stream
  /// errors so the presentation layer can decide how to render them.
  Stream<Post?> watchById(String postId) {
    return _posts.doc(postId).snapshots().map(_fromDoc);
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

  Future<PostPage> feedPublic({int limit = 20, DateTime? after}) async {
    var query = _posts.where('privacy', isEqualTo: PostPrivacy.public.toJson());
    if (after != null) {
      query = query.where(
        'createdAt',
        isLessThan: Timestamp.fromDate(after),
      );
    }
    final snap =
        await query.orderBy('createdAt', descending: true).limit(limit).get();
    return _pageFromSnapshot(
      posts: snap.docs.map(_fromDoc).whereType<Post>().toList(),
      fetchedDocumentCount: snap.docs.length,
      limit: limit,
    );
  }

  /// Returns friends-privacy posts authored by any of the given UIDs.
  /// Chunks into batches of ≤10 due to Firestore `in` operator limit.
  Future<PostPage> feedForFriends(
    List<String> friendUids, {
    int limit = 20,
    DateTime? after,
  }) async {
    if (friendUids.isEmpty) {
      return const PostPage(
        posts: [],
        nextCursor: null,
        hasMore: false,
      );
    }

    const chunkSize = 10;
    final results = <Post>[];
    var chunkReachedLimit = false;

    for (var i = 0; i < friendUids.length; i += chunkSize) {
      final chunk = friendUids.sublist(
        i,
        (i + chunkSize).clamp(0, friendUids.length),
      );
      var query = _posts
          .where('privacy', isEqualTo: PostPrivacy.followers.toJson())
          .where('authorUid', whereIn: chunk);
      if (after != null) {
        query = query.where(
          'createdAt',
          isLessThan: Timestamp.fromDate(after),
        );
      }
      final snap =
          await query.orderBy('createdAt', descending: true).limit(limit).get();
      chunkReachedLimit = chunkReachedLimit || snap.docs.length == limit;
      results.addAll(snap.docs.map(_fromDoc).whereType<Post>());
    }

    // Each chunk is sorted server-side, but the merged list across chunks is
    // not globally ordered — re-sort newest-first client-side.
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final mergedCount = results.length;
    final posts = results.take(limit).toList();
    // See [_pageFromSnapshot] for the strict DateTime cursor trade-off. The
    // follow-up accumulator must deduplicate pages by post.id.
    return PostPage(
      posts: posts,
      nextCursor: posts.isEmpty ? null : posts.last.createdAt,
      hasMore: mergedCount > limit || chunkReachedLimit,
    );
  }

  /// Returns gym-privacy posts where `authorGymId == gymId`.
  /// Posts with null `authorGymId` are excluded (user has no gym).
  Future<PostPage> feedForGym(
    String gymId, {
    int limit = 20,
    DateTime? after,
  }) async {
    var query = _posts
        .where('privacy', isEqualTo: PostPrivacy.gym.toJson())
        .where('authorGymId', isEqualTo: gymId);
    if (after != null) {
      query = query.where(
        'createdAt',
        isLessThan: Timestamp.fromDate(after),
      );
    }
    final snap =
        await query.orderBy('createdAt', descending: true).limit(limit).get();
    return _pageFromSnapshot(
      posts: snap.docs.map(_fromDoc).whereType<Post>().toList(),
      fetchedDocumentCount: snap.docs.length,
      limit: limit,
    );
  }

  PostPage _pageFromSnapshot({
    required List<Post> posts,
    required int fetchedDocumentCount,
    required int limit,
  }) {
    // The DateTime-only cursor deliberately uses a strict range. Two posts
    // with the exact same Firestore microsecond timestamp could therefore be
    // split across pages and one skipped. This keeps cursors portable across
    // the independent friends-feed chunk queries; page accumulation must
    // deduplicate by post.id when it is added in the follow-up pagination task.
    return PostPage(
      posts: posts,
      nextCursor: posts.isEmpty ? null : posts.last.createdAt,
      hasMore: fetchedDocumentCount == limit,
    );
  }

  Post? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // Inject snap.id so seed-written docs (which strip `id` from the body
    // and store it only as the doc ID) deserialize correctly. App-created
    // posts already carry `id` in the body via `create()` — this is a no-op
    // override for those.
    try {
      return Post.fromJson({...data, 'id': snap.id});
    } catch (_) {
      // A malformed doc (hand-crafted via SDK — rules only validate the
      // outer shape) must degrade to a skipped row, never kill the whole
      // feed query: every caller pipes through `.whereType<Post>()`.
      return null;
    }
  }
}
