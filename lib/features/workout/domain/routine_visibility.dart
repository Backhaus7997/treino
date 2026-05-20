import 'package:json_annotation/json_annotation.dart';

/// Visibilidad de una `Routine` en Firestore.
/// - `public`: accesible por todos los usuarios autenticados (plantillas).
/// - `private`: solo legible por `assignedBy` (PF) o `assignedTo` (atleta).
/// - `shared`: extensión futura (planes compartidos entre múltiples atletas).
///   Reservado para iteración futura — no se usa en Etapa 1.
enum RoutineVisibility {
  @JsonValue('public')
  public,
  @JsonValue('private')
  private,
  @JsonValue('shared')
  shared,
}

extension RoutineVisibilityX on RoutineVisibility {
  String toJson() => switch (this) {
        RoutineVisibility.public => 'public',
        RoutineVisibility.private => 'private',
        RoutineVisibility.shared => 'shared',
      };

  static RoutineVisibility fromJson(String value) => switch (value) {
        'public' => RoutineVisibility.public,
        'private' => RoutineVisibility.private,
        'shared' => RoutineVisibility.shared,
        _ => RoutineVisibility.public, // defensivo — docs sin el campo
      };
}
