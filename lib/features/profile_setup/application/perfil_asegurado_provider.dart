import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/telemetry/non_fatal.dart';
import '../../auth/application/auth_providers.dart'
    show authStateChangesProvider;
import '../../profile/application/user_providers.dart';

/// Esperas antes de cada intento de [perfilAseguradoProvider]: uno enseguida
/// y tres más, cada vez más separados.
///
/// Es un provider para que los tests lo corran sin esperar de verdad.
final esperasDelPerfilProvider = Provider<List<Duration>>(
  (_) => const [
    Duration.zero,
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ],
);

/// Reporter de [perfilAseguradoProvider], inyectable para los tests.
final reportePerfilAseguradoProvider =
    Provider<NonFatalReporter>((_) => reportNonFatal);

/// Garantiza `users/{uid}` para la cuenta que está haciendo el alta.
///
/// El login lo crea con UN intento (`AuthService.signInWith*`). Medido en
/// producción del 16 al 22/09: en 3 de las 5 altas con Google/Apple ese
/// intento no dejó el doc, que apareció recién entre 34 y 95 s después. Según
/// lo reportado, pasa en teléfonos nuevos. La causa exacta todavía no se
/// conoce: el login ahora la manda a Crashlytics. Esto no depende de ella:
/// desde que arranca el alta reintenta con esperas crecientes, hasta que el
/// doc existe o se agotan los intentos.
///
/// NO PISA el alta, aunque un intento llegue tarde. `createIfAbsent` lee y
/// después escribe, así que un intento que leyó «no existe» justo antes del
/// submit podría escribir después, con el `toJson()` de un perfil vacío. Lo
/// frena el pin de `createdAt` en el update de `users/{uid}`: cada intento
/// trae su propio `createdAt`, así que sobre un doc ya creado se rechaza, y
/// el batch cae entero. Medido contra el emulador, y fijado en
/// `functions/src/__tests__/alta-no-se-pisa-rules.test.ts`: con el MISMO
/// `createdAt` el batch pasaba y borraba nombre, gimnasio y consentimiento.
///
/// Si ningún intento anda, reporta un non-fatal y el alta sigue igual: ya no
/// depende de este doc para avanzar, y el submit lo crea (self-heal).
final perfilAseguradoProvider = FutureProvider.autoDispose<void>((ref) async {
  final cuenta = ref.watch(
    authStateChangesProvider.select(
      (auth) => (uid: auth.valueOrNull?.uid, email: auth.valueOrNull?.email),
    ),
  );
  final uid = cuenta.uid;
  if (uid == null) return;

  final repo = ref.watch(userRepositoryProvider);
  final esperas = ref.watch(esperasDelPerfilProvider);
  final reportar = ref.watch(reportePerfilAseguradoProvider);

  var vivo = true;
  ref.onDispose(() => vivo = false);

  Object? ultimoError;
  StackTrace? ultimoStack;
  for (final espera in esperas) {
    if (espera > Duration.zero) await Future<void>.delayed(espera);
    if (!vivo) return;
    try {
      await repo.createIfAbsent(uid: uid, email: cuenta.email ?? '');
      return;
    } catch (e, st) {
      ultimoError = e;
      ultimoStack = st;
    }
  }

  if (vivo && ultimoError != null) {
    unawaited(reportar(
      ultimoError,
      ultimoStack ?? StackTrace.current,
      reason: 'perfilAsegurado: users/{uid} sigue sin existir después de '
          '${esperas.length} intentos en el alta',
    ));
  }
});
