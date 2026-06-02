import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/review_repository.dart';
import '../domain/review.dart';
import 'review_providers.dart';

/// Family argument for [reviewNotifierProvider]. Groups linkId + trainerId +
/// athleteId as a single equatable key so Riverpod's family cache works
/// correctly.
///
/// Fase 6 Etapa 7.
class ReviewNotifierArgs {
  const ReviewNotifierArgs({
    required this.linkId,
    required this.trainerId,
    required this.athleteId,
  });

  final String linkId;
  final String trainerId;
  final String athleteId;

  @override
  bool operator ==(Object other) =>
      other is ReviewNotifierArgs &&
      other.linkId == linkId &&
      other.trainerId == trainerId &&
      other.athleteId == athleteId;

  @override
  int get hashCode => Object.hash(linkId, trainerId, athleteId);
}

/// Manages the submit lifecycle for creating or editing a review.
///
/// Validates input before calling the repository, transitions through
/// AsyncLoading → AsyncData(null) on success, or AsyncError on failure.
/// REQ-RV-WRITE-001, REQ-RV-WRITE-002. Fase 6 Etapa 7.
class ReviewNotifier
    extends FamilyAsyncNotifier<void, ReviewNotifierArgs> {
  late ReviewNotifierArgs _args;

  @override
  Future<void> build(ReviewNotifierArgs arg) async {
    _args = arg;
  }

  ReviewRepository get _repo => ref.read(reviewRepositoryProvider);

  /// Submits a new or updated review.
  ///
  /// Validates:
  /// - [rating] must be 1..5 inclusive (throws [ArgumentError] otherwise).
  /// - [comment] must be at most 500 characters (throws [ArgumentError] otherwise).
  Future<void> submit({
    required int rating,
    String? comment,
    Review? existing,
  }) async {
    // Validate BEFORE any async gap so the ArgumentError is synchronous.
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Must be between 1 and 5');
    }
    if (comment != null && comment.length > 500) {
      throw ArgumentError.value(
          comment, 'comment', 'Must be at most 500 characters');
    }

    final now = DateTime.now().toUtc();
    final review = Review(
      id: Review.idFor(_args.linkId, _args.athleteId),
      linkId: _args.linkId,
      athleteId: _args.athleteId,
      trainerId: _args.trainerId,
      rating: rating,
      comment: comment,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repo.upsert(review));
  }
}

/// Provides [ReviewNotifier] as a family keyed by [ReviewNotifierArgs].
///
/// Usage:
/// ```dart
/// ref.read(
///   reviewNotifierProvider(
///     ReviewNotifierArgs(linkId: id, trainerId: tid, athleteId: aid)
///   ).notifier,
/// ).submit(rating: 4, comment: 'Great!');
/// ```
///
/// REQ-RV-WRITE-002. Fase 6 Etapa 7.
final reviewNotifierProvider =
    AsyncNotifierProvider.family<ReviewNotifier, void, ReviewNotifierArgs>(
  ReviewNotifier.new,
);
