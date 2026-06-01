import 'package:json_annotation/json_annotation.dart';

/// Origen de una `Routine`. Discrimina plantillas seedeadas del sistema
/// vs plantillas del PF (sin atleta asignado) vs planes asignados por un PF
/// vs planes creados por el propio atleta. Default `system` para retro-compat
/// con plantillas seedeadas sin el campo en Firestore.
enum RoutineSource {
  @JsonValue('system')
  system,
  @JsonValue('trainer-template')
  trainerTemplate,
  @JsonValue('trainer-assigned')
  trainerAssigned,
  @JsonValue('user-created')
  userCreated,
}

extension RoutineSourceX on RoutineSource {
  String toJson() => switch (this) {
        RoutineSource.system => 'system',
        RoutineSource.trainerTemplate => 'trainer-template',
        RoutineSource.trainerAssigned => 'trainer-assigned',
        RoutineSource.userCreated => 'user-created',
      };

  static RoutineSource fromJson(String value) => switch (value) {
        'system' => RoutineSource.system,
        'trainer-template' => RoutineSource.trainerTemplate,
        'trainer-assigned' => RoutineSource.trainerAssigned,
        'user-created' => RoutineSource.userCreated,
        _ => RoutineSource.system, // defensivo — docs antiguos sin el campo
      };
}
