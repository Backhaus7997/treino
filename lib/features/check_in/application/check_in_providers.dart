import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/check_in_repository.dart';
import '../domain/check_in.dart';

/// Singleton provider for [CheckInRepository].
final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(firestore: ref.watch(firestoreProvider)),
);

/// Returns today's check-in for the current user, or null if not checked in
/// today. Auth-gated: returns null when unauthenticated.
///
/// autoDispose: re-fetched on FeedScreen remount (tab switch, app resume).
final todayCheckInProvider = FutureProvider.autoDispose<CheckIn?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ref.watch(checkInRepositoryProvider).getTodayForUser(uid);
});

/// AsyncNotifier wrapping the action of confirming a check-in. Exposes a
/// single `confirm()` method consumed by the dialog's buttons.
///
/// REQ-WRC-007, REQ-WRC-008: both buttons call `confirm()` with different
/// gymId/gymName values — the notifier delegates to the repository.
final checkInNotifierProvider =
    AsyncNotifierProvider<CheckInNotifier, CheckIn?>(CheckInNotifier.new);

class CheckInNotifier extends AsyncNotifier<CheckIn?> {
  @override
  Future<CheckIn?> build() async => null;

  Future<void> confirm({String? gymId, String? gymName}) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // The kNoGymId sentinel ('no-gym') is a valid profile value meaning the
    // user opted out of a gym — it must NOT be recorded as an in-gym check-in.
    // Treat null/empty/sentinel as not-in-gym and null out gym fields so the
    // stored record stays consistent (no inGym=true pointing at 'no-gym').
    final inGym = gymId != null && gymId.isNotEmpty && gymId != kNoGymId;

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final result =
          await ref.read(checkInRepositoryProvider).createTodayCheckIn(
                uid,
                inGym: inGym,
                gymId: inGym ? gymId : null,
                gymName: inGym ? gymName : null,
              );
      // Invalidate so FeedScreen re-evaluates on next mount.
      ref.invalidate(todayCheckInProvider);
      return result;
    });
  }
}
