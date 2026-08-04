import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../firebase_options.dart';
import '../data/watch_bridge.dart';
import '../data/watch_credential_service.dart';

/// Envoltorio sobre `WatchConnectivity`. Se sobreescribe en tests vía
/// `ProviderScope.overrides`.
final watchBridgeProvider = Provider<WatchBridge>((ref) => WatchBridge());

/// Instancia de Cloud Functions en la región donde vive `mintWatchCredential`.
///
/// Se declara acá y no se reusa `cloudFunctionsProvider` de `coach_hub` a
/// propósito: `watch/` no debe depender de un feature de dominio. Ambos apuntan
/// a la misma región, que es la que usa todo callable del proyecto.
final watchCloudFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: 'southamerica-east1'),
);

/// Servicio que le consigue credencial propia al reloj y se la entrega.
///
/// `apiKey` y `projectId` viajan en el payload porque el reloj habla HTTP
/// directo contra Firebase, sin SDK (Locked Decision #9): sin ellos no puede
/// canjear el token ni renovar después. No son secretos — son identificadores
/// públicos del proyecto; la seguridad la dan las Security Rules y App Check.
final watchCredentialServiceProvider = Provider<WatchCredentialService>((ref) {
  final options = DefaultFirebaseOptions.currentPlatform;
  return WatchCredentialService(
    functions: ref.watch(watchCloudFunctionsProvider),
    bridge: ref.watch(watchBridgeProvider),
    apiKey: options.apiKey,
    projectId: options.projectId,
  );
});
