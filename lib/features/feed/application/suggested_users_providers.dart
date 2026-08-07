import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/user_public_profile.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'follow_providers.dart' show followRepositoryProvider;

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

/// Gente de [gymId] que todavía no tiene NINGUNA arista con el usuario actual.
///
/// La key de la family es a propósito un [String]: una key de tipo colección
/// usa igualdad por identidad y erraría el cache de Riverpod todo el tiempo.
///
/// La exclusión es por PRESENCIA de arista, en cualquier dirección y estado —
/// `allOf` resuelve las dos direcciones con un solo `array-contains` sobre
/// `members`. Deliberadamente NO es direccional: sugerir a alguien que ya te
/// mandó una solicitud sería ofrecerte gente que ya está en tu inbox.
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

    final edges = await ref.watch(followRepositoryProvider).allOf(currentUid);
    final excludedUids = edges
        .expand((edge) => edge.members)
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
