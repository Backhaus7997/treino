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

  /// Si los Servicios de ubicación del dispositivo están encendidos.
  ///
  /// Con ellos apagados no hay posición aunque el permiso esté otorgado, y el
  /// SO no vuelve a preguntar por el permiso: sólo se enciende desde Ajustes.
  Future<bool> isServiceEnabled();

  /// Pide el permiso al SO (dispara el diálogo del sistema si hace falta).
  ///
  /// Sólo para quien no tiene un notifier propio de ubicación (p. ej. el
  /// botón «Detectar» del editor del PF).
  Future<LocationPermission> request();

  /// Adquiere la posición actual con la precisión que pide el caller.
  Future<Position> currentPosition(LocationSettings settings);

  /// Abre los Ajustes de la app.
  Future<void> openSettings();

  /// Abre los Ajustes de los Servicios de ubicación del dispositivo (en iOS,
  /// la app de Ajustes; el SO no permite saltar directo al interruptor).
  Future<void> openLocationSettings();
}

class GeolocatorLocationPermissionGateway implements LocationPermissionGateway {
  const GeolocatorLocationPermissionGateway();

  @override
  Future<LocationPermission> check() => Geolocator.checkPermission();

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> request() => Geolocator.requestPermission();

  @override
  Future<Position> currentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();

  @override
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}

final locationPermissionGatewayProvider = Provider<LocationPermissionGateway>(
  (ref) => const GeolocatorLocationPermissionGateway(),
);
