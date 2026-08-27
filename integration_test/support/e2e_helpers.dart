// ─────────────────────────────────────────────────────────────────────────────
// E2E shared helpers — TREINO integration_test suites (QA Fase 6)
// ─────────────────────────────────────────────────────────────────────────────
//
// This file is INFRASTRUCTURE, not a test suite: it has no `main()` and is not
// discovered/executed by `flutter test integration_test/`. Each *_test.dart in
// this folder imports it to share the Firebase-emulator bootstrap and a couple
// of driving helpers.
//
// REQUIREMENT: the `integration_test` package is NOT yet in dev_dependencies.
// See integration_test/README.md for the one-step enable command. Until it is
// added, these files intentionally reference `package:integration_test/...`
// (via the suites, not here) and will not compile — that is by design; QA
// leaves them as a ready-to-run deliverable.
//
// EMULATORS ONLY — NEVER cloud. Auth 9099 / Firestore 8080 on 127.0.0.1.
// Start them first with:  ./scripts/emulator.sh  (JAVA_HOME → JDK 21).
// El script fija `--project treino-dev`; el default de .firebaserc es
// `demo-treino` y dejaría los datos en otro namespace (#840).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:treino/app/app.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/firebase_options.dart';

/// Loopback host for the Firebase emulator suite. NEVER point these at cloud.
/// `127.0.0.1` (not `localhost`) so it resolves identically on the Android AVD
/// bridge and desktop hosts — the app's own `main.dart` uses `localhost`, but
/// for the AVD the numeric loopback is the safe, unambiguous choice.
const String kEmulatorHost = '127.0.0.1';
const int kAuthEmulatorPort = 9099;
const int kFirestoreEmulatorPort = 8080;

/// Guards `useAuthEmulator`/`useFirestoreEmulator` so re-running suites in one
/// process does not throw "already configured".
bool _emulatorsWired = false;

/// Initializes Firebase and pins Auth + Firestore to the local emulators.
/// Call once from each suite's `setUpAll`. Idempotent across suites in the same
/// test process.
Future<void> initFirebaseForEmulators() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (_emulatorsWired) return;

  await FirebaseAuth.instance.useAuthEmulator(kEmulatorHost, kAuthEmulatorPort);
  FirebaseFirestore.instance.useFirestoreEmulator(
    kEmulatorHost,
    kFirestoreEmulatorPort,
  );
  // Deterministic reads in E2E: no offline cache masking emulator state.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  _emulatorsWired = true;
}

/// Pumps the REAL [TreinoApp] (same widget `main.dart` runs) inside a
/// [ProviderScope], eager-overriding [sharedPreferencesProvider] exactly like
/// production does (ADR-LM-009) so `.requireValue` is safe at provider init.
///
/// [overrides] lets a suite stub providers that would otherwise reach out to
/// device-only services.
///
/// TODO(e2e-infra): [TreinoApp.initState] eagerly reads the FCM / notification
/// providers (`fcmLifecycleProvider`, `fcmServiceProvider`). On a bare AVD
/// without Google Play services — or against the emulator project — token
/// registration can throw and block first frame. If boot hangs, pass overrides
/// here that stub `fcmServiceProvider` / `notificationProviders` with fakes.
Future<void> pumpTreinoApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((_) async => prefs),
        ...overrides,
      ],
      child: const TreinoApp(),
    ),
  );
  // Splash → redirect resolves (anonymous → /welcome, or → /home when a
  // session is already restored). Give async auth/profile streams a beat.
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

/// Signs the Firebase user out so a suite starts from the anonymous
/// `/welcome` gate regardless of a session left over by a previous suite.
Future<void> ensureSignedOut(WidgetTester tester) async {
  await FirebaseAuth.instance.signOut();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Drives the UI login flow: `/welcome` → tap "Iniciar sesión" → fill the two
/// [TextFormField]s → tap "ENTRAR" (`authLoginCta`) → settle on `/home`.
///
/// Precondition: a verified user with [email]/[password] must exist in the
/// Auth emulator. TODO(seed) — see each suite for the seeding contract.
Future<void> signInViaUi(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  final signInLink = find.text('Iniciar sesión');
  if (signInLink.evaluate().isNotEmpty) {
    await tester.tap(signInLink.first);
    await tester.pumpAndSettle();
  }

  final fields = find.byType(TextFormField);
  expect(
    fields,
    findsWidgets,
    reason: 'LoginScreen should render email + password fields',
  );
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  await tester.pump();

  await tester.tap(find.text('ENTRAR'));
  await tester.pumpAndSettle(const Duration(seconds: 4));
}

/// Navigates the live GoRouter to [location] (optionally passing [extra]).
/// Used by suites that need to deep-link past a seeded document (a routine,
/// a chat) rather than tapping through every intermediate screen.
Future<void> goTo(
  WidgetTester tester,
  String location, {
  Object? extra,
}) async {
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go(location, extra: extra);
  await tester.pumpAndSettle(const Duration(seconds: 3));
}
