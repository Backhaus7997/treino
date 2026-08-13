import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../domain/template_rating.dart';
import 'routine_providers.dart';

/// Every rating left on a published template, newest first (capped by the
/// repository). Drives the comment list and the "sin calificaciones" empty
/// state of the published-template detail.
final templateRatingsProvider =
    StreamProvider.autoDispose.family<List<TemplateRating>, String>(
  (ref, routineId) {
    return ref.watch(routineRepositoryProvider).watchTemplateRatings(routineId);
  },
);

/// The signed-in user's own rating on a template — `null` while they have
/// not rated it. Pre-populates the editable star input.
///
/// Resolves to `null` (never an error) when signed out: the detail screen
/// hides the input in that case rather than showing a broken control.
final myTemplateRatingProvider =
    StreamProvider.autoDispose.family<TemplateRating?, String>(
  (ref, routineId) async* {
    final user = await ref.watch(authStateChangesProvider.future);
    if (user == null) {
      yield null;
      return;
    }
    yield* ref.watch(routineRepositoryProvider).watchMyTemplateRating(
          routineId: routineId,
          userId: user.uid,
        );
  },
);
