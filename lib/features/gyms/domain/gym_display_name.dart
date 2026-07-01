import 'gym.dart';

/// Safe fallback helpers for rendering a gym's display name.
///
/// Replaces the retired `feed/domain/gym_name.dart` (`_kGymNames` hardcoded
/// map + `gymNameFromId`). Real names now come from the `gyms/` catalog —
/// [Gym.name] is ALREADY the composed "{brandName} - {branchName}" label
/// (or just the brand name for independent single-branch gyms); see
/// `scripts/seed_gyms.js` and `GymRepository`. There is no separate
/// "compose" step here, only a safe empty-string fallback for the two
/// places a gym can fail to resolve:
///   - DETAIL contexts: `gymByIdProvider` returns `Gym?` — null when the
///     id is unknown/deleted.
///   - LIST contexts: `UserPublicProfile.gymName` is the denormalized
///     `String?` written by `UserRepository.update()` — null/empty when
///     the user has no gym or the id was unresolvable at save time.
///
/// Both helpers never throw — an unresolvable id is a "no gym" UI state,
/// not an error.

/// For DETAIL contexts backed by `gymByIdProvider` (Riverpod-cached lookup
/// by id). Returns the resolved gym's composed name, or `''` when [gym] is
/// `null` (unknown/deleted id — caller hides the subtitle).
String gymDisplayNameFromGym(Gym? gym) => gym?.name ?? '';

/// For LIST/feed contexts reading the already-denormalized
/// `UserPublicProfile.gymName` (no per-row fetch). Returns [gymName] as-is
/// when non-empty, or `''` for `null`/empty (caller hides the subtitle).
String gymDisplayNameFromDenormalized(String? gymName) =>
    (gymName == null || gymName.isEmpty) ? '' : gymName;
