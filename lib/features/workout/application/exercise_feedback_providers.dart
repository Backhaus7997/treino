import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/application/trainer_link_providers.dart'
    show sessionShareRepositoryProvider;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/exercise_feedback_repository.dart';
import '../domain/exercise_feedback.dart';

final exerciseFeedbackRepositoryProvider = Provider<ExerciseFeedbackRepository>(
  (ref) => ExerciseFeedbackRepository(firestore: ref.watch(firestoreProvider)),
);

/// Family key shared by the session-scoped feedback providers.
///
/// A record (not a positional tuple) so both fields are named at every call
/// site, matching [coachSessionSetLogsProvider].
typedef SessionFeedbackKey = ({String athleteUid, String sessionId});

/// Live feedback for the athlete's own in-progress session.
///
/// Streams rather than fetches: an entry the athlete just submitted has to
/// appear under the exercise without a manual refresh, since the player never
/// remounts mid-session.
final sessionFeedbackProvider = StreamProvider.autoDispose
    .family<List<ExerciseFeedback>, SessionFeedbackKey>((ref, key) {
  if (key.athleteUid.isEmpty || key.sessionId.isEmpty) {
    return Stream.value(const <ExerciseFeedback>[]);
  }
  return ref.watch(exerciseFeedbackRepositoryProvider).watch(
        uid: key.athleteUid,
        sessionId: key.sessionId,
      );
});

/// One-shot feedback read for the trainer's session view.
///
/// Mirrors [coachSessionSetLogsProvider]: a FutureProvider, autoDispose so the
/// cache is dropped when the expansion tile closes, and short-circuits on an
/// empty key without touching Firestore.
final coachSessionFeedbackProvider = FutureProvider.autoDispose
    .family<List<ExerciseFeedback>, SessionFeedbackKey>((ref, key) async {
  if (key.athleteUid.isEmpty || key.sessionId.isEmpty) {
    return const <ExerciseFeedback>[];
  }
  return ref.watch(exerciseFeedbackRepositoryProvider).list(
        uid: key.athleteUid,
        sessionId: key.sessionId,
      );
});

/// The trainer who can currently read [athleteUid]'s sessions, or null.
///
/// Drives the composer's consent gate. autoDispose keeps it from pinning a
/// stale answer for a whole app session — the athlete may grant the share from
/// the sheet itself and the next open must see it.
final grantedTrainerIdProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, athleteUid) async {
  if (athleteUid.isEmpty) return null;
  return ref.watch(sessionShareRepositoryProvider).grantedTrainerId(athleteUid);
});
