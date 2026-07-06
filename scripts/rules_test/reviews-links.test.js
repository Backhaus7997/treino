'use strict';

/**
 * Firestore Security Rules test suite — reviews + trainerPublicProfiles
 * rating fields (rules-hardening Slice B).
 *
 * Covers:
 *  - trainer-reviews spec: "Review Create Requires Real Trainer Link"
 *    (SCENARIO-RV-LINK-01..03)
 *  - trainer-reviews spec: "trainerPublicProfiles Rating Fields Are
 *    CF-Write-Only" (SCENARIO-TPP-RATING-01..04)
 *
 * design.md AD-1 (reviews link-gating) + AD-3 (CF-write-only metric pins,
 * mirroring the userPublicProfiles ranking-metric idiom at
 * firestore.rules:434-468 — NO hasOnly allowlist added here, deliberately,
 * per AD-3's dual-write/partial-merge reasoning).
 *
 * Run via: JAVA_HOME=/opt/homebrew/opt/openjdk@21 bash scripts/test_rules.sh
 * (Requires the Firebase emulator; Firestore only, no Storage needed here.)
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

async function seedActiveLink(linkId, { trainerId, athleteId, status = 'active' }) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('trainer_links').doc(linkId).set({
      trainerId,
      athleteId,
      status,
      requestedAt: new Date(),
    });
  });
}

// ---------------------------------------------------------------------------
// SCENARIO-RV-LINK-01: An unlinked athlete forges a review for a trainer
// they never trained with. [AD-1][REQ:trainer-reviews#Review Create
// Requires Real Trainer Link — forged review]
// ---------------------------------------------------------------------------
test('SCENARIO-RV-LINK-01: unlinked athlete cannot forge a review naming an arbitrary trainer', async () => {
  // No trainer_links doc naming trainerId == victimTrainer exists at all.
  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('reviews').doc('forged1').set({
      id: 'forged1',
      linkId: 'nonexistent-link',
      athleteId: 'attacker',
      trainerId: 'victimTrainer',
      rating: 1,
      comment: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-RV-LINK-02: A linked athlete tries to pin a mismatched doc-id.
// [AD-1][REQ:trainer-reviews#Review Create Requires Real Trainer Link —
// mismatched doc-id]
// ---------------------------------------------------------------------------
test('SCENARIO-RV-LINK-02: linked athlete cannot create a review under a doc-id that does not match ${linkId}_${athleteId}', async () => {
  await seedActiveLink('link1', { trainerId: 'coach', athleteId: 'athlete' });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertFails(
    athlete.firestore().collection('reviews').doc('random-doc-id').set({
      id: 'random-doc-id',
      linkId: 'link1',
      athleteId: 'athlete',
      trainerId: 'coach',
      rating: 5,
      comment: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-RV-LINK-03: A linked athlete leaves a legitimate review.
// [AD-1][REQ:trainer-reviews#Review Create Requires Real Trainer Link —
// legit path] — non-vacuity anchor, must stay green through the GREEN step.
// ---------------------------------------------------------------------------
test('SCENARIO-RV-LINK-03: linked athlete CAN create a review at the correct ${linkId}_${athleteId} doc-id', async () => {
  await seedActiveLink('link1', { trainerId: 'coach', athleteId: 'athlete' });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertSucceeds(
    athlete.firestore().collection('reviews').doc('link1_athlete').set({
      id: 'link1_athlete',
      linkId: 'link1',
      athleteId: 'athlete',
      trainerId: 'coach',
      rating: 4,
      comment: 'Great trainer!',
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// A 'paused' link must also be treated as a real relationship — trainer_links
// design.md AD-1: link check accepts status in ['active', 'paused'].
test('SCENARIO-RV-LINK-03b: linked athlete on a PAUSED link can still create a legit review', async () => {
  await seedActiveLink('link2', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'paused',
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertSucceeds(
    athlete.firestore().collection('reviews').doc('link2_athlete').set({
      id: 'link2_athlete',
      linkId: 'link2',
      athleteId: 'athlete',
      trainerId: 'coach',
      rating: 3,
      comment: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// A 'terminated' link must NOT count as a real relationship.
test('SCENARIO-RV-LINK-03c: a TERMINATED link does not authorize a review create', async () => {
  await seedActiveLink('link3', {
    trainerId: 'coach',
    athleteId: 'athlete',
    status: 'terminated',
  });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertFails(
    athlete.firestore().collection('reviews').doc('link3_athlete').set({
      id: 'link3_athlete',
      linkId: 'link3',
      athleteId: 'athlete',
      trainerId: 'coach',
      rating: 5,
      comment: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// A review naming a trainerId that does not match the link's real trainerId
// must be denied even if the doc-id/linkId/athleteId all line up.
test('SCENARIO-RV-LINK-03d: review trainerId must match the linked trainer, not an arbitrary victim', async () => {
  await seedActiveLink('link4', { trainerId: 'coach', athleteId: 'athlete' });

  const athlete = testEnv.authenticatedContext('athlete');
  await assertFails(
    athlete.firestore().collection('reviews').doc('link4_athlete').set({
      id: 'link4_athlete',
      linkId: 'link4',
      athleteId: 'athlete',
      trainerId: 'someOtherTrainer', // does not match link4.trainerId == 'coach'
      rating: 1,
      comment: null,
      createdAt: new Date(),
      updatedAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TPP-RATING-01: A trainer forges their own rating via raw
// set(merge)/update. [AD-3][REQ:trainer-reviews#trainerPublicProfiles
// Rating Fields Are CF-Write-Only — forged rating]
// ---------------------------------------------------------------------------
async function seedTrainerProfile(uid, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('trainerPublicProfiles').doc(uid).set({
      uid,
      averageRating: 3.5,
      reviewCount: 10,
      trainerBio: 'Original bio',
      ...extra,
    });
  });
}

test('SCENARIO-TPP-RATING-01: trainer cannot forge averageRating/reviewCount via update', async () => {
  await seedTrainerProfile('trainer1');

  const trainer = testEnv.authenticatedContext('trainer1');
  await assertFails(
    trainer.firestore().collection('trainerPublicProfiles').doc('trainer1').update({
      averageRating: 5.0,
      reviewCount: 999,
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TPP-RATING-02: A trainer updates a client-owned profile field
// without touching aggregates. [AD-3#legit field-only update] — legit-path
// anchor, must stay green through the GREEN step.
// ---------------------------------------------------------------------------
test('SCENARIO-TPP-RATING-02: trainer CAN update trainerBio while leaving averageRating/reviewCount untouched', async () => {
  await seedTrainerProfile('trainer2');

  const trainer = testEnv.authenticatedContext('trainer2');
  await assertSucceeds(
    trainer.firestore().collection('trainerPublicProfiles').doc('trainer2').update({
      trainerBio: 'Updated bio',
    }),
  );
});

// Re-asserting the SAME averageRating/reviewCount value explicitly (not just
// omitting the fields) must also succeed — the pin allows re-assertion of
// the current value, not just absence.
test('SCENARIO-TPP-RATING-02b: trainer CAN re-write the same averageRating/reviewCount values unchanged', async () => {
  await seedTrainerProfile('trainer2b');

  const trainer = testEnv.authenticatedContext('trainer2b');
  await assertSucceeds(
    trainer.firestore().collection('trainerPublicProfiles').doc('trainer2b').update({
      trainerBio: 'Another bio update',
      averageRating: 3.5,
      reviewCount: 10,
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TPP-RATING-03: A trainer seeds forged rating fields at CREATE
// time (first write, no prior resource.data to compare against).
// [AD-3#create-side guard]
// ---------------------------------------------------------------------------
test('SCENARIO-TPP-RATING-03: trainer cannot seed averageRating/reviewCount at create time', async () => {
  const trainer = testEnv.authenticatedContext('trainer3');
  await assertFails(
    trainer.firestore().collection('trainerPublicProfiles').doc('trainer3').set({
      uid: 'trainer3',
      averageRating: 5.0,
      reviewCount: 1,
    }),
  );
});

// Legit create (no rating fields at all) must still succeed — non-vacuity
// anchor for the create path.
test('SCENARIO-TPP-RATING-03b: trainer CAN create their own profile without seeding rating fields', async () => {
  const trainer = testEnv.authenticatedContext('trainer3b');
  await assertSucceeds(
    trainer.firestore().collection('trainerPublicProfiles').doc('trainer3b').set({
      uid: 'trainer3b',
      trainerBio: 'New trainer',
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TPP-RATING-04: The reviewAggregate Cloud Function (Admin SDK)
// republishes aggregates. Admin SDK writes bypass rules entirely — this is
// simulated here via withSecurityRulesDisabled, matching the spec's explicit
// note that no rules-layer test is required for this path; kept as a single
// documentation-anchor test so the bypass is provably exercised in this
// suite, not merely asserted in a comment. [AD-3#CF bypass]
// ---------------------------------------------------------------------------
test('SCENARIO-TPP-RATING-04: reviewAggregate CF (Admin SDK) write bypasses rules entirely', async () => {
  await seedTrainerProfile('trainer4');

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('trainerPublicProfiles').doc('trainer4').update({
      averageRating: 4.8,
      reviewCount: 11,
    });
  });

  // NOTE: withSecurityRulesDisabled awaits its callback but does NOT return
  // the callback's return value (confirmed against
  // @firebase/rules-unit-testing's implementation — the awaited result is
  // discarded, not propagated). Capture the snapshot via a closure variable
  // instead of relying on the outer await's resolved value.
  let snap;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    snap = await ctx.firestore().collection('trainerPublicProfiles').doc('trainer4').get();
  });
  expect(snap.data().averageRating).toBe(4.8);
  expect(snap.data().reviewCount).toBe(11);
});

// NOTE per AD-3: design.md deliberately chose NO keys().hasOnly() allowlist
// for trainerPublicProfiles (dual-write partial-merge coupling-trap
// reasoning — the trainer-reviews spec's "Out-of-allowlist field" scenario
// is explicitly NOT implemented in this change; documented divergence, see
// tasks.md 2.7 and design.md AD-3).
