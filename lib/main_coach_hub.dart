import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/coach_hub_app.dart';
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

  runApp(const ProviderScope(child: CoachHubApp()));
}
