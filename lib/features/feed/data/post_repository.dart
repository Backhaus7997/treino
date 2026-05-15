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

  Future<List<Post>> byAuthor(String uid) async {
    final snap = await _posts.where('authorUid', isEqualTo: uid).get();
    return snap.docs.map(_fromDoc).whereType<Post>().toList();
  }

  Future<List<Post>> feedPublic() async {
    final snap = await _posts
        .where('privacy', isEqualTo: PostPrivacy.public.toJson())
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
          .get();
      results.addAll(snap.docs.map(_fromDoc).whereType<Post>());
    }

    return results;
  }

  /// Returns gym-privacy posts where `authorGymId == gymId`.
  /// Posts with null `authorGymId` are excluded (user has no gym).
  Future<List<Post>> feedForGym(String gymId) async {
    final snap = await _posts
        .where('privacy', isEqualTo: PostPrivacy.gym.toJson())
        .where('authorGymId', isEqualTo: gymId)
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
