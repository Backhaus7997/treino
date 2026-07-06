import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/profile_share_repository.dart';
import '../domain/profile_share.dart';

/// Repository provider — web read-only for Slice 1.
final profileShareRepositoryProvider = Provider<ProfileShareRepository>(
  (ref) => ProfileShareRepository(firestore: ref.watch(firestoreProvider)),
);

/// Watches `profile_shares/{athleteId}` and emits [ProfileShare?].
///
/// Emits `null` when the athlete has not shared their data yet.
/// The family key is [athleteId] — stable, no [DateTime.now()] in the key.
///
/// The stream is lazily disposed when no longer watched (autoDispose).
final profileShareProvider =
    StreamProvider.autoDispose.family<ProfileShare?, String>(
  (ref, athleteId) =>
      ref.watch(profileShareRepositoryProvider).watchForAthlete(athleteId),
);
