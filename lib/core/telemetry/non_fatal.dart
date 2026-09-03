import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Reporta un error que la app decidió **no** propagar.
///
/// Fase 6 etapa 6 pide que Crashlytics capture "crashes + non-fatals". Los
/// crashes ya los toma `main.dart` por tres vías (`FlutterError.onError`,
/// `PlatformDispatcher.onError` y el `runZonedGuarded`), las tres con
/// `fatal: true`. Los non-fatals no los tomaba nadie.
///
/// El agujero concreto es el `catch` que no relanza. Hoy esos sitios escriben
/// a `developer.log`, que **sólo se ve con un debugger enchufado**: en el
/// teléfono de un usuario real no va a ninguna parte. El resultado es que un
/// write secundario puede fallar siempre, para todos, y nosotros enterarnos
/// cero.
///
/// ## Esto NO se cablea en todo `catch`
///
/// En `lib/` hay ~20 archivos con `developer.log` adentro de un catch y la
/// mayoría **traga a propósito**. El ejemplo que lo deja claro es
/// `FcmService.init`: en iOS `getToken()` tira `apns-token-not-set` cuando
/// APNS todavía no está aprovisionado —que es lo NORMAL antes de que el
/// usuario acepte el permiso, y siempre en el simulador— y su propio
/// comentario dice que se traga ahí justamente para que "the trace [does not]
/// propagate to Crashlytics as noise".
///
/// O sea: alguien ya sacó ese ruido de Crashlytics con criterio. Volver a
/// meterlo en bloque sería una regresión disfrazada de mejora. Cada sitio
/// necesita la misma pregunta: **¿el error es esperable, o es un bug que hoy
/// nadie ve?** Sólo el segundo es non-fatal.
///
/// El caso canónico del segundo grupo es ADR-WRS-10 (`wire-real-stats`): los
/// writes cross-feature de contadores denormalizados, que son best-effort
/// por diseño —no queremos romperle el cierre de sesión al atleta por un
/// contador— pero cuya falla silenciosa deja el perfil público mostrando
/// números viejos para siempre.
///
/// ## Contrato
///
/// Nunca tira. Un reporte de telemetría que rompe al llamador convierte un
/// error invisible en un crash, que es exactamente lo que este código existe
/// para evitar.
typedef NonFatalReporter = Future<void> Function(
  Object error,
  StackTrace stack, {
  required String reason,
});

/// Implementación real de [NonFatalReporter].
///
/// [reason] es la etiqueta que se lee en la consola de Crashlytics: que diga
/// qué operación se perdió y de quién, no sólo el tipo de excepción.
Future<void> reportNonFatal(
  Object error,
  StackTrace stack, {
  required String reason,
}) async {
  // Se mantiene siempre: es lo único que sirve mientras desarrollás, y es el
  // comportamiento que ya tenían los call sites antes de esta costura.
  developer.log(reason, error: error, stackTrace: stack);

  // Crashlytics no soporta web — mismo guard que el wire de `main.dart`.
  if (kIsWeb) return;

  // Sin app de Firebase inicializada, `FirebaseCrashlytics.instance` tira
  // `[core/no-app]`. En `flutter test` nunca la hay. Mismo criterio que
  // `analyticsServiceProvider`, por la misma razón: que un test que no se
  // ocupa de telemetría no tenga que saber que existe.
  if (Firebase.apps.isEmpty) return;

  try {
    await FirebaseCrashlytics.instance.recordError(
      error,
      stack,
      reason: reason,
      fatal: false,
    );
  } catch (_) {
    // Ver el contrato del typedef: silencio deliberado. Si Crashlytics no
    // puede reportar, el llamador no se tiene que enterar.
  }
}

/// Dispara [operacion] sin esperarla, y **sin dejar que su falla escale**.
///
/// `unawaited(future)` a secas no alcanza: no engancha ningún handler, así que
/// si el future falla el error async no lo agarra el `try` de alrededor —
/// sube hasta el `runZonedGuarded` de `main.dart`, que lo registra como
/// **FATAL**. O sea: una llamada de telemetría que falla se convierte en un
/// crash reportado, después de que la operación de negocio ya salió bien.
///
/// Pasó exactamente así con `appointment_created`: el evento mandaba un `bool`
/// —que `firebase_analytics` no acepta—, el assert tiraba, y el `unawaited`
/// lo mandaba derecho al reporte de crashes. La cita quedaba creada y el
/// usuario veía la app "crashear".
///
/// Esto lo baja a lo que es: un non-fatal.
void fireAndForget(Future<void> operacion, {required String reason}) {
  unawaited(
    operacion.catchError(
      (Object error, StackTrace stack) =>
          reportNonFatal(error, stack, reason: reason),
    ),
  );
}
