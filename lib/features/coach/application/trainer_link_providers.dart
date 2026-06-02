import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/session_share_repository.dart';
import '../data/trainer_link_repository.dart';
import '../domain/trainer_link.dart';
import '../domain/trainer_link_status.dart';

final trainerLinkRepositoryProvider = Provider<TrainerLinkRepository>(
  (ref) => TrainerLinkRepository(firestore: ref.watch(firestoreProvider)),
);

/// Lista de vínculos donde el usuario actuó como PF.
final linksForTrainerProvider =
    FutureProvider.autoDispose.family<List<TrainerLink>, String>(
  (ref, trainerId) async {
    if (trainerId.isEmpty) return const [];
    return ref.read(trainerLinkRepositoryProvider).listForTrainer(trainerId);
  },
);

/// Lista de vínculos donde el usuario actuó como atleta.
final linksForAthleteProvider =
    FutureProvider.autoDispose.family<List<TrainerLink>, String>(
  (ref, athleteId) async {
    if (athleteId.isEmpty) return const [];
    return ref.read(trainerLinkRepositoryProvider).listForAthlete(athleteId);
  },
);

/// Vínculo activo del atleta actual con su PF, o null si no tiene.
/// Si hay múltiples activos (no debería pasar — un atleta solo se vincula
/// con UN PF a la vez en Etapa 1), devolvemos el más reciente.
final currentAthleteLinkProvider =
    FutureProvider.autoDispose<TrainerLink?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  final links = await ref
      .read(trainerLinkRepositoryProvider)
      .listForAthlete(uid, statuses: {TrainerLinkStatus.active});
  if (links.isEmpty) return null;
  return links.first; // listForAthlete viene ordenado por requestedAt DESC
});

/// Stream real-time de los vínculos del PF actual. Lo consume el dashboard
/// del PF (Etapa 3).
final trainerLinksStreamProvider =
    StreamProvider.autoDispose<List<TrainerLink>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const Stream.empty();
  return ref.read(trainerLinkRepositoryProvider).watchForTrainer(uid);
});

/// Privacy-grant repository — wraps the `session_shares/{athleteId}` doc.
/// Used by the athlete's "Compartir con mi PF" toggle to keep the Firestore
/// security grant in sync with `trainer_links.sharedWithTrainer`.
final sessionShareRepositoryProvider = Provider<SessionShareRepository>(
  (ref) => SessionShareRepository(firestore: ref.watch(firestoreProvider)),
);
