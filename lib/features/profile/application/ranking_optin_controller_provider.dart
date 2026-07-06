import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ranking_optin_controller.dart';
import 'user_providers.dart' show userRepositoryProvider;
import 'user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;

export 'ranking_optin_controller.dart' show RankingOptInControllerBase;

/// Singleton provider exposing [RankingOptInControllerBase] — typed against
/// the abstract base so widget tests can override it with a fake without
/// touching Firestore. See the rankings surface's opt-in CTA/toggle
/// (design `sdd/rankings-v2/design` AD-6/AD-7). `sdd/rankings-integrity`
/// AD-2/AD-9: no longer depends on `sessionRepositoryProvider` — metrics are
/// server-computed now, not backfilled client-side from session history.
final rankingOptInControllerProvider = Provider<RankingOptInControllerBase>(
  (ref) => RankingOptInController(
    publicProfileRepository: ref.watch(userPublicProfileRepositoryProvider),
    userRepository: ref.watch(userRepositoryProvider),
  ),
);
