import 'package:geolocator/geolocator.dart';

/// Con cuánta precisión se le pide la ubicación al sistema operativo.
///
/// Vive en un solo lugar porque son DOS valores con dos justificaciones
/// distintas, y repartirlos por los call sites garantiza que en seis meses uno
/// tenga `best` "porque venía así".
///
/// ─── Por qué el atleta no necesita `best` ───────────────────────────────────
///
/// Su posición sólo alimenta dos cosas, y las dos son gruesas:
///
/// | consumidor | granularidad real |
/// | --- | --- |
/// | la query de discovery | `geohash5` → celdas de ~4,9 km |
/// | el número que ve en pantalla | `toStringAsFixed(1)` km → **100 m** |
///
/// (`nearestDistanceKm` + `_formatDistance` en `trainer_list_tile.dart`.)
///
/// `best` pide ~0 m en iOS. Es entre 20 y 1000 veces más fino que lo que el
/// producto usa, y en iOS enciende el GPS en su modo más caro — justo lo que
/// `docs/performance.md` pide no hacer.
///
/// ─── Por qué `high` y no `medium` ───────────────────────────────────────────
///
/// `medium` es 100 m en iOS pero **entre 100 y 500 m en Android**. Con 500 m de
/// error, un "0,4 km" puede mostrarse como "0,9 km" — y a esa distancia la
/// diferencia decide si el atleta camina o no. `high` es 10 m en iOS y 0-100 m
/// en Android: calzado con los 100 m que la UI muestra, sin ruido visible.
const kAthleteLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.high,
);

/// La del entrenador SÍ va en `best`, y es lo correcto.
///
/// No es una posición transitoria: se guarda en `TrainerLocation.lat/lng` y se
/// **publica** en su perfil, con pin en el mapa y distancia calculada hasta
/// cada atleta. La precisión ahí no es un exceso, es la feature — un pin a 500
/// m del estudio manda gente a la cuadra equivocada.
///
/// Y es información que el PF publica a propósito sobre dónde trabaja, no un
/// dato que se le extrae mientras usa la app. La sección "4. Ubicación" de
/// `legal_content.dart` explica exactamente esa diferencia; si este valor
/// cambia, ese texto también.
const kTrainerLocationSettings = LocationSettings(
  accuracy: LocationAccuracy.best,
);
