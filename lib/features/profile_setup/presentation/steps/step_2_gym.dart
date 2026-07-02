import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/auth_providers.dart'
    show firebaseAuthProvider;
import '../../../gyms/application/places_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../widgets/gym_search_box.dart';

/// Step 2: single debounced Google Places search box + `kNoGymId`
/// ("OTRO/SIN GYM") option. Mockup: `profile-setup-2.png`.
///
/// Replaces the retired two-step brand→sucursal picker (`GymBrand`,
/// `gymBrandsProvider`, `branchesForBrandProvider`) per spec gym-catalog
/// "Athlete gym selection is a single debounced search".
///
/// Selecting a Google Places suggestion resolves it immediately via
/// `selectGymActionProvider` (server-side `resolveGymPlace` upsert of
/// `gyms/{placeId}` + `UserRepository.update({'gymId': ...})`, which
/// dual-writes `gymName`) — NOT deferred to `ProfileSetupNotifier.submit()`.
/// This guarantees the `gyms/{placeId}` doc exists before submit reads it,
/// since `submit()` only writes the raw `gymId` string and never calls
/// `resolveGymPlace` itself. `users/{uid}` doesn't need to exist yet:
/// `UserRepository.update` uses `set(..., merge: true)`, so this "early"
/// write during onboarding is safe and later merges cleanly with
/// `createIfAbsent` + the final `submit()` write.
///
/// `kNoGymId` needs no resolution — it updates the local draft only.
///
/// Either way, `profileSetupNotifierProvider`'s draft is kept in sync
/// (`updateGymId`) so `submit()`'s `draft.gymId` read and the search box's
/// `selected` highlight stay consistent.
class Step2Gym extends ConsumerWidget {
  const Step2Gym({super.key});

  Future<void> _onGymIdSelected(WidgetRef ref, String? gymId) async {
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    if (gymId == null || gymId == kNoGymId) {
      notifier.updateGymId(kNoGymId);
      return;
    }

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;

    await ref
        .read(selectGymActionProvider.notifier)
        .select(uid: uid, placeId: gymId);
    if (!ref.read(selectGymActionProvider).hasError) {
      notifier.updateGymId(gymId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedGymId = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft.gymId,
      ),
    );

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: GymSearchBox(
          selectedGymId: selectedGymId,
          onGymIdSelected: (gymId) => _onGymIdSelected(ref, gymId),
        ),
      ),
    );
  }
}
