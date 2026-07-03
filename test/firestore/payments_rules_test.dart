import 'package:flutter_test/flutter_test.dart';

/// Firestore security rules tests for `payments/{paymentId}`.
///
/// These tests require the Firebase Emulator Suite running locally:
///   firebase emulators:exec --only firestore,auth \
///     "flutter test test/firestore/payments_rules_test.dart"
///
/// Environment required:
///   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
///   GCLOUD_PROJECT=treino-dev
///
/// SCENARIOs covered (emulator-deferred):
///   SCENARIO-VENC-14: client update that changes dueAt is DENIED.
///   SCENARIO-VENC-15: markPaid update {status: paid, paidAt: <ts>} is ALLOWED.
///
/// REQ-VENC-13. payments-vencimientos PR1.
void main() {
  group('payments Firestore rules — dueAt write protection (REQ-VENC-13)', () {
    // SCENARIO-VENC-14
    test(
      'SCENARIO-VENC-14: client update that sets dueAt is DENIED',
      () async {
        // Setup (emulator):
        //   1. Admin-SDK: create a payments doc for trainerId=tA, athleteId=aA
        //      with dueAt=null (legacy doc, or CF-created doc).
        //   2. Authenticate as tA (trainer).
        //   3. Client-SDK: attempt update({dueAt: Timestamp.now()}).
        //   4. Expect: permission-denied exception.
        //
        // The tightened rule pins dueAt equal-to-existing via:
        //   request.resource.data.get('dueAt', null) == resource.data.get('dueAt', null)
        // So any mutation to dueAt is rejected.
        //
        // This test is a STUB — the full emulator interaction would use
        // @firebase/rules-unit-testing (JS) or a Dart emulator client.
        // Marking skipped until emulator is available.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    // SCENARIO-VENC-15
    test(
      'SCENARIO-VENC-15: markPaid update {status, paidAt} is ALLOWED',
      () async {
        // Setup (emulator):
        //   1. Admin-SDK: create a payments doc for trainerId=tA.
        //   2. Authenticate as tA.
        //   3. Client-SDK: attempt update({status: 'paid', paidAt: Timestamp.now()}).
        //   4. Expect: write succeeds (no exception).
        //
        // The tightened rule allows hasOnly([...all-fields...]) where the only
        // fields CHANGING are status and paidAt, which are both in the allowed set,
        // and the dueAt equality check passes because neither side changes it.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );
  });
}
