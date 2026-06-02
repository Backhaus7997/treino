import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../data/review_repository.dart';
import '../domain/review.dart';

/// Provides a [ReviewRepository] backed by the shared Firestore instance.
final reviewRepositoryProvider = Provider<ReviewRepository>(
  (ref) => ReviewRepository(firestore: ref.watch(firestoreProvider)),
);

/// Streams the current user's review for a specific link, or null when absent.
///
/// Used by the write flow to determine edit vs. new state.
/// REQ-RV-DATA-003, REQ-RV-WRITE-001. Fase 6 Etapa 7.
final userReviewForLinkProvider =
    StreamProvider.autoDispose.family<Review?, String>(
  (ref, linkId) {
    // linkId is the trainer_links doc id; athleteId comes from the auth user.
    // The caller is responsible for providing the correct linkId.
    // This provider streams the review doc using watchForLink from the repo.
    // The athleteId is embedded in the doc id via Review.idFor, but since
    // watchForLink requires both, callers provide a combined key
    // "linkId:athleteId" as the family argument.
    final parts = linkId.split(':');
    final actualLinkId = parts[0];
    final athleteId = parts.length > 1 ? parts[1] : '';
    return ref
        .watch(reviewRepositoryProvider)
        .watchForLink(actualLinkId, athleteId);
  },
);

/// Streams the most recent reviews for a trainer (up to 10, by createdAt DESC).
///
/// Consumed by the public profile RESEÑAS section.
/// REQ-RV-DATA-005, REQ-RV-DISPLAY-002. Fase 6 Etapa 7.
final trainerReviewsProvider =
    StreamProvider.autoDispose.family<List<Review>, String>(
  (ref, trainerId) =>
      ref.watch(reviewRepositoryProvider).watchForTrainer(trainerId, limit: 10),
);
