import 'package:geolocator/geolocator.dart';
import 'package:treino/features/coach/application/location_permission_gateway.dart';

/// Doble del plugin de ubicación para tests de widget.
///
/// `Geolocator.checkPermission()` se cuelga para siempre bajo `testWidgets`
/// (ver `NearbyLocationNotifier`), así que todo test que recorra el flujo
/// «mensaje previo → pedido del SO» inyecta esto vía
/// `locationPermissionGatewayProvider`.
class FakeLocationPermissionGateway implements LocationPermissionGateway {
  FakeLocationPermissionGateway(
    this.status, {
    this.throwOnCheck = false,
    this.serviceEnabled = true,
    this.throwOnServiceCheck = false,
    this.throwOnOpenSettings = false,
    this.requestResult,
    this.position,
  });

  final LocationPermission status;
  final bool throwOnCheck;

  /// Estado de los Servicios de ubicación del dispositivo.
  final bool serviceEnabled;
  final bool throwOnServiceCheck;
  final bool throwOnOpenSettings;

  /// Lo que contesta el SO al pedido; por defecto, el mismo [status].
  final LocationPermission? requestResult;
  final Position? position;

  int openSettingsCalls = 0;
  int openLocationSettingsCalls = 0;
  int requestCalls = 0;

  @override
  Future<LocationPermission> check() async {
    if (throwOnCheck) throw Exception('plugin error');
    return status;
  }

  @override
  Future<bool> isServiceEnabled() async {
    if (throwOnServiceCheck) throw Exception('plugin error');
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> request() async {
    requestCalls++;
    return requestResult ?? status;
  }

  @override
  Future<Position> currentPosition(LocationSettings settings) async =>
      position!;

  @override
  Future<void> openSettings() async {
    openSettingsCalls++;
    if (throwOnOpenSettings) throw Exception('settings error');
  }

  @override
  Future<void> openLocationSettings() async {
    openLocationSettingsCalls++;
    if (throwOnOpenSettings) throw Exception('settings error');
  }
}
