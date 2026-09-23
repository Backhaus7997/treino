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

/// «Cancelar cuenta» del alta está en curso: no se crea nada más.
///
/// Sin esto, un reintento podía crear `users/{uid}` —con el mail— justo antes
/// de que `cancelOnboarding` borrara la cuenta de Auth. Y ese doc queda
/// huérfano: `cancelOnboarding` no borra el de Firestore (`UserRepository.delete`
/// tira siempre) y no hay trigger que lo limpie al borrar la cuenta de Auth.
/// Un intento que ya salió no se puede frenar; los siguientes, sí. Si la
/// cancelación falla, el flag vuelve a false y los reintentos arrancan de nuevo.
///
/// autoDispose: lo mantiene vivo [perfilAseguradoProvider], que lo watchea, y
/// muere con el alta. La cuenta siguiente arranca con el flag en false.
final altaCanceladaProvider = StateProvider.autoDispose<bool>((_) => false);

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
  if (ref.watch(altaCanceladaProvider)) return;
  // El watch de arriba reconstruye este provider cuando cambia el flag, pero
  // no en el acto: flutter_riverpod lo ejecuta en el próximo frame
  // (`_flutterVsync` → `markNeedsBuild`), y con la app en segundo plano no hay
  // frames mientras los timers de este loop siguen corriendo. Hasta ese
  // rebuild, el loop viejo seguiría intentando. Por eso el flag también se
  // consulta antes de cada intento.
  //
  // Es una defensa que NINGÚN test aísla: en un ProviderContainer de test el
  // rebuild llega siempre antes del próximo intento, y el control negativo sin
  // esta consulta sale verde. Lo que sí está medido es el corte por el rebuild.
  final cancelacion = ref.read(altaCanceladaProvider.notifier);
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
    if (!vivo || cancelacion.state) return;
    try {
      await repo.createIfAbsent(uid: uid, email: cuenta.email ?? '');
      return;
    } catch (e, st) {
      ultimoError = e;
      ultimoStack = st;
    }
  }

  if (!vivo || cancelacion.state || ultimoError == null) return;

  // El reporte no puede decir «sigue sin existir» si no lo sabe. El último
  // intento pudo fallar justamente porque el doc apareció en el medio: el
  // submit ganó la carrera y el pin de `createdAt` rechazó el batch. Eso no es
  // un problema, y reportarlo como tal entrenaría a ignorar el reporte.
  bool? existe;
  try {
    existe = await repo.get(uid) != null;
  } catch (_) {
    existe = null;
  }
  if (existe == true || !vivo || cancelacion.state) return;
  unawaited(reportar(
    ultimoError,
    ultimoStack ?? StackTrace.current,
    reason: existe == false
        ? 'perfilAsegurado: users/{uid} sigue sin existir después de '
            '${esperas.length} intentos en el alta'
        : 'perfilAsegurado: fallaron los ${esperas.length} intentos del '
            'alta y no se pudo confirmar si users/{uid} existe',
  ));
});
