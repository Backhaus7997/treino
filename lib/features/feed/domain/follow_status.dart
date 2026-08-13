import 'package:json_annotation/json_annotation.dart';

/// Estado de una arista de follow.
///
/// Los literales de wire son los MISMOS que los de `FriendshipStatus`
/// (`'pending'` / `'accepted'`) a propósito: la migración copia el campo tal
/// cual, sin traducir, y las rules comparan contra el mismo string en las dos
/// colecciones mientras conviven. Inventar literales nuevos habría metido una
/// tabla de traducción en el camino crítico de un cambio de privacidad.
enum FollowStatus {
  /// La solicitud existe pero el destinatario todavía no la aceptó. Solo pasa
  /// con cuentas privadas (`isProfilePublic == false`).
  @JsonValue('pending')
  pending,

  /// El follow está activo. En cuentas públicas se crea directamente así.
  @JsonValue('accepted')
  accepted,
}

extension FollowStatusX on FollowStatus {
  static const _wireMap = {
    'pending': FollowStatus.pending,
    'accepted': FollowStatus.accepted,
  };

  /// Tira [ArgumentError] ante un valor desconocido en vez de devolver un
  /// default. Un status que no reconocemos es dato corrupto o un cliente de
  /// otra versión: asumir `pending` por descarte otorgaría o negaría acceso en
  /// silencio, que es lo peor que puede hacer un gate de privacidad.
  static FollowStatus fromJson(String value) {
    final status = _wireMap[value];
    if (status == null) {
      throw ArgumentError.value(
        value,
        'value',
        'Unknown FollowStatus wire value',
      );
    }
    return status;
  }

  String toJson() => switch (this) {
        FollowStatus.pending => 'pending',
        FollowStatus.accepted => 'accepted',
      };
}
