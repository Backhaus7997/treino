import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/post_repository.dart';
import '../domain/post.dart';

final postRepositoryProvider = Provider<PostRepository>(
  (ref) => PostRepository(firestore: ref.watch(firestoreProvider)),
);

/// All public posts, ordered by Firestore default (createdAt desc recommended
/// via index — for MVP returns server order).
final feedPublicProvider = FutureProvider<List<Post>>((ref) {
  return ref.watch(postRepositoryProvider).feedPublic();
});

/// Friends-privacy posts for the given list of friend UIDs.
/// Uses `FutureProvider.family` with the UID list serialized as a
/// space-separated string key (stable for small sets; revisit if sets grow).
final feedForFriendsProvider =
    FutureProvider.family<List<Post>, List<String>>((ref, friendUids) {
  return ref.watch(postRepositoryProvider).feedForFriends(friendUids);
});

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
