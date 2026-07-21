'use strict';

/**
 * Firestore Security Rules test suite — coach-collections role gate
 * (rules-hardening Slice C).
 *
 * Covers `coach-collections-security` spec's "Coach-Collection Create
 * Requires Trainer Role" scenarios for `payments`, `athlete_billing`,
 * `measurements`, `performance_tests`, `appointments`.
 *
 * IMPORTANT — implemented scope vs spec literal (see design.md AD-1 +
 * engram decision obs #413): this change is ROLE-CHECK ONLY
 * (`get(users/{uid}).data.role == 'trainer'`), NOT role+active-link. The
 * spec's "trainer with no link forges a record" scenario is a documented,
 * accepted residual (attributable — the forger's own uid is on the doc) and
 * is DELIBERATELY implemented here as an assertSucceeds anchor (a linked-or-
 * unlinked real trainer can still create), not a deny test. See tasks.md
 * pre-flight 0.1 and design.md AD-1 "Decision — split by collection".
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

async function seedUserRole(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({ uid, role });
  });
}

// ---------------------------------------------------------------------------
// SCENARIO-CC-01: An athlete-role user forges a payment debt against a
// victim. [AD-1][REQ:coach-collections-security#Coach-Collection Create
// Requires Trainer Role — forged payment]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-01: athlete-role user cannot forge a payment naming themselves trainer', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('payments').doc('forged1').set({
      trainerId: 'attacker',
      athleteId: 'victim',
      amountArs: 999999,
      concept: 'forged debt',
      status: 'pending',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-02: An athlete-role user forges a measurement against a
// victim. [AD-1][REQ:coach-collections-security#Coach-Collection Create
// Requires Trainer Role — forged measurement]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-02: athlete-role user cannot forge a measurement naming themselves recordedBy', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('measurements').doc('forged2').set({
      recordedBy: 'attacker',
      athleteId: 'victim',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-03: An athlete-role user forges a performance test against a
// victim. [AD-1][REQ:coach-collections-security#Coach-Collection Create
// Requires Trainer Role — forged performance test]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-03: athlete-role user cannot forge a performance_test naming themselves recordedBy', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('performance_tests').doc('forged3').set({
      recordedBy: 'attacker',
      athleteId: 'victim',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-04: An athlete-role user forges athlete_billing config against
// a victim. [AD-1][REQ:coach-collections-security#Coach-Collection Create
// Requires Trainer Role — forged billing config]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-04: athlete-role user cannot forge athlete_billing naming themselves trainer', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('athlete_billing').doc('attacker_victim').set({
      trainerId: 'attacker',
      athleteId: 'victim',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-05: An athlete-role user forges a confirmed appointment naming
// themselves as the TRAINER of a victim athlete. [AD-1][REQ:coach-
// collections-security#Coach-Collection Create Requires Trainer Role —
// forged appointment]. Note: this is distinct from the legacy athlete
// self-book path (SCENARIO-CC-08) — here the attacker names THEMSELVES as
// trainerId, not athleteId.
// ---------------------------------------------------------------------------
test('SCENARIO-CC-05: athlete-role user cannot forge an appointment naming themselves trainer', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('appointments').doc('forged5').set({
      status: 'confirmed',
      trainerId: 'attacker',
      athleteId: 'victim',
      startsAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-06: A real trainer creates a legitimate payment for an
// athlete. [AD-1#legit path] — legit-path anchor, must stay green through
// the GREEN step.
// ---------------------------------------------------------------------------
test('SCENARIO-CC-06: real trainer CAN create a payment for an athlete', async () => {
  await seedUserRole('coach', 'trainer');

  const coach = testEnv.authenticatedContext('coach');
  await assertSucceeds(
    coach.firestore().collection('payments').doc('legit1').set({
      // QA-PAY-007 (#447): create now enforces id == doc id — mirrors what
      // every real writer already stamps (PaymentRepository.add /
      // AppointmentRepository.billAppointment via copyWith(id: ref.id)).
      id: 'legit1',
      trainerId: 'coach',
      athleteId: 'athlete',
      amountArs: 15000,
      concept: 'Mensualidad',
      status: 'pending',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-06b: A real trainer creates a legitimate measurement.
// [AD-1#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-06b: real trainer CAN create a measurement for an athlete', async () => {
  await seedUserRole('coach2', 'trainer');

  const coach = testEnv.authenticatedContext('coach2');
  await assertSucceeds(
    coach.firestore().collection('measurements').doc('legit2').set({
      recordedBy: 'coach2',
      athleteId: 'athlete',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-06c: A real trainer creates a legitimate performance test.
// [AD-1#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-06c: real trainer CAN create a performance_test for an athlete', async () => {
  await seedUserRole('coach3', 'trainer');

  const coach = testEnv.authenticatedContext('coach3');
  await assertSucceeds(
    coach.firestore().collection('performance_tests').doc('legit3').set({
      recordedBy: 'coach3',
      athleteId: 'athlete',
      createdAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-06d: A real trainer creates legitimate athlete_billing config.
// [AD-1#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-06d: real trainer CAN create athlete_billing for an athlete', async () => {
  await seedUserRole('coach4', 'trainer');

  const coach = testEnv.authenticatedContext('coach4');
  await assertSucceeds(
    coach.firestore().collection('athlete_billing').doc('coach4_athlete').set({
      // QA-PAY-007 (#447): create now enforces the real AthleteBilling model
      // shape (strict hasOnly) — the old synthetic payload with `createdAt`
      // no longer represents what BillingRepository.setConfig writes.
      trainerId: 'coach4',
      athleteId: 'athlete',
      amountArs: 20000,
      cadence: 'mensual',
      updatedAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-06e: A real trainer updates existing athlete_billing config
// (the combined create+update rule block must keep allowing legit updates
// after the create-only role gate is added). [tasks pre-flight gotcha #2]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-06e: real trainer CAN update their existing athlete_billing config', async () => {
  await seedUserRole('coach5', 'trainer');
  // QA-PAY-007 (#447): the seed deliberately keeps a legacy zombie field
  // (`monthlyRate`) — the update rule is diff()-based precisely so a doc
  // predating the current model can still be updated without the zombie
  // blocking a strict keys().hasOnly() forever.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('athlete_billing').doc('coach5_athlete').set({
      trainerId: 'coach5',
      athleteId: 'athlete',
      amountArs: 10000,
      cadence: 'mensual',
      updatedAt: new Date(),
      monthlyRate: 10000, // zombie pre-model field, untouched by the update
    });
  });

  const coach = testEnv.authenticatedContext('coach5');
  await assertSucceeds(
    coach.firestore().collection('athlete_billing').doc('coach5_athlete').update({
      amountArs: 12000,
      updatedAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-07: A real trainer creates a legitimate confirmed appointment
// for an athlete (trainer-driven booking path). [AD-1#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-07: real trainer CAN create a confirmed appointment for an athlete', async () => {
  await seedUserRole('coach6', 'trainer');

  const coach = testEnv.authenticatedContext('coach6');
  await assertSucceeds(
    coach.firestore().collection('appointments').doc('legit7').set({
      status: 'confirmed',
      trainerId: 'coach6',
      athleteId: 'athlete',
      startsAt: new Date(),
    }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-CC-08: REGRESSION — an athlete self-books a legitimate
// appointment (legacy self-book path). The role gate MUST apply ONLY to the
// trainer-create disjunct, not this athlete-self-book disjunct, or legit
// athlete self-booking breaks. [tasks pre-flight gotcha #1][RISK: appointments
// legacy athlete self-book branch]
// ---------------------------------------------------------------------------
test('SCENARIO-CC-08: athlete (role athlete, no trainer role) CAN self-book their own appointment (legacy path preserved)', async () => {
  await seedUserRole('athlete1', 'athlete');

  const athlete = testEnv.authenticatedContext('athlete1');
  await assertSucceeds(
    athlete.firestore().collection('appointments').doc('legit8').set({
      status: 'confirmed',
      athleteId: 'athlete1',
      trainerId: 'coach7',
      startsAt: new Date(),
    }),
  );
});
