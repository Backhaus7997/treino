import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../domain/friendship.dart';
import '../domain/friendship_status.dart';

class FriendshipRepository {
  FriendshipRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> get _friendships =>
      _firestore.collection('friendships');

  /// Creates a friendship request between [myUid] and [otherUid].
  ///
  /// When [otherIsPublic] is `true`, the target user has a public profile
  /// (Instagram-style): the friendship is created directly as `accepted`
  /// and both counter denormalizations happen in the same call.
  ///
  /// When `false` (default), the friendship is created as `pending` and
  /// the target must call [accept] to complete the flow.
  ///
  /// Idempotent: if a doc already exists for this pair, returns the existing
  /// [Friendship] without writing. Doc ID is always `sortedDocId(myUid, otherUid)`.
  Future<Friendship> request(
    String myUid,
    String otherUid, {
    bool otherIsPublic = false,
  }) async {
    final docId = Friendship.sortedDocId(myUid, otherUid);
    final ref = _friendships.doc(docId);

    final snap = await ref.get();
    if (snap.exists) {
      return _fromDoc(snap)!;
    }

    final uidA = myUid.compareTo(otherUid) <= 0 ? myUid : otherUid;
    final uidB = myUid.compareTo(otherUid) <= 0 ? otherUid : myUid;

    final friendship = Friendship(
      id: docId,
      uidA: uidA,
      uidB: uidB,
      status: otherIsPublic
          ? FriendshipStatus.accepted
          : FriendshipStatus.pending,
      requesterId: myUid,
      members: [uidA, uidB],
      createdAt: DateTime.now().toUtc(),
    );
    await ref.set(friendship.toJson());

    // Follow counters (followingCount / followersCount) are maintained
    // server-side by the `maintainFollowCounters` Cloud Function, which fires
    // on this write. The client no longer touches them — the previous
    // best-effort client increments drifted on failure and were asymmetric on
    // unfollow (phantom followers). See W-SOCIAL-COUNTERS-01.

    return friendship;
  }

  /// Accepts a pending friendship. Throws [StateError] if [myUid] is the
  /// original requester (cannot self-accept per SCENARIO-125).
  ///
  /// Follow counters are maintained server-side by the
  /// `maintainFollowCounters` Cloud Function on the resulting
  /// `pending → accepted` write — the client no longer touches them
  /// (W-SOCIAL-COUNTERS-01).
  Future<void> accept(String friendshipId, String myUid) async {
    final snap = await _friendships.doc(friendshipId).get();
    if (!snap.exists) {
      throw StateError('Friendship $friendshipId not found');
    }
    final data = snap.data()!;
    final requesterId = data['requesterId'] as String;
    if (requesterId == myUid) {
      throw StateError('Requester cannot self-accept a friendship request');
    }
    await _friendships
        .doc(friendshipId)
        .update({'status': FriendshipStatus.accepted.toJson()});
  }

  /// Returns the list of UIDs that [uid] is friends with (status = accepted).
  Future<List<String>> acceptedFriendsOf(String uid) async {
    final snap = await _friendships
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: FriendshipStatus.accepted.toJson())
        .get();
    return snap.docs
        .map((doc) {
          final data = doc.data();
          final members = (data['members'] as List).cast<String>();
          return members.firstWhere((m) => m != uid, orElse: () => '');
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  /// Live stream of pending friendships where [uid] is the recipient
  /// (not the requester). This is the inbox feed for the friend-requests
  /// inbox screen. Emits an empty list when none exist.
  ///
  /// Same shape as [pendingRequestsFor], but uses `.snapshots()` so the
  /// inbox auto-prunes rows when `accept` or `delete` commits without
  /// requiring manual provider invalidation.
  Stream<List<Friendship>> watchPendingRequestsFor(String uid) {
    return _friendships
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: FriendshipStatus.pending.toJson())
        .snapshots()
        .map((snap) => snap.docs
            .map(_fromDoc)
            .whereType<Friendship>()
            .where((f) => f.requesterId != uid)
            .toList());
  }

  /// Returns pending friendships where [uid] is the recipient (not the requester).
  /// This is the inbox: requests received by [uid] that haven't been acted on.
  Future<List<Friendship>> pendingRequestsFor(String uid) async {
    final snap = await _friendships
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: FriendshipStatus.pending.toJson())
        .get();
    final all = snap.docs.map(_fromDoc).whereType<Friendship>().toList();
    return all.where((f) => f.requesterId != uid).toList();
  }

  /// Permanently removes a friendship document (unfollow / cancel request).
  ///
  /// [myUid] is kept in the signature for call-site clarity and future use.
  /// Follow counters are decremented server-side by the
  /// `maintainFollowCounters` Cloud Function when an `accepted` friendship is
  /// deleted — and, unlike the old client path, it decrements BOTH sides
  /// (no phantom follower). Deleting a `pending` doc is a counter no-op.
  /// (W-SOCIAL-COUNTERS-01)
  Future<void> delete(String friendshipId, String myUid) async {
    await _friendships.doc(friendshipId).delete();
  }

  /// Returns the friendship document between [uidA] and [uidB], or null if none
  /// exists. Single `get()` on `sortedDocId(uidA, uidB)` — pair order doesn't
  /// matter (commutative).
  Future<Friendship?> getByPair(String uidA, String uidB) async {
    final id = Friendship.sortedDocId(uidA, uidB);
    final snap = await _friendships.doc(id).get();
    return _fromDoc(snap);
  }

  /// Live stream of the friendship doc between [uidA] and [uidB], or null when
  /// no doc exists. Subscribes to `friendships/{sortedDocId(uidA, uidB)}` via
  /// `.snapshots()`. Mirrors [getByPair] but streamed.
  Stream<Friendship?> watchByPair(String uidA, String uidB) {
    final id = Friendship.sortedDocId(uidA, uidB);
    return _friendships.doc(id).snapshots().map(_fromDoc);
  }

  /// Live stream of UIDs that [uid] is friends with (status == accepted).
  /// Query shape is IDENTICAL to [acceptedFriendsOf] — same composite index.
  Stream<List<String>> watchAcceptedFriendsOf(String uid) {
    return _friendships
        .where('members', arrayContains: uid)
        .where('status', isEqualTo: FriendshipStatus.accepted.toJson())
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) {
              final members = (doc.data()['members'] as List).cast<String>();
              return members.firstWhere((m) => m != uid, orElse: () => '');
            })
            .where((m) => m.isNotEmpty)
            .toList());
  }

  Friendship? _fromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // Inject snap.id so manually-created docs (e.g. Firestore Console)
    // deserialize correctly even if they omit the `id` field from the body.
    // App-created friendships already carry `id` via `request()` toJson().
    return Friendship.fromJson({...data, 'id': snap.id});
  }
}
