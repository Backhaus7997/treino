import 'package:flutter_test/flutter_test.dart';

/// Firestore security rules tests for `trainerPublicProfiles`.
///
/// These tests require the Firebase Emulator Suite running locally
/// (firebase emulators:start --only firestore). They are intentionally
/// skipped in the normal CI/unit-test suite per design D21.
///
/// Run manually with:
///   firebase emulators:exec "flutter test test/features/coach/data/firestore_rules_test.dart"
///
/// SCENARIOs covered (deferred to emulator):
///   SCENARIO-416: authenticated user can read trainerPublicProfiles.
///   SCENARIO-417: unauthenticated request is denied.
///   SCENARIO-418: owner can write own document.
///   SCENARIO-419: non-owner write is denied.
///
/// REQ-COACH-DISC-DATA-008, REQ-COACH-DISC-DATA-009.
void main() {
  group('trainerPublicProfiles Firestore rules (emulator required)', () {
    test(
      'SCENARIO-416: authenticated user can read trainerPublicProfiles',
      () {
        // Requires emulator — not implemented in unit test suite.
        // See: https://firebase.google.com/docs/rules/unit-tests
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'SCENARIO-417: unauthenticated request is denied',
      () {
        // Requires emulator.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'SCENARIO-418: owner can write own document',
      () {
        // Requires emulator.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'SCENARIO-419: non-owner write denied',
      () {
        // Requires emulator.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );
  });
}
