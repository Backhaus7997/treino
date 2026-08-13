'use strict';

/**
 * Firestore Security Rules test suite — exerciseFeedback (issue #628).
 *
 * `users/{uid}/sessions/{sessionId}/exerciseFeedback/{feedbackId}` holds the
 * athlete's comment or discomfort report, anchored to one exercise and
 * optionally one set. It is HEALTH DATA: a discomfort entry names a body part
 * that hurts. The read gate is the `session_shares/{uid}` grant — the same one
 * setLogs uses — and writes are owner-only.
 *
 * Why this file exists: the rules block already documented sixteen scenarios
 * (E1-E16) but nothing executed them. The issue calls that out twice, citing
 * #508 and #447 — "las reglas sin validación de tipo/rango se cuelan". A
 * documented scenario that no test runs is a comment, not a guarantee.
 *
 * Coverage:
 *   E1  owner reads own feedback                        → allowed
 *   E2  granted trainer reads athlete's feedback        → allowed
 *   E3  unrelated user reads                            → denied
 *   E4  trainer WITHOUT a session_shares grant reads    → denied
 *   E5  trainer whose grant names ANOTHER trainer reads → denied
 *   E6  unauthenticated read                            → denied
 *   E7  owner creates a valid entry                     → allowed
 *   E8  trainer writes into the athlete's subcollection → denied
 *   E9  empty report (no text, no photo)                → denied
 *   E10 unknown `kind`                                  → denied
 *   E11 negative slotIndex                              → denied
 *   E12 setNumber 0                                     → denied
 *   E13 photoUrl without photoPath                      → denied
 *   E14 owner updates an existing entry                 → denied (immutable)
 *   E15 owner deletes own entry                         → allowed
 *   E16 granted trainer deletes athlete's entry         → denied
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

const ATHLETE = 'athlete1';
const COACH = 'coach1';
const OTHER = 'stranger1';
const SESSION = 'session1';

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

/** A well-formed entry. Individual tests override single fields to break it. */
function validFeedback(overrides = {}) {
  return {
    exerciseId: 'bench-press',
    exerciseName: 'Press de banca',
    slotIndex: 0,
    setNumber: 3,
    kind: 'discomfort',
    text: 'Molestia en el hombro derecho',
    createdAt: new Date(),
    ...overrides,
  };
}

function feedbackRef(ctx, uid = ATHLETE, id = 'fb1') {
  return ctx
    .firestore()
    .collection('users')
    .doc(uid)
    .collection('sessions')
    .doc(SESSION)
    .collection('exerciseFeedback')
    .doc(id);
}

/** Grants `trainerId` read access to `uid`'s session data. */
async function seedGrant(uid, trainerId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('session_shares')
      .doc(uid)
      .set({ trainerId, updatedAt: new Date() });
  });
}

/** Writes an entry bypassing rules, so read/update/delete tests have a target. */
async function seedFeedback(uid = ATHLETE, id = 'fb1', data = validFeedback()) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('users')
      .doc(uid)
      .collection('sessions')
      .doc(SESSION)
      .collection('exerciseFeedback')
      .doc(id)
      .set(data);
  });
}

// ── Read gate (E1-E6) ───────────────────────────────────────────────────────

test('E1: the owner reads their own feedback', async () => {
  await seedFeedback();
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertSucceeds(feedbackRef(athlete).get());
});

test('E2: a trainer WITH a session_shares grant reads it', async () => {
  await seedFeedback();
  await seedGrant(ATHLETE, COACH);
  const coach = testEnv.authenticatedContext(COACH);
  await assertSucceeds(feedbackRef(coach).get());
});

test('E3: an unrelated signed-in user cannot read it', async () => {
  await seedFeedback();
  await seedGrant(ATHLETE, COACH);
  const stranger = testEnv.authenticatedContext(OTHER);
  await assertFails(feedbackRef(stranger).get());
});

test('E4: a trainer without any grant cannot read it', async () => {
  await seedFeedback();
  // No session_shares doc at all — the athlete never opted in.
  const coach = testEnv.authenticatedContext(COACH);
  await assertFails(feedbackRef(coach).get());
});

test('E5: a grant naming another trainer does not let this one read', async () => {
  await seedFeedback();
  await seedGrant(ATHLETE, 'someOtherCoach');
  const coach = testEnv.authenticatedContext(COACH);
  await assertFails(feedbackRef(coach).get());
});

test('E6: an unauthenticated request cannot read it', async () => {
  await seedFeedback();
  const anon = testEnv.unauthenticatedContext();
  await assertFails(feedbackRef(anon).get());
});

// ── Write gate (E7-E8) ──────────────────────────────────────────────────────

test('E7: the owner creates a valid entry', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertSucceeds(feedbackRef(athlete).set(validFeedback()));
});

test('E8: a granted trainer cannot write into the athlete subcollection', async () => {
  await seedGrant(ATHLETE, COACH);
  const coach = testEnv.authenticatedContext(COACH);
  // Reading is allowed; authoring on the athlete's behalf never is.
  await assertFails(feedbackRef(coach).set(validFeedback()));
});

// ── Field validation (E9-E13) ───────────────────────────────────────────────

test('E9: an empty report — no text, no photo — is rejected', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(
    feedbackRef(athlete).set(validFeedback({ text: null })),
  );
});

test('E9b: whitespace-free empty string counts as no text', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(feedbackRef(athlete).set(validFeedback({ text: '' })));
});

test('E10: an unknown kind is rejected', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(
    feedbackRef(athlete).set(validFeedback({ kind: 'injury' })),
  );
});

test('E11: a negative slotIndex is rejected', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(feedbackRef(athlete).set(validFeedback({ slotIndex: -1 })));
});

test('E12: setNumber 0 is rejected (sets are 1-based)', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(feedbackRef(athlete).set(validFeedback({ setNumber: 0 })));
});

test('E12b: a null setNumber is accepted (exercise-level comment)', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertSucceeds(
    feedbackRef(athlete).set(validFeedback({ setNumber: null })),
  );
});

test('E13: photoUrl without photoPath is rejected', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  // photoPath is what the deletion cascade needs; a URL without it orphans the
  // Storage object — and this one holds health data.
  await assertFails(
    feedbackRef(athlete).set(
      validFeedback({ text: null, photoUrl: 'https://x/y.jpg' }),
    ),
  );
});

test('E13b: photoPath without photoUrl is rejected', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertFails(
    feedbackRef(athlete).set(
      validFeedback({ text: null, photoPath: 'sessionFeedback/a/b/c.jpg' }),
    ),
  );
});

test('E13c: photo-only, both fields present, is accepted', async () => {
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertSucceeds(
    feedbackRef(athlete).set(
      validFeedback({
        text: null,
        photoUrl: 'https://x/y.jpg',
        photoPath: `sessionFeedback/${ATHLETE}/${SESSION}/y.jpg`,
      }),
    ),
  );
});

// ── Immutability and delete (E14-E16) ───────────────────────────────────────

test('E14: the owner cannot update an existing entry', async () => {
  await seedFeedback();
  const athlete = testEnv.authenticatedContext(ATHLETE);
  // Amend by delete + create: an update could leave photoUrl pointing at an
  // object photoPath no longer names.
  await assertFails(feedbackRef(athlete).update({ text: 'editado' }));
});

test('E15: the owner deletes their own entry', async () => {
  await seedFeedback();
  const athlete = testEnv.authenticatedContext(ATHLETE);
  await assertSucceeds(feedbackRef(athlete).delete());
});

test('E16: a granted trainer cannot delete the athlete entry', async () => {
  await seedFeedback();
  await seedGrant(ATHLETE, COACH);
  const coach = testEnv.authenticatedContext(COACH);
  await assertFails(feedbackRef(coach).delete());
});
