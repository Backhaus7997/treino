import 'package:json_annotation/json_annotation.dart';

/// Kind of athlete-authored feedback attached to an exercise during a session.
///
/// [comment] is neutral information for the trainer (how the exercise felt,
/// a machine substitution, a question). [discomfort] flags pain or a joint
/// issue — it is the only kind that pushes a notification to the trainer, and
/// the only one rendered with a distinct visual marker on the trainer's side.
/// Keeping them apart is what stops a routine comment from buzzing the
/// trainer's phone a dozen times per session.
///
/// Wire values follow the same serialization pattern as [SessionStatus] and
/// [MediaType].
enum ExerciseFeedbackKind {
  @JsonValue('comment')
  comment,
  @JsonValue('discomfort')
  discomfort,
}

extension ExerciseFeedbackKindX on ExerciseFeedbackKind {
  static const _wireMap = {
    'comment': ExerciseFeedbackKind.comment,
    'discomfort': ExerciseFeedbackKind.discomfort,
  };

  static ExerciseFeedbackKind fromJson(String value) {
    final kind = _wireMap[value];
    if (kind == null) {
      throw ArgumentError.value(
          value, 'value', 'Unknown ExerciseFeedbackKind wire value');
    }
    return kind;
  }

  String toJson() => switch (this) {
        ExerciseFeedbackKind.comment => 'comment',
        ExerciseFeedbackKind.discomfort => 'discomfort',
      };

  /// Whether this kind notifies the linked trainer on create.
  bool get notifiesTrainer => this == ExerciseFeedbackKind.discomfort;
}
