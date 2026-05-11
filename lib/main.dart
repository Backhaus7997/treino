import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app/app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
}
