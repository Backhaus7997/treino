import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/user_public_profile.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'friendship_providers.dart' show friendshipRepositoryProvider;

const int kSuggestedUsersLimit = 20;
const int kSuggestedUsersPageSize = 8;
const int _kSuggestedUsersPostCadence = 10;

List<UserPublicProfile> suggestedUsersPage(
  List<UserPublicProfile> candidates,
  int pageIndex,
) {
  if (pageIndex < 0) return const [];
  return candidates
      .skip(pageIndex * kSuggestedUsersPageSize)
      .take(kSuggestedUsersPageSize)
      .toList(growable: false);
}

List<UserPublicProfile> suggestedUsersAfterPost(
  List<UserPublicProfile> candidates,
  int postIndex,
) {
  if (postIndex < 0 || (postIndex + 1) % _kSuggestedUsersPostCadence != 0) {
    return const [];
  }

  final pageIndex = (postIndex + 1) ~/ _kSuggestedUsersPostCadence - 1;
  return suggestedUsersPage(candidates, pageIndex);
}

/// People from [gymId] who have no friendship document with the current user.
///
/// The family key is deliberately a [String]: collection-valued family keys
/// use identity equality and would continually miss Riverpod's cache.
///
/// Any friendship document excludes its other member. Loading all relationships
/// in one query avoids a per-candidate lookup while still excluding `accepted`
/// and `pending` friendships regardless of request direction.
final suggestedUsersProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) async {
    final currentUid = ref.watch(currentUidProvider);
    if (currentUid == null || gymId.isEmpty || gymId == kNoGymId) {
      return const [];
    }

    final snapshot = await ref
        .watch(firestoreProvider)
        .collection('userPublicProfiles')
        .where('gymId', isEqualTo: gymId)
        .get();

    final friendships =
        await ref.watch(friendshipRepositoryProvider).allOf(currentUid);
    final excludedUids = friendships
        .expand((friendship) => friendship.members)
        .where((uid) => uid != currentUid)
        .toSet();

    final candidates = snapshot.docs
        .map((doc) => UserPublicProfile.fromJson(doc.data()))
        .where(
          (profile) =>
              profile.uid != currentUid && !excludedUids.contains(profile.uid),
        )
        .toList()
      ..sort((a, b) {
        final aName = a.displayNameLowercase ?? a.displayName ?? '';
        final bName = b.displayNameLowercase ?? b.displayName ?? '';
        final byName = aName.compareTo(bName);
        return byName != 0 ? byName : a.uid.compareTo(b.uid);
      });

    return candidates.take(kSuggestedUsersLimit).toList();
  },
);
