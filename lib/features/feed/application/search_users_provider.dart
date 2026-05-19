import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/user_public_profile.dart';

/// Minimum number of characters required to trigger a search query.
/// Shared between the provider (defense-in-depth) and the screen (UX).
const int kSearchMinChars = 2;

/// `FutureProvider.autoDispose.family` keyed on the lowercased query string.
///
/// `autoDispose` is required because the family key (query) grows unbounded as
/// the user types — each keystroke produces a new key. AutoDispose drops
/// unused entries. Debounce lives in the screen (Timer), not here, so this
/// provider stays pure and cacheable.
///
/// Normalization: the query is lowercased INSIDE this provider (ADR per spec
/// Risk 3 resolution). Callers may pass raw user input; the provider normalizes
/// before delegating to the repository.
///
/// Guard: returns empty list immediately if `query.trim().length < kSearchMinChars`
/// without calling the repository (REQ-UPS-006, REQ-UPS-007, SCENARIO-276..277).
///
/// Privacy: delegates ONLY to [userPublicProfileRepositoryProvider] — never
/// to [userRepositoryProvider]. No private fields accessed (REQ-UPS-017..018).
final searchUsersProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, query) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.length < kSearchMinChars) return const [];
    return ref
        .read(userPublicProfileRepositoryProvider)
        .searchByDisplayName(trimmed);
  },
);
