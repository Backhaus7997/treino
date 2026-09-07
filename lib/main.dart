import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/persistence/shared_prefs_provider.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // runZonedGuarded captura excepciones async no atrapadas (futures sin await,
  // streams sin onError). Sin esto, Crashlytics solo ve crashes sync via
  // FlutterError.onError + PlatformDispatcher.instance.onError.
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Las tipografías se sirven desde `assets/fonts/` y NUNCA por red.
    //
    // Sin esto, google_fonts baja Barlow / Barlow Condensed / Space Grotesk de
    // fonts.gstatic.com en el primer arranque. Hasta que llegan, todo se mide
    // con la fallback del sistema, y en Android esa fallback es Roboto — que
    // no es condensada. "ENTRENAR" pasa de 44,36pt a 56,78 y la barra de
    // navegación, que decide si los labels entran midiendo el texto, se queda
    // en modo íconos hasta los 389,5pt de ancho de pantalla: o sea, en la
    // práctica siempre.
    //
    // En `false` google_fonts usa lo bundleado y, si le faltara una variante,
    // lo reporta en consola en vez de taparlo con una descarga silenciosa.
    GoogleFonts.config.allowRuntimeFetching = false;

    // Y se esperan ANTES del primer frame.
    //
    // Bundlearlas no alcanza: google_fonts las registra igual de forma
    // asíncrona, así que el primer frame se dibuja con la fallback del sistema.
    // Para casi toda la UI eso es un parpadeo, pero [TreinoBottomBar] MIDE el
    // texto para decidir si los labels entran, y esa decisión no se revisa:
    // su `LayoutBuilder` no se vuelve a ejecutar cuando la fuente aparece.
    //
    // Medido en un iPhone 17 Pro (402pt): "ENTRENAR" daba 62,01pt con SF Pro
    // contra los 44,36 de Barlow Condensed, y como la caja del label es 56,12
    // la barra se quedaba en íconos PARA SIEMPRE — el mismo síntoma que esto
    // venía a arreglar, con la fuente ya bundleada.
    //
    // Desde assets esto es leer del bundle, no red: cuesta milisegundos.
    await GoogleFonts.pendingFonts([
      GoogleFonts.barlowCondensed(fontWeight: FontWeight.w700),
      GoogleFonts.barlowCondensed(),
      GoogleFonts.barlow(),
      GoogleFonts.barlow(fontWeight: FontWeight.w600),
      GoogleFonts.barlow(fontWeight: FontWeight.w700),
    ]);

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // App Check: validación de que el request viene de una app legítima
    // (no de un script o emulator random). Se activa ANTES que cualquier
    // otra service call (Firestore/Auth/Analytics) para que todas las
    // requests subsiguientes incluyan el token.
    //
    // En debug: `AndroidProvider.debug` + `AppleProvider.debug` — la primera
    // vez que la app arranca, el SDK printa un debug token en consola del
    // tipo `Enter this debug secret into the allow list...`. Ese token hay
    // que agregarlo manualmente en Firebase Console → App Check → Apps →
    // app → Manage debug tokens, una sola vez por device de dev.
    //
    // En release: Play Integrity (Android) y AppAttest (iOS). Estos
    // requieren signed builds y firebase config correcta en Console.
    //
    // ⚠️ ENFORCEMENT POR API ESTÁ **APAGADO** en `treino-dev` — Firestore e
    // Identity Toolkit los dos en UNENFORCED. Re-verificado 2026-08-25 contra
    // las APIs, sin token y con un token deliberadamente inválido: las dos lo
    // ignoran y siguen de largo (Firestore llega a evaluar reglas, Identity
    // Toolkit llega a validar credenciales). Esto CORRIGE el "ENFORCEMENT ESTÁ
    // ACTIVO (verificado 2026-07-27)" que decía acá y que contradecía a
    // functions/src/mint-watch-credential.ts:103. Ver docs/security.md §4.8.1.
    //
    // El modo se controla desde Firebase Console, no desde código, así que
    // esto puede quedar desactualizado otra vez — chequealo en
    // Console → App Check → APIs antes de creerle.
    //
    // ⚠️ OJO, lo de arriba NO aplica a los callables: `enforceAppCheck` en las
    // opciones de un `onCall` lo aplica la propia función, en su código, y es
    // independiente de la consola. Hoy el único que lo exige es `addAlias`, y
    // como se llama sólo desde el Coach Hub web —que nunca activa App Check—
    // falla siempre, con el error tragado en un `debugPrint`
    // (docs/security.md §4.10).
    //
    // `deleteAccount` lo tuvo del 2026-07-20 al 2026-08-25 y en ese mes el
    // borrado de cuenta no funcionó nunca; se sacó por eso (§4.8.2). No
    // confundir "el callable exige atestación" con "el cliente puede
    // producirla".
    //
    // Medido ancho el 2026-09-04 (24 días, 6 callables, docs/security.md
    // §4.8.3): el problema no es una tasa baja, son DOS CALLABLES EN CERO.
    // `acceptTrainerLink` —el gate del paywall— no produjo ni una atestación
    // válida en 10 intentos, y `requestPasswordReset` tampoco. Con enforcement
    // encendido esos dos flujos no fallan a veces: fallan siempre.
    //
    // El inventario de qué callable exige qué —y por qué los que no, no— vive
    // en functions/src/__tests__/appcheck-enforcement.test.ts, derivado del
    // AST de index.ts para que no se pueda quedar viejo.
    //
    // Consecuencia práctica el día que se vuelva a encender por API: en un
    // device de dev cuyo debug token NO esté registrado, TODA escritura a
    // Firestore se rechaza. No falla el login (Auth no está enforced), falla lo
    // que venga después, y el síntoma no se parece a App Check — p.ej. crear
    // cuenta muere con "Hubo un problema creando tu perfil"
    // (AuthService.signUpWithEmail → getOrCreate).
    //
    // Cómo diagnosticarlo sin depender de la consola de `flutter run`:
    //   xcrun simctl spawn <udid> log show --last 10m --style compact \
    //     --predicate 'process == "Runner"' \
    //     | rg -i "attestation|AppCheck failed|Write at"
    //
    // Cómo sacar el token ya generado de un simulador iOS:
    //   CONT=$(xcrun simctl get_app_container <udid> com.backhaus.treino data)
    //   plutil -p "$CONT/Library/Preferences/com.backhaus.treino.plist" \
    //     | rg -i appcheck        # key GACAppCheckDebugToken
    //
    // OJO: el log "(AppCheckCore) App Check debug token: 'XXX'" aparece
    // SIEMPRE al arrancar y NO significa que el server lo aceptó. La señal
    // de que está bien es la AUSENCIA de "App attestation failed".
    if (!kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider:
            kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    }

    // Crashlytics no soporta web — guardamos el wire bajo !kIsWeb. En web este
    // entry no se usa (el web target levanta main_coach_hub.dart), pero el
    // guard previene crashes si alguien lo corre por accidente con flutter
    // run -d chrome.
    if (!kIsWeb) {
      // Colección habilitada también en debug — necesario para validar el
      // wire desde el botón "Forzar crash" del Profile (también gated por
      // kDebugMode). El default del SDK es desactivar en debug; lo forzamos
      // a true para que los crashes lleguen al dashboard durante dev.
      // Trade-off aceptado: dashboard con noise de dev runs hasta que el
      // producto justifique filtrar por build flavor (Fase 7).
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

      // Errores sync del framework (build/layout/paint).
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Errores que escapan al engine (handlers nativos, gestos, etc.).
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    }

    // Analytics: colección habilitada explícitamente para que los eventos
    // lleguen tanto en debug (DebugView) como en release (dashboard real).
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

    // google_sign_in 7.x requires a single initialize() before any authenticate()
    // call. Both iOS and Android pick up clientId/serverClientId from their
    // native bundles (Info.plist URL scheme on iOS, google-services.json on
    // Android), so no explicit args are needed here.
    await GoogleSignIn.instance.initialize();

    const useEmulator = bool.fromEnvironment(
      'USE_EMULATOR',
      defaultValue: false,
    );
    if (useEmulator) {
      FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
      // Sin esto los callables salen a PRODUCCIÓN aunque corras contra el
      // emulador, así que ningún callable del proyecto se podía probar en
      // local. La región tiene que ser la misma con la que se construyen las
      // instancias en los providers (southamerica-east1): `instanceFor`
      // cachea por región, y apuntar otra deja la real sin redirigir.
      //
      // Requiere levantar el emulador de functions:
      //   ./scripts/emulator.sh   (fija --project treino-dev; el default de
      //   .firebaserc es `demo-treino`, ver #840)
      FirebaseFunctions.instanceFor(region: 'southamerica-east1')
          .useFunctionsEmulator('localhost', 5001);
    }

    // Eager-resolve SharedPreferences before runApp so that all providers
    // depending on sharedPreferencesProvider.requireValue (ThemeModeNotifier,
    // SidebarCollapsedNotifier) are safe at init time (ADR-LM-009).
    final prefs = await SharedPreferences.getInstance();

    runApp(
      ProviderScope(
        overrides: [
          // Synchronous by contract — see sharedPreferencesOverride (#543).
          sharedPreferencesOverride(prefs),
        ],
        child: const TreinoApp(),
      ),
    );
  }, (error, stack) {
    // Cualquier async uncaught dentro del zone cae acá.
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}
