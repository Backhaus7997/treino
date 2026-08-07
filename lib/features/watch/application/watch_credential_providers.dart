import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../firebase_options.dart';
import '../../auth/application/auth_providers.dart';
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
  // Corriendo contra el emulador hay que decirle al reloj dónde autenticarse:
  // por defecto le habla a la Firebase real, y un custom token minteado
  // localmente vuelve 400 desde producción. El lado Swift solo honra este host
  // en builds de debug.
  const useEmulator = bool.fromEnvironment('USE_EMULATOR');
  return WatchCredentialService(
    functions: ref.watch(watchCloudFunctionsProvider),
    bridge: ref.watch(watchBridgeProvider),
    apiKey: options.apiKey,
    projectId: options.projectId,
    authEmulatorHost: useEmulator ? 'http://localhost:9099' : null,
    // Puerto DISTINTO al de Auth. Reusar uno para el otro da 404 mudo.
    firestoreEmulatorHost: useEmulator ? 'http://localhost:8080' : null,
  );
});

/// Entrega credencial al reloj cada vez que hay un usuario autenticado.
///
/// Se lee de forma eager en `app.dart`, mismo patrón que `fcmLifecycleProvider`
/// (ADR-PN-003). Sin ese `ref.read`, todo el handoff es código muerto: el
/// servicio existe pero nadie lo llama, y el reloj se queda esperando para
/// siempre.
///
/// Reenviar en cada arranque es intencional y barato: el servicio corta solo si
/// no hay reloj emparejado, y el lado Swift no re-canjea si ya tiene credencial
/// del mismo uid. Así se cubre el caso de emparejar el reloj DESPUÉS de haber
/// iniciado sesión, que si no quedaría sin credencial hasta el próximo login.
final watchCredentialLifecycleProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<User?>>(
    authStateChangesProvider,
    (prev, next) {
      next.whenData((user) {
        if (user == null) return;
        final service = ref.read(watchCredentialServiceProvider);
        // Fire-and-forget: esto corre en el camino crítico del arranque, así
        // que no se lo hace esperar ni se le deja tirar. Quedarse sin
        // credencial de reloj es una degradación aceptable; tumbar la app por
        // eso, no.
        unawaited(
          service.deliverCredential(uid: user.uid).catchError(
                (_) => WatchCredentialOutcome.deliveryFailed,
              ),
        );
      });
    },
    fireImmediately: true,
  );
});
