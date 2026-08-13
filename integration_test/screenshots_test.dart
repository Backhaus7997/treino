// Store screenshot capture.
//
// Drives the app against the Firebase emulator with the seeded demo account and
// writes one PNG per store screen. This exists so screenshots are never taken
// from someone's real account — a store listing is public permanently.
//
// This is NOT a correctness test. It asserts only enough to fail loudly when a
// screen does not reach a capturable state, so a broken run never silently
// produces blank or half-loaded screenshots.
//
// Run it via the wrapper, which starts the emulator, seeds, and collects the
// PNGs into store/:
//
//   bash store/capture_screenshots.sh
//
// See store/README.md.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/app.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/firebase_options.dart';

const _demoEmail = 'martin@emulator.treino';
const _demoPassword = 'Emulator1234!';

late IntegrationTestWidgetsFlutterBinding binding;

/// Pumps a fixed budget then tries to settle.
///
/// `pumpAndSettle` alone times out on screens with looping animations, and
/// returning too early captures a half-drawn chart.
Future<void> _settle(WidgetTester tester, {int seconds = 3}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  } on FlutterError {
    // Continuous animation on screen — the fixed pump above is enough.
  }
}

bool _surfaceConverted = false;

Future<void> _shoot(WidgetTester tester, String name) async {
  await _settle(tester);
  // The Flutter surface must be converted before the binding can read pixels.
  // One-shot: calling it twice throws.
  if (!_surfaceConverted) {
    await binding.convertFlutterSurfaceToImage();
    _surfaceConverted = true;
  }
  await binding.takeScreenshot(name);
  debugPrint('CAPTURED $name');
}

/// Fails with a readable message instead of letting a blank screen through.
void _require(bool condition, String what) {
  if (!condition) {
    throw StateError(
      'Screenshot precondition failed: $what.\n'
      'The screen did not reach a capturable state, so the run was stopped '
      'rather than writing a misleading screenshot.',
    );
  }
}

void main() {
  binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);

    // Sign in directly rather than driving the login form: the form is not what
    // we are capturing, and doing it here keeps the run deterministic.
    await FirebaseAuth.instance.signOut();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _demoEmail,
      password: _demoPassword,
    );
  });

  testWidgets('capture store screenshots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        // Same override main.dart uses — synchronous by contract (#543).
        overrides: [sharedPreferencesOverride(prefs)],
        child: const TreinoApp(),
      ),
    );
    await _settle(tester, seconds: 8);

    _require(
      find.byType(MaterialApp).evaluate().isNotEmpty,
      'the app never mounted',
    );

    // The context MUST come from below the router, not from the MaterialApp
    // itself. `MaterialApp.router` inserts go_router's InheritedGoRouter
    // underneath it — between the Router and the root Navigator — so the
    // MaterialApp's own element sits ABOVE the thing `context.go` looks up, and
    // every call fails with "No GoRouter found in context". That is what made
    // this run finish with zero screenshots: it threw on the first navigation,
    // before a single `_shoot`.
    //
    // The root Navigator is the stable anchor: go_router builds it inside the
    // InheritedGoRouter, and it survives every navigation below.
    BuildContext ctx() => tester.element(find.byType(Navigator).first);

    // 3 — Insights. Captured first because it is the screen most sensitive to
    // seeded history, so a bad seed fails the run early instead of at the end.
    ctx().go('/home/insights');
    await _settle(tester, seconds: 5);
    await _shoot(tester, '03-insights');

    // 1 — Live session player.
    ctx().go('/workout/session/seed-routine-001/1?week=1');
    await _settle(tester, seconds: 5);
    await _shoot(tester, '01-session');

    // 2 — Routine detail.
    ctx().go('/workout/routine/seed-routine-001');
    await _settle(tester, seconds: 4);
    await _shoot(tester, '02-routine');

    // 4 — Coach: trainer discovery.
    ctx().go('/coach');
    await _settle(tester, seconds: 5);
    await _shoot(tester, '04-coach');

    // 5 — Feed / gym rankings.
    ctx().go('/feed?tab=rankings');
    await _settle(tester, seconds: 5);
    await _shoot(tester, '05-feed-rankings');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
