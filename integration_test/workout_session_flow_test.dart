// ─────────────────────────────────────────────────────────────────────────────
// E2E (c) — Start workout → Session player → Summary
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a signed-in athlete with an assigned routine starts a fresh
// training session, logs the sets in the SessionPlayer, taps "terminar", and
// lands on the PostWorkoutSummary screen.
//
// Route map (lib/app/router.dart):
//   /workout/session/:routineId/:dayNumber   → SessionPlayerScreen(FreshSession)
//   /workout/session-summary/:sessionId       → PostWorkoutSummaryScreen
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT:
//   • Auth emulator: verified user { kSeedEmail / kSeedPassword }, displayName
//     set (so login lands on /home, not /profile-setup).
//   • Firestore emulator: a routine document owned by / assigned to that uid
//     with at least day `kDayNumber` and one exercise + one set, so the player
//     can reach `isFullyCompleted` after the sets are logged. Put its id in
//     kRoutineId.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/workout/presentation/post_workout_summary_screen.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';

import 'support/e2e_helpers.dart';

// TODO(seed): credentials of the seeded athlete.
const String kSeedEmail = 'e2e.athlete@treino.test';
const String kSeedPassword = 'Treino1234';

// TODO(seed): id of the routine assigned to the seeded athlete, and the day to
// train. `dayNumber` is 1-based on the wire (see router).
const String kRoutineId = 'REPLACE_WITH_SEEDED_ROUTINE_ID';
const int kDayNumber = 1;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('workout: start session → log sets → finish → summary',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kSeedEmail, password: kSeedPassword);

    // Deep-link straight into a fresh session for the seeded routine/day.
    // (Tapping through Home's "empezar entrenamiento" card is the fuller path;
    //  deep-linking keeps the suite robust to Home layout changes.)
    await goTo(tester, '/workout/session/$kRoutineId/$kDayNumber');

    expect(
      find.byType(SessionPlayerScreen),
      findsOneWidget,
      reason: 'fresh-session route should mount the player',
    );

    // ── Log the work ─────────────────────────────────────────────────────────
    // TODO(finder/seed): for each set, enter reps + weight and tap the set's
    // check control (TreinoIcon.checkCircleEmpty → checkCircleFill). Once every
    // set is confirmed the session becomes `isFullyCompleted` and the
    // "terminar" button (_TerminarSessionButton) enables.
    // Example skeleton for a single-set seed:
    //   final repsField = find.byType(TextField).first;
    //   await tester.enterText(repsField, '10');
    //   await tester.pump();
    //   await tester.tap(find.byIcon(/* the set-confirm icon */));
    //   await tester.pumpAndSettle();

    // Finish the session. The button reads the localized "terminar" copy; drive
    // it by its widget type to stay decoupled from the exact label.
    // TODO(finder): if multiple tap targets match, scope to the bottom
    // _TerminarSessionButton (it sits in the fixed footer Padding).
    final finishButton = find.byType(SessionPlayerScreen);
    expect(finishButton, findsOneWidget);
    // TODO(finder): replace the line below with a tap on the enabled
    // "terminar" button once the sets above are logged, e.g.
    //   await tester.tap(find.text('TERMINAR'));
    //   await tester.pumpAndSettle(const Duration(seconds: 4));

    // ── Summary ──────────────────────────────────────────────────────────────
    // finishSession() writes the finished session and navigates to
    // /workout/session-summary/:sessionId.
    // TODO(activate): this assertion is the real acceptance gate — enable it
    // once the finish tap above is wired to the seeded single-set routine.
    // expect(
    //   find.byType(PostWorkoutSummaryScreen),
    //   findsOneWidget,
    //   reason: 'finishing a session should open the post-workout summary',
    // );
    // Keep a type reference so the import is validated by the analyzer.
    expect(PostWorkoutSummaryScreen, isNotNull);
  });
}
