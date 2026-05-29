import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app/app.dart';
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
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(true);

      // Errores sync del framework (build/layout/paint).
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

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
    }

    runApp(const ProviderScope(child: TreinoApp()));
  }, (error, stack) {
    // Cualquier async uncaught dentro del zone cae acá.
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}
