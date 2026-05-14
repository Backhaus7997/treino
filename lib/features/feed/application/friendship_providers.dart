import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/friendship_repository.dart';
import '../domain/friendship.dart';

final friendshipRepositoryProvider = Provider<FriendshipRepository>(
  (ref) => FriendshipRepository(firestore: ref.watch(firestoreProvider)),
);

/// Returns the list of UIDs that [uid] is friends with (status = accepted).
final acceptedFriendsProvider =
    FutureProvider.family<List<String>, String>((ref, uid) {
  return ref.watch(friendshipRepositoryProvider).acceptedFriendsOf(uid);
});

/// Returns pending friendship requests received by [uid] (inbox — requesterId != uid).
final pendingRequestsProvider =
    FutureProvider.family<List<Friendship>, String>((ref, uid) {
  return ref.watch(friendshipRepositoryProvider).pendingRequestsFor(uid);
});
