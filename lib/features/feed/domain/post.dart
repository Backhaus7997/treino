// ignore: unused_import — Timestamp is used by the generated post.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'post_privacy.dart';
import 'routine_tag.dart';
import 'workout_stats.dart';

part 'post.freezed.dart';
part 'post.g.dart';

@freezed
class Post with _$Post {
  const factory Post({
    required String id,
    required String authorUid,
    // Author display fields denormalized at write time (same ADR as authorGymId).
    // Stale-on-update is accepted — standard social-media pattern.
    // `@Default('Anónimo')` handles legacy Firestore docs that predate this field —
    // json_serializable applies the default when the JSON key is missing.
    @Default('Anónimo') String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,
    required String text,
    required RoutineTag? routineTag,
    required PostPrivacy privacy,
    @TimestampConverter() required DateTime createdAt,
    // QA-FEED-364/389: workout metrics for the feed card's stats row. Optional
    // (NOT `required`) on purpose — a manual post or a legacy doc simply omits
    // it and the card hides the row. Keeping it non-required also means the
    // other Post(...) call sites (e.g. manual create-post) need no change.
    WorkoutStats? workoutStats,
  }) = _Post;

  factory Post.fromJson(Map<String, Object?> json) => _$PostFromJson(json);
}
