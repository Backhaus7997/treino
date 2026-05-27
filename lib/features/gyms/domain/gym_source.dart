import 'package:json_annotation/json_annotation.dart';

/// Origen de un gym del catálogo.
///
/// `seed` → cargado por `scripts/seed_gyms.js` con datos curados (cadenas
/// grandes + gimnasios locales conocidos).
/// `selfService` → un PF lo agregó desde la UI "Mi gym no está en la lista".
/// Self-service entries pueden requerir moderación admin en una iteración
/// futura — por ahora se aceptan directos.
enum GymSource {
  @JsonValue('seed')
  seed,
  @JsonValue('self-service')
  selfService,
}

extension GymSourceX on GymSource {
  static const _wireMap = {
    'seed': GymSource.seed,
    'self-service': GymSource.selfService,
  };

  String toWire() => switch (this) {
        GymSource.seed => 'seed',
        GymSource.selfService => 'self-service',
      };
}

GymSource? gymSourceFromString(String? value) {
  if (value == null || value.isEmpty) return null;
  return GymSourceX._wireMap[value.trim().toLowerCase()];
}
