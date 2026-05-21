import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore;

import '../../../features/profile/data/user_public_profile_repository.dart';
import '../domain/friendship.dart';
import '../domain/friendship_status.dart';

class FriendshipRepository {
  FriendshipRepository({
    required FirebaseFirestore firestore,
    UserPublicProfileRepository? publicProfileRepository,
  })  : _firestore = firestore,
        _publicProfileRepository = publicProfileRepository;

  final FirebaseFirestore _firestore;
  final UserPublicProfileRepository? _publicProfileRepository;

  CollectionReference<Map<String, Object?>> get _friendships =>
      _firestore.collection('friendships');

  /// Creates a pending friendship request between [myUid] and [otherUid].
  /// Idempotent: if a doc already exists for this pair, returns the existing
  /// [Friendship] without writing. Doc ID is always `sortedDocId(myUid, otherUid)`.
  Future<Friendship> request(String myUid, String otherUid) async {
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
      status: FriendshipStatus.pending,
      requesterId: myUid,
      members: [uidA, uidB],
      createdAt: DateTime.now().toUtc(),
    );
    await ref.set(friendship.toJson());
    return friendship;
  }

  /// Accepts a pending friendship. Throws [StateError] if [myUid] is the
  /// original requester (cannot self-accept per SCENARIO-125).
  ///
  /// After accepting, performs a best-effort self-refresh write to
  /// `userPublicProfiles/{myUid}` to increment [followingCount].
  /// If the public profile write fails, it is logged and swallowed —
  /// the primary accept is not affected. (REQ-WRX-004 / ADR-WRS-12)
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

    // Cross-feature: increment followingCount for myUid (best-effort)
    final pubRepo = _publicProfileRepository;
    if (pubRepo == null) return;

    try {
      final profile = await pubRepo.get(myUid);
      final currentFollowing = profile?.followingCount ?? 0;
      await pubRepo.updateCounters(myUid, {
        'followingCount': currentFollowing + 1,
      });
    } catch (e, st) {
      developer.log(
        'FriendshipRepository.accept: failed to increment public profile '
        'counters for $myUid',
        error: e,
        stackTrace: st,
      );
    }
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

  /// Permanently removes a friendship document.
  ///
  /// [myUid] identifies the caller for the self-refresh counter decrement
  /// written to `userPublicProfiles/{myUid}`. The decrement is best-effort:
  /// if the public profile write fails, the friendship is still deleted and
  /// the error is captured via `developer.log` (REQ-WRX-010 / ADR-WRS-12).
  Future<void> delete(String friendshipId, String myUid) async {
    await _friendships.doc(friendshipId).delete();

    // Cross-feature: decrement self-refresh counter for myUid (best-effort)
    final pubRepo = _publicProfileRepository;
    if (pubRepo == null) return;

    try {
      final profile = await pubRepo.get(myUid);
      final currentFollowing = profile?.followingCount ?? 0;
      await pubRepo.updateCounters(myUid, {
        'followingCount':
            (currentFollowing - 1).clamp(0, double.maxFinite).toInt(),
      });
    } catch (e, st) {
      developer.log(
        'FriendshipRepository.delete: failed to decrement public profile '
        'counters for $myUid',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Returns the friendship document between [uidA] and [uidB], or null if none
  /// exists. Single `get()` on `sortedDocId(uidA, uidB)` — pair order doesn't
  /// matter (commutative).
  Future<Friendship?> getByPair(String uidA, String uidB) async {
    final id = Friendship.sortedDocId(uidA, uidB);
    final snap = await _friendships.doc(id).get();
    return _fromDoc(snap);
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
