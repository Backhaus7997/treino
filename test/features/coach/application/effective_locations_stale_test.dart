import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';

/// Política de Places (#1338): un lugar `stale` perdió sus coordenadas (el
/// servidor las borra a los 30 días). Ni el mapa, ni la distancia, ni la
/// etiqueta del "más cercano" pueden verlo: todos pasan por
/// `effectiveLocationsOf`.
void main() {
  Position pos() => Position(
        latitude: -34.6,
        longitude: -58.4,
        timestamp: DateTime(2026),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  const vigente = TrainerLocation(
    id: 'vigente',
    type: TrainerLocationType.custom,
    customLabel: 'Vigente',
    lat: -34.7,
    lng: -58.5,
    geohash: '69y7p',
  );
  const vencido = TrainerLocation(
    id: 'vencido',
    type: TrainerLocationType.custom,
    customLabel: 'Vencido',
    placeId: 'ChIJabc',
    stale: true,
  );
  // Defensivo: coordenadas ausentes sin la marca `stale`.
  const sinCoords = TrainerLocation(
    id: 'sin-coords',
    type: TrainerLocationType.custom,
    customLabel: 'Sin coords',
  );

  TrainerPublicProfile pf(List<TrainerLocation> locs) =>
      TrainerPublicProfile(uid: 't1', trainerLocations: locs);

  test('effectiveLocationsOf descarta los stale / sin coordenadas', () {
    final r = effectiveLocationsOf(pf([vencido, vigente, sinCoords]));
    expect(r.map((l) => l.id), ['vigente']);
  });

  test(
      'un PF con TODOS los lugares vencidos no aparece en el mapa ni tiene '
      'distancia', () {
    final t = pf([vencido, sinCoords]);
    expect(effectiveLocationsOf(t), isEmpty);
    expect(nearestDistanceKm(t, pos()), isNull);
    expect(nearestLocationOf(t, pos()), isNull);
  });

  test('la distancia y el más cercano ignoran al vencido', () {
    final t = pf([vencido, vigente]);
    expect(nearestDistanceKm(t, pos()), isNotNull);
    expect(nearestLocationOf(t, pos())!.id, 'vigente');
  });
}
