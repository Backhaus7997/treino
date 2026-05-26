import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/friendship_repository.dart';
import '../domain/friendship.dart';

final friendshipRepositoryProvider = Provider<FriendshipRepository>(
  (ref) => FriendshipRepository(firestore: ref.watch(firestoreProvider)),
);

/// Live stream of UIDs that [uid] is friends with (status = accepted).
/// Drop-in replacement for the former FutureProvider.family — same name,
/// same `AsyncValue<List<String>>` consumer surface. `autoDispose` bounds
/// the Firestore listener to consumer lifetime. REQ-FPS-005, ADR-FPS-001.
final acceptedFriendsProvider =
    StreamProvider.family.autoDispose<List<String>, String>((ref, uid) {
  return ref.watch(friendshipRepositoryProvider).watchAcceptedFriendsOf(uid);
});

// `pendingRequestsProvider` (Future variant) removed 2026-05-26 per SDD
// `feed-providers-stream-conversion` — superseded by `pendingRequestsStreamProvider`.
// Zero consumers confirmed by explore phase. Any file importing and using
// `pendingRequestsProvider` WILL fail to compile — "Undefined name" error.

/// Live stream of pending friendship requests received by [uid]
/// (status=pending, requesterId != uid). Backs the inbox screen.
///
/// `autoDispose` because the inbox is screen-scoped — no need to hold a
/// Firestore listener open when the user is on another tab.
final pendingRequestsStreamProvider =
    StreamProvider.family.autoDispose<List<Friendship>, String>((ref, uid) {
  return ref.watch(friendshipRepositoryProvider).watchPendingRequestsFor(uid);
});

/// Count of pending requests received by [uid]. Derived synchronously from
/// [pendingRequestsStreamProvider] — returns 0 during loading/error so the
/// Profile tile renders "(0)" without flicker.
///
/// `autoDispose` matches the upstream stream provider's lifecycle.
final pendingRequestCountProvider =
    Provider.family.autoDispose<int, String>((ref, uid) {
  return ref.watch(pendingRequestsStreamProvider(uid)).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});
