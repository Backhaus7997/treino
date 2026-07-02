import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart'
    show sessionRepositoryProvider;
import 'ranking_optin_controller.dart';
import 'user_providers.dart' show userRepositoryProvider;
import 'user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;

export 'ranking_optin_controller.dart' show RankingOptInControllerBase;

/// Singleton provider exposing [RankingOptInControllerBase] — typed against
/// the abstract base so widget tests can override it with a fake without
/// touching Firestore. See the rankings surface's opt-in CTA/toggle
/// (design `sdd/rankings-v2/design` AD-6/AD-7).
final rankingOptInControllerProvider = Provider<RankingOptInControllerBase>(
  (ref) => RankingOptInController(
    sessionRepository: ref.watch(sessionRepositoryProvider),
    publicProfileRepository: ref.watch(userPublicProfileRepositoryProvider),
    userRepository: ref.watch(userRepositoryProvider),
  ),
);
