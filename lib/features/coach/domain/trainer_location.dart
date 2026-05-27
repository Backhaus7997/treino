import 'package:freezed_annotation/freezed_annotation.dart';

part 'trainer_location.freezed.dart';
part 'trainer_location.g.dart';

/// Tipo de ubicación de trabajo del PF. Mantiene la diferencia visual y
/// semántica entre un gym del catálogo (entity con su propia ficha) y un
/// lugar propio del PF (sin entity respaldo).
enum TrainerLocationType {
  @JsonValue('gym')
  gym,
  @JsonValue('custom')
  custom,
}

extension TrainerLocationTypeX on TrainerLocationType {
  String toWire() => switch (this) {
        TrainerLocationType.gym => 'gym',
        TrainerLocationType.custom => 'custom',
      };
}

/// Una ubicación donde el PF trabaja físicamente.
///
/// Cuando `type == gym`, `gymId` referencia `gyms/{gymId}` y `customLabel`
/// es null. Cuando `type == custom`, `gymId` es null y `customLabel` lleva
/// el nombre que le puso el PF (ej: 'Mi estudio en casa', 'Parque Sarmiento').
///
/// `lat`, `lng` y `geohash` SIEMPRE están seteados — tanto para gyms (copia
/// de la ubicación del gym al snapshotear) como para custom (lo que el PF
/// marca en el mapa). El `geohash` se calcula client-side con `geohash5`.
@freezed
class TrainerLocation with _$TrainerLocation {
  const factory TrainerLocation({
    required String id,
    required TrainerLocationType type,
    String? gymId,
    String? customLabel,
    required double lat,
    required double lng,
    required String geohash,
  }) = _TrainerLocation;

  factory TrainerLocation.fromJson(Map<String, Object?> json) =>
      _$TrainerLocationFromJson(json);
}
