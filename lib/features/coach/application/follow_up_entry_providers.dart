import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/follow_up_entry_repository.dart';
import '../domain/follow_up_entry.dart';

final followUpEntryRepositoryProvider = Provider<FollowUpEntryRepository>(
  (ref) => FollowUpEntryRepository(firestore: ref.watch(firestoreProvider)),
);

typedef FollowUpEntryKey = ({String trainerId, String athleteId});

/// Stream reactivo de entradas de seguimiento del par PF↔alumno. Ordenadas
/// server-side por `recordedAt DESC` (requiere composite index).
final followUpEntriesProvider =
    StreamProvider.autoDispose.family<List<FollowUpEntry>, FollowUpEntryKey>(
  (ref, key) => ref
      .watch(followUpEntryRepositoryProvider)
      .watch(key.trainerId, key.athleteId),
);
