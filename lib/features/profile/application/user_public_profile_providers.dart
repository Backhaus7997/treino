import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../data/user_public_profile_repository.dart';
import '../domain/user_public_profile.dart';
import 'user_providers.dart' show firestoreProvider;

/// Singleton provider exposing [UserPublicProfileRepository].
final userPublicProfileRepositoryProvider =
    Provider<UserPublicProfileRepository>(
  (ref) => UserPublicProfileRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

/// Fetches a single public profile by [uid]. Auth-gated: returns `null` when
/// the viewer is not authenticated (defensive — profile routes are already
/// auth-gated by the router). Returns `null` also when the document does not
/// exist (e.g. pre-backfill user).
///
/// REQ-UPP-007, REQ-UPP-008.
final userPublicProfileProvider =
    FutureProvider.family<UserPublicProfile?, String>((ref, uid) async {
  final auth = await ref.watch(authStateChangesProvider.future);
  if (auth == null) return null;

  return ref.watch(userPublicProfileRepositoryProvider).get(uid);
});
