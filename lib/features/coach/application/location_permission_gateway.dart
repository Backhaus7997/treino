import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Costura sobre el plugin de ubicación para el flujo «mensaje previo →
/// pedido del SO».
///
/// Sólo EXPONE lo que el flujo necesita para decidir QUÉ mostrar: el estado
/// actual del permiso y la apertura de los Ajustes de la app. El pedido al SO
/// en sí sigue viviendo en los notifiers (`requestPermission()`), porque ahí
/// se adquiere además la posición.
///
/// Existe porque `Geolocator.checkPermission()` se cuelga para siempre bajo
/// `testWidgets` (ver `NearbyLocationNotifier`): los tests inyectan un doble.
abstract class LocationPermissionGateway {
  /// Estado actual del permiso, SIN disparar el diálogo del SO.
  ///
  /// En iOS, `deniedForever` cubre «denegado» y «restringido»: el SO no
  /// vuelve a preguntar, sólo se cambia desde Ajustes.
  Future<LocationPermission> check();

  /// Abre los Ajustes de la app.
  Future<void> openSettings();
}

class GeolocatorLocationPermissionGateway implements LocationPermissionGateway {
  const GeolocatorLocationPermissionGateway();

  @override
  Future<LocationPermission> check() => Geolocator.checkPermission();

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}

final locationPermissionGatewayProvider = Provider<LocationPermissionGateway>(
  (ref) => const GeolocatorLocationPermissionGateway(),
);
