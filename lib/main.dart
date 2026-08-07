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
    // ⚠️ ENFORCEMENT ESTÁ ACTIVO para Cloud Firestore en `treino-dev`
    // (verificado 2026-07-27). El modo se controla desde Firebase Console,
    // no desde código, así que este comentario puede quedar desactualizado
    // otra vez — chequealo en Console → App Check → APIs antes de creerle.
    //
    // Consecuencia práctica: en un device de dev cuyo debug token NO esté
    // registrado, TODA escritura a Firestore se rechaza. No falla el login
    // (Auth no está enforced), falla lo que venga después, y el síntoma no
    // se parece a App Check — p.ej. crear cuenta muere con "Hubo un problema
    // creando tu perfil" (AuthService.signUpWithEmail → getOrCreate).
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
      //   firebase emulators:start --only firestore,auth,functions
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
