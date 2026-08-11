// ignore: unused_import — Timestamp is used by the generated part file
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'exercise_feedback_kind.dart';

part 'exercise_feedback.freezed.dart';
part 'exercise_feedback.g.dart';

/// Athlete-authored feedback on one exercise of a session, readable by their
/// linked trainer.
///
/// The mirror image of [RoutineSlot.notes] (trainer → athlete, authored in the
/// routine editor): this is athlete → trainer, authored live during the
/// session and anchored to the exercise — and optionally the exact set — that
/// prompted it. That anchoring is the whole point; the chat cannot express
/// "third set of bench press, right shoulder".
///
/// Stored at `users/{uid}/sessions/{sessionId}/exerciseFeedback/{id}`, mirroring
/// the `setLogs` sub-collection so it inherits the `session_shares` read grant
/// (owner OR linked trainer) with owner-only writes.
@freezed
class ExerciseFeedback with _$ExerciseFeedback {
  const ExerciseFeedback._();

  const factory ExerciseFeedback({
    required String id,

    /// FK → exercises/{id}. Matches [SetLog.exerciseId] so the trainer can
    /// correlate feedback with the numbers.
    required String exerciseId,

    /// Denormalized for display without a catalog read, same rationale as
    /// [SetLog.exerciseName].
    required String exerciseName,

    /// Position of the slot within the routine day (0-based).
    ///
    /// Required because the same [exerciseId] may legitimately appear twice in
    /// one day (device feedback 2026-06-12). Anchoring on `exerciseId` alone
    /// would surface a comment left on the second bench-press block on the
    /// first one too.
    required int slotIndex,

    /// 1-based set the feedback refers to. Null ⇒ the feedback is about the
    /// exercise as a whole, not one set.
    int? setNumber,
    required ExerciseFeedbackKind kind,

    /// Free-form athlete text. Null/empty when the athlete only sent a photo.
    String? text,

    /// Storage download URL of the attached photo, null when text-only.
    String? photoUrl,

    /// Storage object path behind [photoUrl], kept so the object can be
    /// deleted. Mirrors the `athlete_files` pattern: storing both prevents
    /// URL↔path drift, which is why updates are denied by the rules.
    String? photoPath,
    @TimestampConverter() required DateTime createdAt,
  }) = _ExerciseFeedback;

  factory ExerciseFeedback.fromJson(Map<String, Object?> json) =>
      _$ExerciseFeedbackFromJson(json);

  /// Whether this entry carries any payload at all.
  ///
  /// The composer enforces "text OR photo" before writing, so a persisted
  /// entry should always satisfy this; the getter exists so the trainer-side
  /// render can skip a malformed doc instead of drawing an empty card.
  bool get hasContent =>
      (text?.trim().isNotEmpty ?? false) ||
      (photoUrl?.trim().isNotEmpty ?? false);

  /// Anchor identity used to group feedback under a rendered exercise block.
  bool matchesSlot(String exerciseId, int slotIndex) =>
      this.exerciseId == exerciseId && this.slotIndex == slotIndex;
}
