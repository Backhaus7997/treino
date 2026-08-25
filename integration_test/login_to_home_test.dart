// ─────────────────────────────────────────────────────────────────────────────
// E2E (a) — Login → Home
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: an existing, verified athlete opens the app anonymous, signs
// in with email/password on /login, and lands on /home (the 5-tab shell).
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT (do before running — via emulator UI, the Admin SDK, or a
// `firebase emulators:exec` seed script):
//   • Auth emulator: a user { email: kSeedEmail, password: kSeedPassword },
//     emailVerified = true.
//   • Firestore emulator: users/{uid} with a non-null `displayName` (otherwise
//     authRedirect sends the user to /profile-setup, not /home — see
//     lib/app/router.dart `authRedirect`).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/home/home_screen.dart';

import 'support/e2e_helpers.dart';

// TODO(seed): replace with the credentials of the seeded emulator user.
const String kSeedEmail = 'e2e.athlete@treino.test';
const String kSeedPassword = 'Treino1234';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('login → home: verified athlete signs in and reaches /home',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    // Anonymous boot resolves to the welcome gate.
    expect(
      find.text('Iniciar sesión'),
      findsWidgets,
      reason: 'anonymous user should land on /welcome',
    );

    await signInViaUi(tester, email: kSeedEmail, password: kSeedPassword);

    // Landed on the home tab of the shell.
    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: 'successful login should redirect the athlete to /home',
    );
  });
}
