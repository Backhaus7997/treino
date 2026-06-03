import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/athlete_note_repository.dart';
import '../domain/athlete_note.dart';

final athleteNoteRepositoryProvider = Provider<AthleteNoteRepository>(
  (ref) => AthleteNoteRepository(firestore: ref.watch(firestoreProvider)),
);

typedef AthleteNoteKey = ({String trainerId, String athleteId});

final athleteNoteProvider =
    StreamProvider.autoDispose.family<AthleteNote?, AthleteNoteKey>(
  (ref, key) => ref
      .watch(athleteNoteRepositoryProvider)
      .watch(key.trainerId, key.athleteId),
);
