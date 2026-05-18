import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/session_repository.dart';
import '../domain/session.dart';

final sessionRepositoryProvider = Provider<SessionRepository>(
  (ref) => SessionRepository(firestore: ref.watch(firestoreProvider)),
);

/// Fetches all sessions for [uid], ordered by startedAt descending.
/// Returns an empty list when [uid] is empty/invalid.
final sessionsByUidProvider =
    FutureProvider.family<List<Session>, String>((ref, uid) async {
  if (uid.isEmpty) return const [];
  return ref.watch(sessionRepositoryProvider).listByUid(uid);
});

/// Returns the currently active session for [uid], or null if none.
final activeSessionProvider =
    FutureProvider.family<Session?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  return ref.watch(sessionRepositoryProvider).getActive(uid);
});
