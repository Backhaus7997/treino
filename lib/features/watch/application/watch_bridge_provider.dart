import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/watch_bridge.dart';

/// Envoltorio sobre `WatchConnectivity`. Se sobreescribe en tests vía
/// `ProviderScope.overrides`.
///
/// Vive en un archivo PROPIO y no junto al servicio de credencial del teléfono
/// porque lo consumen las dos apps, y sólo una de ellas quiere las
/// dependencias de la otra: `watch_credential_providers.dart` arrastra
/// `cloud_functions` y el perfil del usuario, que en el companion de Wear no
/// pintan nada. Compartir la instancia sin compartir ese equipaje es todo el
/// motivo de este archivo.
final watchBridgeProvider = Provider<WatchBridge>((ref) => WatchBridge());
