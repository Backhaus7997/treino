'use strict';

/**
 * Firestore Security Rules test suite — payments / athlete_billing money
 * field validation (QA-PAY-007, issue #447).
 *
 * Before this hardening, a legit-role trainer with a modified client could
 * create payments with negative/zero/decimal/string amountArs, unbounded
 * concept, arbitrary status/periodKey — poisoning the totals both the
 * athlete and the trainer see. athlete_billing accepted any shape at all.
 *
 * Happy paths mirror the REAL writers exactly:
 *   - PaymentRepository.add            → pending payment, id == doc id
 *   - paidPaymentFor (marcar pagado)   → status 'paid' + paidAt + periodKey
 *                                        ('YYYY-MM' mensual | 'YYYY-Www' ISO)
 *   - cita/vencimiento flows           → dueAt set at create (timestamp)
 *   - BillingRepository.setConfig      → exact AthleteBilling model shape
 *
 * Run via: JAVA_HOME=/opt/homebrew/opt/openjdk@21 bash scripts/test_rules.sh
 * (Requires the Firebase emulator; Firestore only.)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules-pay';
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

async function seedTrainer(uid) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({ uid, role: 'trainer' });
  });
}

/** Valid pending-payment payload as PaymentRepository.add writes it. */
function validPayment(docId, trainerId, overrides = {}) {
  return {
    id: docId,
    trainerId,
    athleteId: 'athlete-1',
    amountArs: 25000,
    concept: 'Mensualidad julio',
    status: 'pending',
    createdAt: new Date(),
    ...overrides,
  };
}

/** Valid billing config as BillingRepository.setConfig writes it. */
function validBilling(trainerId, overrides = {}) {
  return {
    trainerId,
    athleteId: 'athlete-1',
    amountArs: 30000,
    cadence: 'mensual',
    updatedAt: new Date(),
    ...overrides,
  };
}

// ───────────────────────────────────────────────────────────────────────────
// payments — happy paths (every real writer keeps working)
// ───────────────────────────────────────────────────────────────────────────

test('PAY-VAL-01: pending payment with the exact repo payload succeeds', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertSucceeds(
    coach.firestore().collection('payments').doc('p1').set(validPayment('p1', 't1')),
  );
});

test('PAY-VAL-02: already-paid payment (paidPaymentFor) with monthly periodKey succeeds', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertSucceeds(
    coach.firestore().collection('payments').doc('p2').set(
      validPayment('p2', 't1', {
        status: 'paid',
        paidAt: new Date(),
        periodKey: '2026-07',
      }),
    ),
  );
});

test('PAY-VAL-03: ISO-week periodKey (semanal) succeeds', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertSucceeds(
    coach.firestore().collection('payments').doc('p3').set(
      validPayment('p3', 't1', { periodKey: '2026-W29' }),
    ),
  );
});

test('PAY-VAL-04: cita flow sets dueAt at create — still allowed', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertSucceeds(
    coach.firestore().collection('payments').doc('p4').set(
      validPayment('p4', 't1', { dueAt: new Date() }),
    ),
  );
});

// ───────────────────────────────────────────────────────────────────────────
// payments — money field attacks (all must be rejected)
// ───────────────────────────────────────────────────────────────────────────

test('PAY-VAL-05: negative amountArs is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p5').set(
      validPayment('p5', 't1', { amountArs: -50000 }),
    ),
  );
});

test('PAY-VAL-06: zero amountArs is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p6').set(
      validPayment('p6', 't1', { amountArs: 0 }),
    ),
  );
});

test('PAY-VAL-07: decimal amountArs is rejected (int only)', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p7').set(
      validPayment('p7', 't1', { amountArs: 50000.5 }),
    ),
  );
});

test('PAY-VAL-08: string amountArs is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p8').set(
      validPayment('p8', 't1', { amountArs: '50000' }),
    ),
  );
});

test('PAY-VAL-09: missing amountArs is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  const payload = validPayment('p9', 't1');
  delete payload.amountArs;
  await assertFails(
    coach.firestore().collection('payments').doc('p9').set(payload),
  );
});

test('PAY-VAL-10: amountArs above the 100M ARS cap is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p10').set(
      validPayment('p10', 't1', { amountArs: 100000001 }),
    ),
  );
});

test('PAY-VAL-11: empty concept is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p11').set(
      validPayment('p11', 't1', { concept: '' }),
    ),
  );
});

test('PAY-VAL-12: concept longer than 200 chars is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p12').set(
      validPayment('p12', 't1', { concept: 'x'.repeat(201) }),
    ),
  );
});

test('PAY-VAL-13: status outside the whitelist is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p13').set(
      validPayment('p13', 't1', { status: 'refunded' }),
    ),
  );
});

test('PAY-VAL-14: malformed periodKey is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p14').set(
      validPayment('p14', 't1', { periodKey: 'julio-2026' }),
    ),
  );
});

test('PAY-VAL-15: client writing lastOverdueNotifiedAt is rejected (CF-only)', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p15').set(
      validPayment('p15', 't1', { lastOverdueNotifiedAt: new Date() }),
    ),
  );
});

test('PAY-VAL-16: extra field outside the model is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p16').set(
      validPayment('p16', 't1', { discountPct: 50 }),
    ),
  );
});

test('PAY-VAL-17: id not matching the doc id is rejected', async () => {
  await seedTrainer('t1');
  const coach = testEnv.authenticatedContext('t1');
  await assertFails(
    coach.firestore().collection('payments').doc('p17').set(
      validPayment('SOMETHING-ELSE', 't1'),
    ),
  );
});

// ───────────────────────────────────────────────────────────────────────────
// athlete_billing — happy paths and attacks
// ───────────────────────────────────────────────────────────────────────────

test('BIL-VAL-01: setConfig-shaped create succeeds', async () => {
  await seedTrainer('t2');
  const coach = testEnv.authenticatedContext('t2');
  await assertSucceeds(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').set(validBilling('t2')),
  );
});

test('BIL-VAL-02: negative amountArs is rejected', async () => {
  await seedTrainer('t2');
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').set(
      validBilling('t2', { amountArs: -1000 }),
    ),
  );
});

test('BIL-VAL-03: cadence outside the whitelist is rejected', async () => {
  await seedTrainer('t2');
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').set(
      validBilling('t2', { cadence: 'anual' }),
    ),
  );
});

test('BIL-VAL-04: doc id not matching ${trainerId}_${athleteId} is rejected', async () => {
  await seedTrainer('t2');
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('random-id').set(validBilling('t2')),
  );
});

test('BIL-VAL-05: extra field on create is rejected', async () => {
  await seedTrainer('t2');
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').set(
      validBilling('t2', { discountPct: 10 }),
    ),
  );
});

test('BIL-VAL-06: update that injects a non-model field is rejected', async () => {
  await seedTrainer('t2');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('athlete_billing').doc('t2_athlete-1').set(validBilling('t2'));
  });
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').update({
      amountArs: 35000,
      updatedAt: new Date(),
      surchargePct: 15,
    }),
  );
});

test('BIL-VAL-07: update cannot flip amountArs to an invalid value', async () => {
  await seedTrainer('t2');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('athlete_billing').doc('t2_athlete-1').set(validBilling('t2'));
  });
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').update({
      amountArs: -35000,
      updatedAt: new Date(),
    }),
  );
});

test('BIL-VAL-08: update cannot reassign athleteId (identity immutable)', async () => {
  await seedTrainer('t2');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('athlete_billing').doc('t2_athlete-1').set(validBilling('t2'));
  });
  const coach = testEnv.authenticatedContext('t2');
  await assertFails(
    coach.firestore().collection('athlete_billing').doc('t2_athlete-1').update({
      athleteId: 'someone-else',
      updatedAt: new Date(),
    }),
  );
});
