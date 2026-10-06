import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/profile/data/timestamp_converter.dart';

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
/// `lat`, `lng` y `geohash` están seteados — tanto para gyms (copia de la
/// ubicación del gym al snapshotear) como para custom (lo que el PF marca en el
/// mapa). El `geohash` se calcula client-side con `geohash5`. Son `null` SOLO en
/// un lugar `stale`: Google permite cachear las coordenadas 30 días, y cuando el
/// servidor no pudo refrescarlas se las BORRA (no se guarda ninguna coordenada
/// de relleno que pudiera dibujarse en un mapa). Todo consumidor que necesite
/// coordenadas filtra con [TrainerLocationPublishable.isPublishable].
///
/// Políticas de Google Places: de un lugar elegido en Places se guarda SOLO
/// `placeId` (referencia permanente) y las coordenadas con su fecha
/// (`coordsFetchedAt`; Google permite cachearlas hasta 30 días, un job las
/// refresca). `customLabel` es SIEMPRE texto que escribió el PF, nunca el
/// nombre ni la dirección de Google. Un lugar de GPS del móvil no tiene
/// `placeId` y no se refresca. `stale` lo marca el servidor cuando ya no pudo
/// refrescar las coordenadas: la app debe pedir volver a elegir el lugar.
@freezed
class TrainerLocation with _$TrainerLocation {
  const factory TrainerLocation({
    required String id,
    required TrainerLocationType type,
    String? gymId,
    String? customLabel,
    double? lat,
    double? lng,
    String? geohash,
    String? placeId,
    @TimestampConverter() DateTime? coordsFetchedAt,
    bool? stale,
  }) = _TrainerLocation;

  factory TrainerLocation.fromJson(Map<String, Object?> json) =>
      _$TrainerLocationFromJson(json);
}

extension TrainerLocationPublishable on TrainerLocation {
  /// `true` si el lugar tiene coordenadas vigentes: no está `stale` y conserva
  /// `lat`/`lng`. Es la compuerta para mapa, distancia, búsqueda y espejo
  /// público; un lugar que no la pasa solo se muestra para pedir que se lo
  /// vuelva a elegir.
  bool get isPublishable => stale != true && lat != null && lng != null;
}

/// Lugar de PF tipo `gym` a partir de un gym del catálogo.
///
/// Copia las coordenadas del gym. Si el gym viene de Google Places su id ES el
/// `place_id`: se copia también `placeId` y `coordsFetchedAt` (la edad real de
/// esas coordenadas) para que el job de refresco (#1338) las mantenga dentro de
/// los 30 días de Google. Sin `coordsFetchedAt` en el gym queda null y la
/// migración lo cubre. Un gym seed / self-service no tiene `place_id`.
TrainerLocation trainerLocationFromGym(Gym gym) {
  final fromPlaces = gym.source == GymSource.googlePlaces;
  return TrainerLocation(
    id: 'gym-${gym.id}',
    type: TrainerLocationType.gym,
    gymId: gym.id,
    lat: gym.lat,
    lng: gym.lng,
    geohash: gym.geohash,
    placeId: fromPlaces ? gym.id : null,
    coordsFetchedAt: fromPlaces ? gym.coordsFetchedAt : null,
  );
}
