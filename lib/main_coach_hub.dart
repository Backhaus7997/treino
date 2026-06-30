import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/coach_hub_app.dart';
import 'core/persistence/shared_prefs_provider.dart';
import 'firebase_options.dart';

/// Entry point del TREINO Coach Hub (Flutter Web target).
///
/// Es paralelo a `lib/main.dart` (mobile app). Mismo backend Firebase,
/// distinto shell de UI: routing acotado al rol trainer, sin bottom bar,
/// sin todos los tabs mobile-specific.
///
/// Correr local:
///   flutter run -t lib/main_coach_hub.dart -d chrome
///
/// Build para hosting:
///   flutter build web -t lib/main_coach_hub.dart
///   firebase deploy --only hosting:coach-hub-dev
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Analytics: colección habilitada para tracking de actions del Coach Hub
  // web. Crashlytics no aplica acá (no soporta web).
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

  // Coach Hub MVP NO usa Google Sign-In (decisión #2 del propose). Solo
  // email/password. Por eso NO inicializamos `GoogleSignIn.instance` acá
  // — el plugin web es scope aparte (Etapa 7.5 o follow-up).

  const useEmulator = bool.fromEnvironment(
    'USE_EMULATOR',
    defaultValue: false,
  );
  if (useEmulator) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }

  // Eager-resolve SharedPreferences before runApp so that providers depending
  // on sharedPreferencesProvider.requireValue (ThemeModeNotifier,
  // SidebarCollapsedNotifier) are safe at init time on the web target too
  // (ADR-LM-009). Mirrors lib/main.dart.
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) async => prefs),
      ],
      child: const CoachHubApp(),
    ),
  );
}
