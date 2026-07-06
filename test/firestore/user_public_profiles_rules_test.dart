import 'package:flutter_test/flutter_test.dart';

/// Firestore security rules tests for `userPublicProfiles/{uid}`.
///
/// These tests require the Firebase Emulator Suite running locally:
///   firebase emulators:exec --only firestore,auth \
///     "flutter test test/firestore/user_public_profiles_rules_test.dart"
///
/// Environment required:
///   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
///   GCLOUD_PROJECT=treino-dev
///
/// ⚠️ NOT EXECUTED FOR REAL — documented, not enforced. This repo has no
/// Dart-side (or JS-side, checked `functions/package.json`) harness capable
/// of running Firestore security-rules assertions against a live emulator —
/// `cloud_firestore`/`fake_cloud_firestore` do not enforce `firestore.rules`
/// at all (`fake_cloud_firestore` skips rule evaluation entirely; the
/// client SDK against a real emulator would need `@firebase/rules-unit-testing`,
/// which is not wired into this Flutter test target). The two pre-existing
/// files this mirrors (`payments_rules_test.dart`, `reviews_rules_test.dart`)
/// are ALSO CI-skipped stubs, never executed against a live emulator in this
/// repo — this is a known, accepted, pre-existing gap (design AD-7/Q5), not a
/// regression introduced by this change. Every `test(...)` below is marked
/// `skip:` and documents the exact manual/future-tooling steps a human (or a
/// future JS/rules-unit-testing harness) would need to run to verify it for
/// real. sdd-verify should treat rules enforcement here as UNVERIFIED BY
/// AUTOMATION — the actual security guarantee comes from the rule text in
/// `firestore.rules` (312-360ish) and this apply run's manual reasoning
/// (README of `sdd/rankings-integrity/apply-progress`), not from this file
/// passing in CI.
///
/// SCENARIOs covered (emulator-deferred, spec: user-public-profiles-layer):
///   - Field Allowlist: unknown field denied / known-fields-only succeeds.
///   - Owner-Only and UID Immutability: non-owner write denied; uid immutable.
///   - gymId Integrity: forged gymId denied; real own gymId accepted.
///   - CF-Write-Only Ranking Metrics: forged metric denied; re-asserting the
///     stored value is not rejected; Admin SDK (trigger) write bypasses rules
///     entirely — documented as a non-rule-based guarantee, not asserted here.
///   - Disable path (gym-rankings spec, Opt-In Disable — Unchanged): the
///     `clearRankingMetrics` deflate-to-default write on a true→false
///     `rankingOptIn` transition is explicitly ALLOWED by the metric pin's
///     disable-branch — this is the one case where a client CAN change a
///     metric value, and it is intentional (spec: "deflating one's own stats
///     is not a forgery vector").
///   - Type and Range Validation: out-of-range numeric metric rejected;
///     non-boolean rankingOptIn rejected.
///   - Read Access Unchanged: any authenticated user can still read.
///
/// REQ (user-public-profiles-layer): Firestore Rules — Field Allowlist,
/// Owner-Only and UID Immutability, gymId Integrity, CF-Write-Only Ranking
/// Metrics, Type and Range Validation, Read Access Unchanged.
/// rankings-integrity Phase 2 (PR#2). AD-3, AD-4, AD-6, AD-8.
void main() {
  group('userPublicProfiles Firestore rules — Field Allowlist', () {
    test(
      'write containing an unknown field is denied',
      () {
        // Setup (emulator):
        //   1. Authenticate as uid U.
        //   2. Client-SDK: set(merge:true) userPublicProfiles/U with
        //      {uid: U, isAdmin: true} (isAdmin is not in the 15-field set).
        //   3. Expect: permission-denied.
        //
        // Rule: request.resource.data.keys().hasOnly([15 fields]) on both
        // create and update.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'write containing only known fields succeeds (field-shape check passes)',
      () {
        // Setup (emulator):
        //   1. Authenticate as uid U.
        //   2. Client-SDK: set(merge:true) userPublicProfiles/U with only
        //      allowlisted fields (e.g. {uid: U, displayName: 'x'}).
        //   3. Expect: write succeeds (not rejected for field-shape reasons —
        //      still subject to owner/gymId/metric-pin/type checks below).
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );
  });

  group(
    'userPublicProfiles Firestore rules — Owner-Only and UID Immutability',
    () {
      test(
        'non-owner write is denied regardless of allowlist compliance',
        () {
          // Setup (emulator):
          //   1. Authenticate as uid A.
          //   2. Client-SDK: attempt set(merge:true) userPublicProfiles/B
          //      (different uid) with only allowlisted, valid-shaped fields.
          //   3. Expect: permission-denied (request.auth.uid == uid fails).
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'uid field cannot be changed on update',
        () {
          // Setup (emulator):
          //   1. Admin-SDK: seed userPublicProfiles/U with uid: 'U'.
          //   2. Authenticate as U.
          //   3. Client-SDK: update({uid: 'someone-else'}).
          //   4. Expect: permission-denied
          //      (request.resource.data.uid == resource.data.uid fails).
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );
    },
  );

  group('userPublicProfiles Firestore rules — gymId Integrity', () {
    test(
      'athlete cannot self-assign to a gym they do not attend',
      () {
        // Setup (emulator):
        //   1. Admin-SDK: seed users/U with {gymId: 'gym-A'}.
        //   2. Admin-SDK: seed userPublicProfiles/U with {uid: 'U'}.
        //   3. Authenticate as U.
        //   4. Client-SDK: update({gymId: 'gym-B'}).
        //   5. Expect: permission-denied — gymId must equal
        //      get(/databases/$(database)/documents/users/U).data.gymId.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'athlete can write their own real gymId',
      () {
        // Setup (emulator):
        //   1. Admin-SDK: seed users/U with {gymId: 'gym-A'}.
        //   2. Admin-SDK: seed userPublicProfiles/U with {uid: 'U'}.
        //   3. Authenticate as U.
        //   4. Client-SDK: update({gymId: 'gym-A'}).
        //   5. Expect: write succeeds (not rejected by the gymId-integrity
        //      check — value equals the private users/U.gymId).
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );

    test(
      'gymId omitted from the write payload is not rejected by the pin',
      () {
        // Setup (emulator): AD-4 — the pin is a no-op when the write does
        // not touch gymId at all (e.g. an update that only changes
        // rankingOptIn). Covers writes made before onboarding populates
        // users/{uid}.gymId as long as the write itself omits gymId.
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );
  });

  group(
    'userPublicProfiles Firestore rules — CF-Write-Only Ranking Metrics',
    () {
      test(
        'client raw-write of a forged metric value is denied',
        () {
          // Setup (emulator):
          //   1. Admin-SDK: seed userPublicProfiles/U with
          //      {uid: 'U', rankingOptIn: true, bestSquatKg: 100}.
          //   2. Authenticate as U.
          //   3. Client-SDK: update({bestSquatKg: 999}).
          //   4. Expect: permission-denied — bestSquatKg must equal
          //      resource.data.bestSquatKg (CF-write-only pin), UNLESS this
          //      write is also flipping rankingOptIn true→false (the disable
          //      branch — not the case here, rankingOptIn is untouched).
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'client write that re-asserts the existing metric value is not '
        'rejected by the pin',
        () {
          // Setup (emulator):
          //   1. Admin-SDK: seed userPublicProfiles/U with
          //      {uid: 'U', lifetimeVolumeKg: 3400}.
          //   2. Authenticate as U.
          //   3. Client-SDK: update({lifetimeVolumeKg: 3400, gymId: ...})
          //      (unchanged value, alongside another allowlisted field).
          //   4. Expect: write succeeds — value equals
          //      resource.data.lifetimeVolumeKg.
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'disable transition (rankingOptIn true->false) may reset all 4 '
        'metrics to their default even though the pin would otherwise '
        'block the change (gym-rankings: Opt-In Disable — Unchanged)',
        () {
          // Setup (emulator):
          //   1. Admin-SDK: seed userPublicProfiles/U with
          //      {uid: 'U', rankingOptIn: true, lifetimeVolumeKg: 3400,
          //       bestSquatKg: 110, bestBenchKg: 80, bestDeadliftKg: 150}.
          //   2. Authenticate as U.
          //   3. Client-SDK: update({rankingOptIn: false,
          //      lifetimeVolumeKg: 0, bestSquatKg: null, bestBenchKg: null,
          //      bestDeadliftKg: null}) — this is exactly
          //      UserPublicProfileRepository.clearRankingMetrics's payload.
          //   4. Expect: write succeeds — the metric pin has an explicit
          //      disable-branch: when the write's rankingOptIn is `false`
          //      AND resource.data.rankingOptIn (before) was `true`, each
          //      metric field may equal its stored value OR its fixed
          //      default (0 / null). Per spec gym-rankings "Opt-In Disable —
          //      Unchanged, Client-Initiated": deflating one's own stats is
          //      not a forgery vector, this remains a direct client write.
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'disable-branch does NOT allow setting metrics to a non-default '
        'value while flipping rankingOptIn to false (still no forgery path)',
        () {
          // Setup (emulator):
          //   1. Admin-SDK: seed userPublicProfiles/U with
          //      {uid: 'U', rankingOptIn: true, bestSquatKg: 110}.
          //   2. Authenticate as U.
          //   3. Client-SDK: update({rankingOptIn: false, bestSquatKg: 999}).
          //   4. Expect: permission-denied — the disable-branch only
          //      tolerates the fixed defaults (0 / null), not arbitrary
          //      values, so this is not a laundering path for a forged
          //      metric via a disable/re-enable round trip.
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'server-side recompute writes new metric values via Admin SDK',
        () {
          // NOT a rules assertion — documented for completeness only. The
          // recompute trigger (functions/src/ranking-aggregate.ts,
          // rankingAggregateOnSession / rankingAggregateOnOptIn) writes via
          // the Admin SDK, which bypasses Firestore rule evaluation
          // entirely. No rule path "allows" this write; it is simply not
          // subject to rules. Covered for real by
          // functions/src/__tests__/ranking-aggregate.test.ts (14/14 green
          // against the Firestore emulator, Phase 1) — that suite does not
          // load firestore.rules at all (Admin SDK bypass), so it does not
          // change whether THIS file's rules are enforced; it just confirms
          // the trigger itself still writes correctly, which is orthogonal.
        },
        skip: 'documentation only — no rule assertion applies (Admin SDK '
            'bypasses rules); see functions/src/__tests__/ranking-aggregate.test.ts',
      );
    },
  );

  group(
    'userPublicProfiles Firestore rules — Type and Range Validation',
    () {
      test(
        'out-of-range numeric metric value is rejected',
        () {
          // Setup (emulator):
          //   1. Authenticate as uid U with an existing profile.
          //   2. Client-SDK: update({bestSquatKg: 5000}) (> 1000 bound,
          //      AD-8) — or update creating the doc with
          //      lifetimeVolumeKg: 999999999 (> 100_000_000 bound).
          //   3. Expect: permission-denied.
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );

      test(
        'non-boolean rankingOptIn value is rejected',
        () {
          // Setup (emulator):
          //   1. Authenticate as uid U.
          //   2. Client-SDK: update({rankingOptIn: 'yes'}).
          //   3. Expect: permission-denied — rankingOptIn is not `is bool`.
        },
        skip: 'emulator required — run with firebase emulators:exec',
      );
    },
  );

  group('userPublicProfiles Firestore rules — Read Access Unchanged', () {
    test(
      'authenticated user reads any profile after the rules hardening',
      () {
        // Setup (emulator):
        //   1. Admin-SDK: seed userPublicProfiles/OTHER.
        //   2. Authenticate as any uid.
        //   3. Client-SDK: get(userPublicProfiles/OTHER).
        //   4. Expect: read succeeds, unchanged by this PR's rule additions
        //      (allow read: if request.auth != null — untouched).
      },
      skip: 'emulator required — run with firebase emulators:exec',
    );
  });
}
