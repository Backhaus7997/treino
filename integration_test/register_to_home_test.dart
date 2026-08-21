// ─────────────────────────────────────────────────────────────────────────────
// E2E (b) — Register → Profile-setup → Home
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a brand-new athlete signs up on /register (email + password +
// Terms), gets routed to /profile-setup (because the freshly created
// users/{uid} doc has displayName == null), completes the 4 onboarding steps,
// and the submit persists displayName → router's onboarding-complete gate
// pushes them to /home. See lib/app/router.dart `authRedirect`.
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT:
//   • No pre-seeded user needed — this flow CREATES one. But the Auth emulator
//     must be empty of `kNewEmail` (use a per-run unique email, below) so
//     signUp does not fail with email-already-in-use.
//   • The AuthService.signUpWithEmail path creates users/{uid} with
//     displayName == null; ProfileSetup's submit fills it. No manual Firestore
//     seed required.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/profile_setup/presentation/profile_setup_flow.dart';

import 'support/e2e_helpers.dart';

/// Per-run unique email so re-runs don't collide in the Auth emulator.
/// TODO(seed): if you prefer a fixed account, clear it from the Auth emulator
/// between runs instead.
final String kNewEmail =
    'e2e.new+${DateTime.now().millisecondsSinceEpoch}@treino.test';
const String kNewPassword = 'Treino1234';
const String kNewUsername = 'e2e_athlete';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets(
      'register → profile-setup → home: new athlete completes onboarding',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    // /welcome → tap primary CTA "EMPEZAR" (authWelcomeCta) → /register.
    await tester.tap(find.text('EMPEZAR'));
    await tester.pumpAndSettle();

    // Fill the register form: email, password, confirm password.
    final fields = find.byType(TextFormField);
    expect(
      fields,
      findsNWidgets(3),
      reason: 'RegisterScreen has email + password + confirm fields',
    );
    await tester.enterText(fields.at(0), kNewEmail);
    await tester.enterText(fields.at(1), kNewPassword);
    await tester.enterText(fields.at(2), kNewPassword);
    await tester.pump();

    // Accept Terms — the checkbox gates the submit button (`_canSubmit`).
    // TODO(finder): TermsCheckbox renders a tappable row; tapping the visible
    // Checkbox is the stable target. If the label intercepts the tap, switch to
    // find.byType(TermsCheckbox) and tap its center.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();

    // "CREAR CUENTA" (authRegisterCta).
    await tester.tap(find.text('CREAR CUENTA'));
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // New user → redirected to the profile-setup flow.
    expect(
      find.byType(ProfileSetupFlow),
      findsOneWidget,
      reason: 'signup with displayName == null routes to /profile-setup',
    );

    // ── Step 1: username + avatar ────────────────────────────────────────────
    // The first field of Step1UsernameAvatar is the username AuthInput.
    await tester.enterText(find.byType(TextFormField).first, kNewUsername);
    await tester.pump();
    await tester.tap(find.text('SIGUIENTE'));
    await tester.pumpAndSettle();

    // ── Step 2: gym ──────────────────────────────────────────────────────────
    // TODO(seed/finder): Step2Gym gates `canGoNext` on a gym selection (search
    // + pick, or "entreno solo"). Drive the real selector here — e.g. tap the
    // "Entreno por mi cuenta / sin gimnasio" affordance so the step validates.
    await tester.tap(find.text('SIGUIENTE'));
    await tester.pumpAndSettle();

    // ── Step 3: experience + gender ──────────────────────────────────────────
    // TODO(finder): tap one experience-level chip and one gender chip so
    // `canGoNext` turns true before advancing.
    await tester.tap(find.text('SIGUIENTE'));
    await tester.pumpAndSettle();

    // ── Step 4: weight + height → submit ("EMPEZAR") ─────────────────────────
    // TODO(finder): enter weight + height in the two numeric fields; the last
    // step's primary button is labelled "EMPEZAR" and calls notifier.submit().
    await tester.tap(find.text('EMPEZAR'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Submit persisted displayName → onboarding-complete gate → /home.
    expect(
      find.byType(HomeScreen),
      findsOneWidget,
      reason: 'completing profile-setup should land the new athlete on /home',
    );
  });
}
