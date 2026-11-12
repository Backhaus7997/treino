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

/// Estados de un vínculo VIVO: el PF y el alumno siguen siendo PF y alumno.
///
/// `paused` cuenta: pausar es un hold temporal, no un corte (el chat sigue
/// abierto, ver `chatEnablingLinkStatuses`). Sólo `pending` (nunca se aceptó) y
/// `terminated` (ex-alumno) quedan afuera, y también el alumno SIN vínculo.
/// Es el criterio de las acciones que le dan algo al alumno, como asignarle una
/// rutina (#1695).
const kEstadosDeVinculoVivo = {
  TrainerLinkStatus.active,
  TrainerLinkStatus.paused,
};

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
