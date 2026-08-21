// ─────────────────────────────────────────────────────────────────────────────
// E2E (e) — Edit my own routine
// ─────────────────────────────────────────────────────────────────────────────
// Critical flow: a signed-in athlete opens the self-routine editor for one of
// their existing personal routines (SelfCreating mode), changes something (a
// day name), saves, and the change persists.
//
// Route (lib/app/router.dart):
//   /workout/my-routine-editor  (extra: existingRoutineId)
//       → RoutineEditorScreen(mode: SelfCreating(existingRoutineId: extra))
//   `extra == null` means CREATE; a non-null id means EDIT.
//
// Runs against the Firebase EMULATORS only (Auth 9099, Firestore 8080 on
// 127.0.0.1). Never cloud. See integration_test/README.md to enable + run.
//
// SEED CONTRACT:
//   • Auth emulator: verified athlete { kSeedEmail / kSeedPassword }, displayName
//     set.
//   • Firestore emulator: a personal routine authored by that athlete (the
//     SelfCreating source collection — see RoutineEditorScreen / its repository)
//     with at least one day. Put its id in kRoutineId.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

import 'support/e2e_helpers.dart';

// TODO(seed): credentials of the seeded athlete.
const String kSeedEmail = 'e2e.athlete@treino.test';
const String kSeedPassword = 'Treino1234';

// TODO(seed): id of a personal routine owned by the seeded athlete.
const String kRoutineId = 'REPLACE_WITH_SEEDED_SELF_ROUTINE_ID';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initFirebaseForEmulators);

  testWidgets('my routine: open editor in edit mode → change → save',
      (tester) async {
    await ensureSignedOut(tester);
    await pumpTreinoApp(tester);

    await signInViaUi(tester, email: kSeedEmail, password: kSeedPassword);

    // Deep-link into the editor in EDIT mode by passing the existing id as
    // `extra` (the route maps a non-null String extra → SelfCreating(existingRoutineId)).
    await goTo(tester, '/workout/my-routine-editor', extra: kRoutineId);

    expect(
      find.byType(RoutineEditorScreen),
      findsOneWidget,
      reason: 'self-routine editor should mount in SelfCreating edit mode',
    );

    // ── Edit ─────────────────────────────────────────────────────────────────
    // TODO(finder): change a day name (or a set's reps). The day-name field is
    // an editable text field in the editor body; enter new text and pump.
    //   final dayNameField = find.byType(TextField).first;
    //   await tester.enterText(dayNameField, 'Día A — Empuje (editado E2E)');
    //   await tester.pump();

    // ── Save ─────────────────────────────────────────────────────────────────
    // TODO(finder): tap the editor's primary save/update action. In edit mode
    // the label comes from l10n.workoutSelfEditorUpdateLabel; drive it by text
    // or by the AppBar action button.
    //   await tester.tap(find.text('GUARDAR')); // or the update label
    //   await tester.pumpAndSettle(const Duration(seconds: 4));

    // ── Verify persistence ───────────────────────────────────────────────────
    // TODO(activate): after saving, assert the edited value round-tripped —
    // either by reading the routine doc back from the Firestore emulator, or by
    // re-opening the editor and finding the new day name. This is the real
    // acceptance gate; enable it once the edit + save taps above are wired to
    // the seeded routine's actual field structure.
    //   expect(find.text('Día A — Empuje (editado E2E)'), findsOneWidget);
  });
}
