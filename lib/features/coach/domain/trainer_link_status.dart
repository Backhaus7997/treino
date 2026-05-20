import 'package:json_annotation/json_annotation.dart';

/// Estado del vínculo entre PF y atleta.
///
/// Transiciones válidas:
/// - request → `pending`
/// - accept (sobre pending) → `active`
/// - decline (sobre pending) → `terminated`
/// - terminate (sobre active/paused) → `terminated`
/// - (paused/resume queda para iteración futura — paused está definido
///   en el enum pero no se expone API en Etapa 1.)
enum TrainerLinkStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('active')
  active,
  @JsonValue('paused')
  paused,
  @JsonValue('terminated')
  terminated,
}

extension TrainerLinkStatusX on TrainerLinkStatus {
  String toJson() => switch (this) {
        TrainerLinkStatus.pending => 'pending',
        TrainerLinkStatus.active => 'active',
        TrainerLinkStatus.paused => 'paused',
        TrainerLinkStatus.terminated => 'terminated',
      };

  static TrainerLinkStatus fromJson(String value) => switch (value) {
        'pending' => TrainerLinkStatus.pending,
        'active' => TrainerLinkStatus.active,
        'paused' => TrainerLinkStatus.paused,
        'terminated' => TrainerLinkStatus.terminated,
        _ => throw ArgumentError.value(
            value, 'value', 'Unknown TrainerLinkStatus wire value'),
      };
}
