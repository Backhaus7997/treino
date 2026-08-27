/**
 * Rules tests for `payments/{paymentId}` UPDATE — the field-level pins added
 * by REQ-VENC-13 / QA-PAY-007.
 *
 * WHY THIS FILE EXISTS
 * The rules-coverage matrix (docs/security.md, #680 Slice A) found `payments`
 * with 14 negative tests on CREATE (scripts/rules_test/payments-field-
 * validation.test.js) and **zero** on UPDATE. The only artefact naming the
 * update path is `test/firestore/payments_rules_test.dart`, and both of its
 * cases are empty bodies marked `skip: 'emulator required'` — a stub that has
 * been reporting "skipped", never "failed", since it was written. So the
 * strictest rule in the file, the one that decides whether a debt can be
 * rewritten after the fact, was running unverified.
 *
 * What the update rule pins, and therefore what this file checks:
 *   - money and identity are immutable after create — amountArs, concept,
 *     trainerId, athleteId, id, createdAt, periodKey;
 *   - `dueAt` is pinned equal-to-existing, so a client can neither set nor
 *     move a due date (REQ-VENC-13 — the CF writes it via Admin SDK);
 *   - `lastOverdueNotifiedAt` is CF-only for the same reason;
 *   - only the OWNER trainer may update at all — the athlete named in the
 *     debt cannot mark their own debt paid.
 * The legit path (`markPaid` sending exactly `{status, paidAt}`) is asserted
 * alongside, so a rule that denied every update could not turn this green.
 *
 * Uses `@firebase/rules-unit-testing` with `firestore.rules` actually loaded
 * and enforced (client-authenticated contexts), NOT the Admin SDK.
 *
 * Run against the Firestore emulator (Java 21 required):
 *   npm --prefix functions run test:rules:emulator
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setLogLevel } from "firebase/firestore";

// Distinct projectId: the rules suites share one emulator and clearFirestore()
// in afterEach; a distinct projectId keeps this suite's data out of the others'
// namespace so parallel Jest workers don't wipe each other.
const PROJECT_ID = "treino-rules-test-payupd";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_PAYMENTS = "payments";

const TRAINER = "trainer-payupd";
const OTHER_TRAINER = "other-trainer-payupd";
const ATHLETE = "athlete-payupd";
const PAYMENT_ID = "payment-payupd-1";

const CREATED_AT = new Date("2026-08-01T12:00:00Z");
const DUE_AT = new Date("2026-08-10T12:00:00Z");

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
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

function ctxDb(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

/**
 * The full Payment wire shape (PaymentRepository.add). The update rule is
 * keys().hasOnly() + per-field equality against the pre-image, so the fixture
 * has to be the WHOLE document — a partial one would fail for the wrong
 * reason and the test would prove nothing.
 */
function paymentDoc(
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: PAYMENT_ID,
    trainerId: TRAINER,
    athleteId: ATHLETE,
    amountArs: 45000,
    concept: "Mensualidad agosto",
    status: "pending",
    periodKey: "2026-08",
    createdAt: CREATED_AT,
    paidAt: null,
    dueAt: null,
    lastOverdueNotifiedAt: null,
    ...overrides,
  };
}

async function seedPayment(
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_PAYMENTS)
      .doc(PAYMENT_ID)
      .set(paymentDoc(overrides));
  });
}

describe("payments update — who may write at all", () => {
  beforeEach(async () => {
    await seedPayment();
  });

  it("allows the owner trainer to mark it paid (markPaid's exact payload)", async () => {
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ status: "paid", paidAt: new Date() }),
    );
  });

  it("DENIES the athlete marking their own debt paid", async () => {
    // The athlete can READ the payment (it is about them) but the record is
    // the trainer's books.
    await assertFails(
      ctxDb(ATHLETE)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ status: "paid", paidAt: new Date() }),
    );
  });

  it("DENIES another trainer touching someone else's books", async () => {
    await assertFails(
      ctxDb(OTHER_TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ status: "paid", paidAt: new Date() }),
    );
  });

  it("DENIES an unauthenticated update", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ status: "paid" }),
    );
  });
});

describe("payments update — money and identity are immutable after create", () => {
  beforeEach(async () => {
    await seedPayment();
  });

  it("DENIES rewriting amountArs (poisoning the totals both sides see)", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ amountArs: 1 }),
    );
  });

  it("DENIES rewriting the concept after the fact", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ concept: "Otra cosa" }),
    );
  });

  it("DENIES reassigning the debt to a different athlete", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ athleteId: "otro-alumno" }),
    );
  });

  it("DENIES handing the debt to another trainer", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ trainerId: OTHER_TRAINER }),
    );
  });

  it("DENIES backdating createdAt", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ createdAt: new Date("2020-01-01T00:00:00Z") }),
    );
  });

  it("DENIES moving the record to another billing period", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ periodKey: "2026-07" }),
    );
  });

  it("DENIES desyncing the body id from the doc id", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ id: "otro-id" }),
    );
  });

  it("DENIES smuggling in a field outside the model", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ discountPct: 100 }),
    );
  });
});

describe("payments update — dueAt is CF-only (SCENARIO-VENC-14)", () => {
  it("DENIES a client SETTING dueAt on a record that has none", async () => {
    await seedPayment();
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ dueAt: DUE_AT }),
    );
  });

  it("DENIES a client MOVING an existing dueAt", async () => {
    await seedPayment({ dueAt: DUE_AT });
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ dueAt: new Date("2026-12-31T12:00:00Z") }),
    );
  });

  it("DENIES a client CLEARING an existing dueAt", async () => {
    await seedPayment({ dueAt: DUE_AT });
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ dueAt: null }),
    );
  });

  it("still allows markPaid on a record that carries a dueAt (SCENARIO-VENC-15)", async () => {
    await seedPayment({ dueAt: DUE_AT });
    await assertSucceeds(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ status: "paid", paidAt: new Date() }),
    );
  });

  it("DENIES a client writing lastOverdueNotifiedAt (CF bookkeeping)", async () => {
    // Forging this silences the overdue notification for that record.
    await seedPayment({ dueAt: DUE_AT });
    await assertFails(
      ctxDb(TRAINER)
        .collection(COL_PAYMENTS)
        .doc(PAYMENT_ID)
        .update({ lastOverdueNotifiedAt: new Date() }),
    );
  });
});

/**
 * #848 — el `delete` de `payments` chocaba con el set-once de
 * `appointments.paymentId`.
 *
 * Los dos bloques por separado están bien; lo que nunca se cruzó es que el
 * set-once asume que el Payment NO desaparece. Medido contra el emulador, con
 * el PF dueño de los DOS documentos:
 *   · borrar el Payment                  → ALLOW
 *   · limpiar el `paymentId` del turno    → DENY (set-once, Path 2)
 *   · reapuntarlo a otro Payment          → DENY (set-once, Path 2)
 * El turno quedaba apuntando PERMANENTEMENTE a un documento inexistente, en el
 * campo money-critical, y `appointments` tiene `allow delete: if false`.
 *
 * El `delete` se cerró en vez de acotarse: aflojar el set-once no se puede
 * ESCRIBIR (haría falta un `exists()` y `exists()` lee estado pre-commit,
 * mientras `billAppointment` crea el Payment y setea el `paymentId` en la MISMA
 * transacción). Y es gratis: `PaymentRepository` no tiene delete, ningún
 * `.delete()` de `lib/` cae sobre `collection('payments')`, y el cascade de
 * borrado de cuenta RETIENE los payments a propósito por motivos fiscales.
 *
 * ⚠️ El primer caso ERA `allows the owner trainer to delete their own record`.
 * Se CONVIRTIÓ a DENY en vez de borrarse — el mismo criterio que #831 usó con
 * el flip: un camino que se remueve necesita un test que se ponga rojo si
 * alguien lo reintroduce sin pensarlo.
 */
describe("payments delete — cerrado (#848)", () => {
  beforeEach(async () => {
    await seedPayment();
  });

  it("DENIES the owner trainer deleting their own record — el `paymentId` colgado", async () => {
    await assertFails(
      ctxDb(TRAINER).collection(COL_PAYMENTS).doc(PAYMENT_ID).delete(),
    );
  });

  it("DENIES the athlete deleting a debt recorded against them", async () => {
    await assertFails(
      ctxDb(ATHLETE).collection(COL_PAYMENTS).doc(PAYMENT_ID).delete(),
    );
  });

  it("DENIES another trainer deleting it", async () => {
    await assertFails(
      ctxDb(OTHER_TRAINER).collection(COL_PAYMENTS).doc(PAYMENT_ID).delete(),
    );
  });
});

/**
 * #848 — la referencia rota, de punta a punta.
 *
 * Los tres casos de arriba miden el `delete` solo. Éste mide el CHOQUE, que es
 * lo que el issue reporta: el turno apunta al Payment, el Payment se va, y el
 * `paymentId` queda colgado para siempre porque el set-once del Path 2 no deja
 * ni limpiarlo ni reapuntarlo, y `appointments` tiene `allow delete: if false`.
 *
 * Con el `delete` cerrado, el primer paso de la cadena ya no ocurre. Los otros
 * dos siguen dando DENY —el gate money-critical NO se tocó, que es justamente
 * el punto de haber cerrado el `delete` en vez de aflojar el set-once— y por
 * eso están acá: si alguien "arregla" #848 aflojando el set-once, estos dos se
 * ponen verdes por el motivo equivocado y este bloque deja de custodiar nada.
 */
describe("payments delete — el paymentId del turno no queda colgado (#848)", () => {
  const APPT_ID = "appt-848";

  beforeEach(async () => {
    await seedPayment();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("appointments").doc(APPT_ID).set({
        id: APPT_ID,
        trainerId: TRAINER,
        athleteId: ATHLETE,
        athleteDisplayName: "Ana",
        startsAt: new Date(Date.now() + 5 * 86400000),
        durationMin: 60,
        status: "confirmed",
        cancelledAt: null,
        cancelledBy: null,
        cancellationLog: [],
        noteBefore: null,
        noteAfter: null,
        recurringId: null,
        paymentId: PAYMENT_ID,
      });
    });
  });

  it("el PF dueño de los DOS documentos ya no puede borrar el Payment apuntado", async () => {
    await assertFails(
      ctxDb(TRAINER).collection(COL_PAYMENTS).doc(PAYMENT_ID).delete(),
    );
  });

  it("y el set-once sigue intacto: no puede limpiar el paymentId del turno", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection("appointments")
        .doc(APPT_ID)
        .update({ paymentId: null }),
    );
  });

  it("ni reapuntarlo a otro Payment", async () => {
    await assertFails(
      ctxDb(TRAINER)
        .collection("appointments")
        .doc(APPT_ID)
        .update({ paymentId: "otro-pago" }),
    );
  });

  it("el Payment sigue existiendo después del intento — la referencia no se rompe", async () => {
    await assertFails(
      ctxDb(TRAINER).collection(COL_PAYMENTS).doc(PAYMENT_ID).delete(),
    );
    const snap = await ctxDb(TRAINER)
      .collection(COL_PAYMENTS)
      .doc(PAYMENT_ID)
      .get();
    expect(snap.exists).toBe(true);
  });
});
