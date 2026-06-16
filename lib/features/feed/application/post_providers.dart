import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/post_repository.dart';
import '../domain/post.dart';

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
final postsByAuthorProvider =
    FutureProvider.family<List<Post>, String>((ref, uid) {
  return ref.watch(postRepositoryProvider).byAuthor(uid);
});
