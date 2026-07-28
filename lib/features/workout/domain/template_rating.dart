// ignore: unused_import — Timestamp is used by the generated template_rating.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'template_rating.freezed.dart';
part 'template_rating.g.dart';

/// A community rating left by a user on a published trainer template.
///
/// Stored at `routines/{routineId}/ratings/{userId}` — the doc id IS the
/// rater's uid, so each user holds exactly one rating per template (upsert
/// semantics via [RoutineRepository.upsertTemplateRating]). Aggregated into
/// the parent routine's `ratingAvg`/`ratingsCount` by the
/// `templateRatingAggregate` Cloud Function.
@freezed
class TemplateRating with _$TemplateRating {
  const factory TemplateRating({
    /// Rater uid — duplicated from the doc id so list snapshots can render
    /// without re-deriving it from the snapshot path.
    required String userId,

    /// 1..5 inclusive. Validated by [RoutineRepository] and Firestore rules.
    required int rating,

    /// Optional freeform comment, max 500 chars.
    /// Validated by [RoutineRepository] and Firestore rules.
    String? comment,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
  }) = _TemplateRating;

  factory TemplateRating.fromJson(Map<String, Object?> json) =>
      _$TemplateRatingFromJson(json);
}
