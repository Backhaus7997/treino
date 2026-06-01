import 'package:json_annotation/json_annotation.dart';

/// Estado de una `Routine` creada por el atleta.
/// - `active`: visible en MIS RUTINAS.
/// - `archived`: oculta en MIS RUTINAS; el documento se conserva para
///   mantener referencias históricas de sesiones (soft-delete, ADR-USR-04).
/// Default `active` para retro-compat con docs sin el campo.
enum RoutineStatus {
  @JsonValue('active')
  active,
  @JsonValue('archived')
  archived,
}

extension RoutineStatusX on RoutineStatus {
  String get label => switch (this) {
        RoutineStatus.active => 'Activa',
        RoutineStatus.archived => 'Archivada',
      };

  String toJson() => switch (this) {
        RoutineStatus.active => 'active',
        RoutineStatus.archived => 'archived',
      };

  static RoutineStatus fromJson(String value) => switch (value) {
        'active' => RoutineStatus.active,
        'archived' => RoutineStatus.archived,
        _ => RoutineStatus
            .active, // defensivo — docs sin el campo o valor desconocido
      };
}
