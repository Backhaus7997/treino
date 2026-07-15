'use strict';

/**
 * Firestore Security Rules test suite — athlete-self-measurements.
 *
 * Covers the widened `measurements` create + read rules that let an athlete
 * log their OWN body measurements, and let a linked+consented trainer read
 * those self-logged entries.
 *
 * Requirements (openspec/changes/athlete-self-measurements/spec.md):
 *  - REQ-ASM-01  widened create (athlete-self branch + preserved trainer branch)
 *  - REQ-ASM-02  author/subject read branches unchanged
 *  - REQ-ASM-03  trainer reads self-logged doc IFF session_shares AND profile_shares name them
 *  - REQ-ASM-04  visibility follows the CURRENT trainer, never one frozen at consent time
 *  - REQ-ASM-05  list satisfiability for the trainer's self-logged query
 *
 * Mechanism (design.md ADR-ASM-1): dual FIXED-PATH share-doc gate —
 * session_shares/{athleteId} (live link, CF-maintained) AND
 * profile_shares/{athleteId} (athlete consent) must BOTH name the trainer.
 * NOT the dead `sharedWithTrainer` bool (ADR-ASM-2).
 *
 * Run via: JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home" \
 *          bash scripts/test_rules.sh
 * (Requires the Firebase emulator; Firestore only.)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

// ── seed helpers (rules disabled — set up preconditions) ──────────────────────

async function seedUserRole(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({ uid, role });
  });
}

/** A self-logged measurement: recordedBy == athleteId. */
async function seedSelfLoggedMeasurement(docId, athleteId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('measurements').doc(docId).set({
      recordedBy: athleteId,
      athleteId,
      recordedAt: new Date(),
      weightKg: 80,
    });
  });
}

/** A trainer-recorded measurement: recordedBy == trainerId != athleteId. */
async function seedTrainerMeasurement(docId, { trainerId, athleteId }) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('measurements').doc(docId).set({
      recordedBy: trainerId,
      athleteId,
      recordedAt: new Date(),
      weightKg: 80,
    });
  });
}

/** session_shares/{athleteId} → {trainerId} (the CF-maintained live-link doc). */
async function seedSessionShare(athleteId, trainerId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('session_shares')
      .doc(athleteId)
      .set({ trainerId, updatedAt: new Date() });
  });
}

/** profile_shares/{athleteId} → {trainerId} (the athlete consent doc). */
async function seedProfileShare(athleteId, trainerId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('profile_shares')
      .doc(athleteId)
      .set({ trainerId, updatedAt: new Date() });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CREATE — REQ-ASM-01 (S1, S2, S3)
// ═══════════════════════════════════════════════════════════════════════════

// S1 — the NEW capability: athlete logs their OWN measurement.
test('S1 [REQ-ASM-01A]: athlete CAN create a measurement about themselves', async () => {
  await seedUserRole('athleteX', 'athlete');
  const athlete = testEnv.authenticatedContext('athleteX');
  await assertSucceeds(
    athlete.firestore().collection('measurements').doc('m-self').set({
      recordedBy: 'athleteX',
      athleteId: 'athleteX',
      recordedAt: new Date(),
      weightKg: 78,
    }),
  );
});

// S2 — forge vector stays closed (AD-1 regression anchor): athlete about ANOTHER.
test('S2 [REQ-ASM-01B]: athlete CANNOT create a measurement about another athlete', async () => {
  await seedUserRole('attacker', 'athlete');
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('measurements').doc('m-forge').set({
      recordedBy: 'attacker',
      athleteId: 'victim',
      recordedAt: new Date(),
      weightKg: 80,
    }),
  );
});

// S3 — legit-path anchor: trainer creates for an athlete (unchanged).
test('S3 [REQ-ASM-01C]: trainer CAN create a measurement for an athlete', async () => {
  await seedUserRole('coach', 'trainer');
  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('measurements').doc('m-coach').set({
      recordedBy: 'coach',
      athleteId: 'athleteX',
      recordedAt: new Date(),
      weightKg: 80,
    }),
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// READ — REQ-ASM-02, REQ-ASM-03, REQ-ASM-04 (S4–S10)
// ═══════════════════════════════════════════════════════════════════════════

// S4 — the NEW read: consented + live-linked trainer reads a self-logged doc.
test('S4 [REQ-ASM-03A]: consented + live-linked trainer CAN read a self-logged measurement', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedSessionShare('athleteX', 'coach'); // live link
  await seedProfileShare('athleteX', 'coach'); // consent
  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('measurements').doc('m1').get(),
  );
});

// S5 — D3 consent gate: linked but NOT consented → denied.
test('S5 [REQ-ASM-03B]: linked but NOT consented trainer CANNOT read a self-logged measurement', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedSessionShare('athleteX', 'coach'); // live link only, no consent
  const coach = testEnv.authenticatedContext('coach');
  await assertFails(
    coach.firestore().collection('measurements').doc('m1').get(),
  );
});

// S6 — D2 live-link gate: consented but link gone → denied.
test('S6 [REQ-ASM-03C]: consented but no live link → trainer CANNOT read a self-logged measurement', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedProfileShare('athleteX', 'coach'); // consent only, no live link
  const coach = testEnv.authenticatedContext('coach');
  await assertFails(
    coach.firestore().collection('measurements').doc('m1').get(),
  );
});

// S7 — THE HEADLINE D2 test: visibility follows the CURRENT trainer, not a
// frozen id. session_shares repointed to B; stale profile_shares still names A.
// A must be DENIED (the CF live-link gate revokes A even before re-consent).
test('S7 [REQ-ASM-04]: an OLD trainer is denied once the live link moved to a new trainer', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedSessionShare('athleteX', 'trainerB'); // link moved to B
  await seedProfileShare('athleteX', 'trainerA'); // stale consent still names A
  const trainerA = testEnv.authenticatedContext('trainerA');
  await assertFails(
    trainerA.firestore().collection('measurements').doc('m1').get(),
  );
});

// S8 — neither share doc → denied.
test('S8 [REQ-ASM-03D]: unlinked + unconsented trainer CANNOT read a self-logged measurement', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  const stranger = testEnv.authenticatedContext('stranger');
  await assertFails(
    stranger.firestore().collection('measurements').doc('m1').get(),
  );
});

// S9 — author branch anchor: trainer reads their OWN recorded doc (no shares).
test('S9 [REQ-ASM-02A]: trainer CAN read a measurement they themselves recorded', async () => {
  await seedTrainerMeasurement('m1', { trainerId: 'coach', athleteId: 'athleteX' });
  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('measurements').doc('m1').get(),
  );
});

// S10 — subject branch anchor: athlete reads their own self-logged doc.
test('S10 [REQ-ASM-02B]: athlete CAN read their own self-logged measurement', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  const athlete = testEnv.authenticatedContext('athleteX');
  await assertSucceeds(
    athlete.firestore().collection('measurements').doc('m1').get(),
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// LIST (trainer vantage query, REQ-ASM-05) — S11, S12
// ═══════════════════════════════════════════════════════════════════════════

// S11 — the trainer's self-logged LIST query (Q2) succeeds when linked+consented.
test('S11 [REQ-ASM-05A]: consented + linked trainer CAN list an athlete\'s self-logged measurements', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedSessionShare('athleteX', 'coach');
  await seedProfileShare('athleteX', 'coach');
  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach
      .firestore()
      .collection('measurements')
      .where('athleteId', '==', 'athleteX')
      .where('recordedBy', '==', 'athleteX')
      .get(),
  );
});

// S12 — the same list run by a NON-consented trainer is denied wholesale
// (proves the client MUST tolerate the permission-denied on Q2).
test('S12 [REQ-ASM-05B]: non-consented trainer CANNOT list an athlete\'s self-logged measurements', async () => {
  await seedSelfLoggedMeasurement('m1', 'athleteX');
  await seedSessionShare('athleteX', 'coach'); // linked but NOT consented
  const coach = testEnv.authenticatedContext('coach');
  await assertFails(
    coach
      .firestore()
      .collection('measurements')
      .where('athleteId', '==', 'athleteX')
      .where('recordedBy', '==', 'athleteX')
      .get(),
  );
});
