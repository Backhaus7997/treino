import 'package:geolocator/geolocator.dart';
import 'package:treino/features/coach/application/location_permission_gateway.dart';

/// Doble del plugin de ubicación para tests de widget.
///
/// `Geolocator.checkPermission()` se cuelga para siempre bajo `testWidgets`
/// (ver `NearbyLocationNotifier`), así que todo test que recorra el flujo
/// «mensaje previo → pedido del SO» inyecta esto vía
/// `locationPermissionGatewayProvider`.
class FakeLocationPermissionGateway implements LocationPermissionGateway {
  FakeLocationPermissionGateway(this.status, {this.throwOnCheck = false});

  final LocationPermission status;
  final bool throwOnCheck;
  int openSettingsCalls = 0;

  @override
  Future<LocationPermission> check() async {
    if (throwOnCheck) throw Exception('plugin error');
    return status;
  }

  @override
  Future<void> openSettings() async => openSettingsCalls++;
}
