import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart';
import '../data/wear_push_registration.dart';

/// Se sobreescribe en tests.
final wearPushRegistrationProvider = Provider<WearPushRegistration>(
  (ref) => WearPushRegistration(),
);

/// Registra el token del reloj cada vez que hay sesión.
///
/// Se lee de forma EAGER en `main_wear.dart`, mismo patrón que el lifecycle de
/// credencial del teléfono: sin ese `ref.read` esto es código muerto y el reloj
/// nunca queda alcanzable por push.
///
/// Se engancha al uid y no se hace una sola vez al arrancar porque el uid llega
/// asíncrono —Firebase restaura la sesión después de que el árbol se construye—
/// y una lectura única daría null en todo arranque en frío. Es la misma trampa
/// que ya costó una corrida con la adopción del entreno.
final wearPushLifecycleProvider = Provider<void>((ref) {
  ref.listen<String?>(
    currentUidProvider,
    (previo, nuevo) {
      if (nuevo == null || nuevo.isEmpty) return;
      if (previo == nuevo) return;
      unawaited(ref.read(wearPushRegistrationProvider).register(nuevo));
    },
    fireImmediately: true,
  );
});
