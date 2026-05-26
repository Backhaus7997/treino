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

/// Live stream of a single public profile by [uid]. Auth-gated: emits `null`
/// when the viewer is not authenticated. Emits `null` also when the document
/// does not exist (e.g. pre-backfill user). Drop-in replacement for the
/// former FutureProvider.family — same name, same `AsyncValue<UserPublicProfile?>`
/// consumer surface. `autoDispose` bounds the Firestore listener to consumer
/// lifetime. REQ-FPS-006, ADR-FPS-001.
final userPublicProfileProvider =
    StreamProvider.family.autoDispose<UserPublicProfile?, String>(
  (ref, uid) async* {
    final auth = await ref.watch(authStateChangesProvider.future);
    if (auth == null) {
      yield null;
      return;
    }
    yield* ref.watch(userPublicProfileRepositoryProvider).watch(uid);
  },
);
