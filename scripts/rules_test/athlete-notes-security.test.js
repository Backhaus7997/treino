'use strict';

/**
 * Firestore Security Rules test suite — athlete_notes identity hardening
 * (QA audit 2026-07-30, finding C1).
 *
 * `athlete_notes/{trainerId}_{athleteId}` holds the trainer's PRIVATE coaching
 * note about an athlete — the athlete must never read it. Before this fix the
 * block combined `create, update` validating only the POST-image
 * (`request.resource.data.trainerId == request.auth.uid`), which — combined
 * with the deterministic, enumerable docId and the repo's `set(merge:true)` —
 * left two holes:
 *
 *   SQUAT   — an attacker creates the doc at a VICTIM trainer's docId with
 *             their own trainerId, locking the victim out (their later update
 *             fails: resource.data.trainerId != their uid).
 *   HIJACK  — a third party reassigns trainerId via merge (preserving `note`)
 *             and then reads the private note, because the read gate keys on
 *             `resource.data.trainerId` — the very field update let them
 *             rewrite.
 *
 * Fix: split create/update. Create binds the docId to the signer's uid; update
 * pins the pre-image so trainerId/athleteId are immutable (mirrors the sibling
 * follow_up_entries / nutrition_plans rules).
 *
 * Run via: JAVA_HOME=/opt/homebrew/opt/openjdk@21 bash scripts/test_rules.sh
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

// Seeds an existing note bypassing rules, so update/hijack/read scenarios have
// a real pre-image to attack.
async function seedNote(trainerId, athleteId, note) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('athlete_notes')
      .doc(`${trainerId}_${athleteId}`)
      .set({ trainerId, athleteId, note, updatedAt: new Date() });
  });
}

// ── Legit paths (must stay green) ───────────────────────────────────────────

test('LEGIT: a trainer can create their own note at {uid}_{athleteId}', async () => {
  const coach = testEnv.authenticatedContext('coach1');
  await assertSucceeds(
    coach.firestore().collection('athlete_notes').doc('coach1_athleteX').set({
      trainerId: 'coach1',
      athleteId: 'athleteX',
      note: 'Viene entrenando bien',
      updatedAt: new Date(),
    }),
  );
});

test('LEGIT: a trainer can update their own existing note', async () => {
  await seedNote('coach2', 'athleteX', 'nota vieja');
  const coach = testEnv.authenticatedContext('coach2');
  await assertSucceeds(
    coach.firestore().collection('athlete_notes').doc('coach2_athleteX').set(
      {
        trainerId: 'coach2',
        athleteId: 'athleteX',
        note: 'nota nueva',
        updatedAt: new Date(),
      },
      { merge: true },
    ),
  );
});

test('LEGIT: a trainer can read their own note', async () => {
  await seedNote('coach3', 'athleteX', 'secreta');
  const coach = testEnv.authenticatedContext('coach3');
  await assertSucceeds(
    coach.firestore().collection('athlete_notes').doc('coach3_athleteX').get(),
  );
});

test('LEGIT: reading a non-existent note is allowed (UI shows "sin nota")', async () => {
  const coach = testEnv.authenticatedContext('coach4');
  await assertSucceeds(
    coach.firestore().collection('athlete_notes').doc('coach4_nada').get(),
  );
});

test('LEGIT: an empty note is allowed (the inline editor can clear it)', async () => {
  const coach = testEnv.authenticatedContext('coach5');
  await assertSucceeds(
    coach.firestore().collection('athlete_notes').doc('coach5_athleteX').set({
      trainerId: 'coach5',
      athleteId: 'athleteX',
      note: '',
      updatedAt: new Date(),
    }),
  );
});

// ── Attacks (must be denied) ────────────────────────────────────────────────

test('SQUAT: an attacker cannot create a note at ANOTHER trainer docId', async () => {
  // Attacker's uid is 'attacker'; they target victim PF 'coachV' + athleteX.
  // Even naming trainerId=attacker (to pass the post-image check), the docId
  // binding rejects it because coachV_athleteX != attacker_athleteX.
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('athlete_notes').doc('coachV_athleteX').set({
      trainerId: 'attacker',
      athleteId: 'athleteX',
      note: 'squat',
      updatedAt: new Date(),
    }),
  );
});

test('SQUAT: an attacker cannot forge the docId to name a foreign trainerId', async () => {
  // The mirror check: docId matches but trainerId is a foreign uid.
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('athlete_notes').doc('coachV_athleteX').set({
      trainerId: 'coachV',
      athleteId: 'athleteX',
      note: 'squat',
      updatedAt: new Date(),
    }),
  );
});

test('HIJACK: an attacker cannot reassign trainerId on a victim note via merge', async () => {
  await seedNote('coachV', 'athleteX', 'nota privada de coachV');
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('athlete_notes').doc('coachV_athleteX').set(
      { trainerId: 'attacker', updatedAt: new Date() },
      { merge: true },
    ),
  );
});

test('READ: an attacker cannot read another trainer note', async () => {
  await seedNote('coachV', 'athleteX', 'nota privada');
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('athlete_notes').doc('coachV_athleteX').get(),
  );
});

test('READ: the athlete cannot read the note written ABOUT them', async () => {
  // The most-motivated attacker: the athlete X reading what their PF wrote.
  await seedNote('coachV', 'athleteX', 'nota sobre athleteX');
  const athlete = testEnv.authenticatedContext('athleteX');
  await assertFails(
    athlete.firestore().collection('athlete_notes').doc('coachV_athleteX').get(),
  );
});

test('READ: the athlete cannot hijack-then-read by squatting their own uid', async () => {
  // Post-fix, the athlete cannot create/overwrite coachV_athleteX (docId
  // binds to coachV, not to the athlete's uid), so the read stays denied.
  await seedNote('coachV', 'athleteX', 'nota sobre athleteX');
  const athlete = testEnv.authenticatedContext('athleteX');
  await assertFails(
    athlete.firestore().collection('athlete_notes').doc('coachV_athleteX').set(
      { trainerId: 'athleteX', updatedAt: new Date() },
      { merge: true },
    ),
  );
});

test('SIZE: a note >= 5000 chars is rejected', async () => {
  const coach = testEnv.authenticatedContext('coach6');
  await assertFails(
    coach.firestore().collection('athlete_notes').doc('coach6_athleteX').set({
      trainerId: 'coach6',
      athleteId: 'athleteX',
      note: 'x'.repeat(5000),
      updatedAt: new Date(),
    }),
  );
});
