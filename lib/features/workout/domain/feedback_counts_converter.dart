import 'package:freezed_annotation/freezed_annotation.dart';

import 'exercise_feedback.dart';

/// Convierte el mapa `feedbackCounts` que escribe
/// `maintainSessionFeedbackCounters` (functions/) al mapa tipado del modelo.
///
/// Gemelo de `ReactionCountsConverter`, y por el mismo motivo: un contador que
/// viene del backend tiene que poder ganar claves nuevas sin romper la
/// deserialización de TODA la sesión en los clientes viejos.
class FeedbackCountsConverter
    implements
        JsonConverter<Map<ExerciseFeedbackKind, int>, Map<String, dynamic>?> {
  const FeedbackCountsConverter();

  /// Espejo a mano de los `@JsonValue` de [ExerciseFeedbackKind]. Si agregás o
  /// renombrás un kind, esto y la lista `FEEDBACK_KINDS` de
  /// `functions/src/notifications/maintain-session-feedback-counters.ts` van
  /// juntos — no hay nada que los sincronice.
  static const _wireMap = <String, ExerciseFeedbackKind>{
    'comment': ExerciseFeedbackKind.comment,
    'discomfort': ExerciseFeedbackKind.discomfort,
  };

  static String _wireOf(ExerciseFeedbackKind kind) => switch (kind) {
        ExerciseFeedbackKind.comment => 'comment',
        ExerciseFeedbackKind.discomfort => 'discomfort',
      };

  @override
  Map<ExerciseFeedbackKind, int> fromJson(Map<String, dynamic>? json) {
    if (json == null) return const {};

    final result = <ExerciseFeedbackKind, int>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (value is! int) continue;
      final kind = _wireMap[key];
      // Compatibilidad hacia adelante: un kind que agregue un backend más nuevo
      // se ignora, en vez de tumbar la sesión entera.
      if (kind == null) continue;
      result[kind] = value;
    }
    return result;
  }

  @override
  Map<String, int> toJson(Map<ExerciseFeedbackKind, int> object) =>
      object.map((kind, count) => MapEntry(_wireOf(kind), count));
}
