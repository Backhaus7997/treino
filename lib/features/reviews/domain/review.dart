// ignore: unused_import — Timestamp is used by the generated review.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'review.freezed.dart';
part 'review.g.dart';

/// A trainer review left by an athlete.
///
/// Stored at `reviews/${linkId}_${athleteId}` (deterministic id).
/// One review per link — upsert semantics via [ReviewRepository.upsert].
///
/// REQ-RV-DATA-001, REQ-RV-DATA-002. Fase 6 Etapa 7.
@freezed
class Review with _$Review {
  const factory Review({
    required String id,
    required String linkId,
    required String athleteId,
    required String trainerId,

    /// 1..5 inclusive. Validated by [ReviewRepository] and Firestore rules.
    required int rating,

    /// Optional freeform comment, max 500 chars.
    /// Validated by [ReviewRepository] and Firestore rules.
    String? comment,
    @TimestampConverter() required DateTime createdAt,
    @TimestampConverter() required DateTime updatedAt,
  }) = _Review;

  /// Deterministic document id: `${linkId}_${athleteId}`.
  /// One review per active link per athlete. ADR-RV-002.
  static String idFor(String linkId, String athleteId) =>
      '${linkId}_$athleteId';

  factory Review.fromJson(Map<String, Object?> json) => _$ReviewFromJson(json);
}
