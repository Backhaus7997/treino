/**
 * Unit tests for syncTrainerLoad / promotionDenialReason (paywall Fase 7,
 * PR4). LOCAL — no emulator. Uses the hand-rolled FakeTx firestore double
 * (design D-6) so the reads-before-writes invariant is verified without
 * Java 21 / the Firestore emulator.
 */

// `dobleNamespaced().firestore` is both a factory AND the namespace holding the
// `Timestamp`/`FieldValue` sentinels the gate writes. The double has to carry
// both, or the write path silently can't be exercised.
jest.mock("firebase-admin", () => {
  const firestore = jest.fn() as jest.Mock & Record<string, unknown>;
  // Stable sentinel: `FieldValue.delete()` must be reference-equal across
  // calls so tests can assert the delete marker itself, like the real SDK.
  const deleteSentinel = { __fakeFieldValue: "delete" };
  firestore.Timestamp = {
    fromMillis: (ms: number) => ({ __fakeTimestampMs: ms }),
  };
  firestore.FieldValue = { delete: () => deleteSentinel };
  return { firestore };
});

// La puerta modular tiene que dar EL MISMO doble que la namespaced de arriba.
//
// `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Producción
// importa FieldValue/Timestamp de `firebase-admin/firestore`, y sin esto le
// llega el REAL: el Firestore de mentira de este archivo no reconoce sus
// sentinels, guarda basura en vez de aplicarlos, y el test falla —o peor, pasa—
// por un motivo que no tiene que ver con lo que quiere probar.
//
// Getters y no valores: los factories se evalúan por demanda, así que esto no
// depende del orden entre los dos `jest.mock`.
//
// Lo fija `firebase-admin-mock-surface.test.ts`.
jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

import { App } from "firebase-admin/app";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { dobleNamespaced } from "./helpers/modular-from-namespaced";
import {
  createFakeFirestore,
  FakeDoc,
  FakeFirestoreState,
} from "./helpers/fake-tx-firestore";
import {
  promotionDenialReason,
  syncTrainerLoad,
} from "../subscriptions/promote-link";

function install(seed: Partial<FakeFirestoreState>): FakeFirestoreState {
  const { db, state } = createFakeFirestore(seed);
  (dobleNamespaced().firestore as unknown as jest.Mock).mockReturnValue(db);
  return state;
}

const app = {} as App;

const link = (overrides: Record<string, unknown> = {}) => ({
  trainerId: "trainer-1",
  athleteId: "athlete-1",
  status: "pending",
  entitlement: "entitled",
  ...overrides,
});

const plan1Active = { tier: "plan1", status: "active" };

describe("syncTrainerLoad — precondition ladder", () => {
  beforeEach(() => jest.clearAllMocks());

  it("not-found — link doesn't exist", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "missing", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("permission-denied — caller isn't the link's trainer", async () => {
    install({
      trainer_links: { L1: link({ trainerId: "trainer-1" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "someone-else", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("failed-precondition/wrong-status — status doesn't match expectedFromStatus", async () => {
    install({
      trainer_links: { L1: link({ status: "terminated" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition", message: "wrong-status" });
  });

  it("failed-precondition/link-blocked — target link is entitlement:blocked", async () => {
    install({
      trainer_links: { L1: link({ status: "pending", entitlement: "blocked" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition", message: "link-blocked" });
  });

  it("already-active — success no-op, promoted:false, link untouched", async () => {
    const state = install({
      trainer_links: { L1: link({ status: "active" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });
    expect(result.promoted).toBe(false);
    expect(state.trainer_links.L1.status).toBe("active");
  });

  it("not-found — trainer profile doc missing", async () => {
    install({
      trainer_links: { L1: link() },
      users: {},
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("invalid-argument — promotion missing linkId/callerUid", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  // Defensa en profundidad del gate de rol que `firestore.rules` le puso al
  // `create` de `trainer_links`. Esta callable va por Admin SDK y SE SALTEA las
  // reglas, así que es la otra mitad del camino: un vínculo trucho que ya
  // estuviera en la base —creado antes del fix— se promovía igual.
  //
  // El ataque que cierra: dos cuentas de ATLETA se nombran entrenador una a la
  // otra y se aceptan. Con el vínculo activo, `hasActiveTrainerLink` apaga
  // `athletePaywallEnforced` y las dos quedan exentas del tope.
  it("permission-denied — el 'trainer' del vínculo tiene rol de atleta", async () => {
    install({
      trainer_links: { L1: link() },
      users: { "trainer-1": { role: "athlete", subscription: plan1Active } },
    });
    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  // El ANCLA de la asimetría, y por qué el chequeo de arriba mira el valor y no
  // la ausencia: NINGÚN fixture de este archivo siembra `role` —ni los de más
  // abajo, ni los de promote-link.emulator.test.ts—, porque `syncTrainerLoad`
  // nunca lo necesitó. Un chequeo fail-CLOSED los pondría todos en rojo, y en
  // producción le rompería el aceptar a cualquier PF legacy cuyo doc no tenga
  // el campo.
  //
  // No debilita el gate: el ataque usa cuentas del signup PÚBLICO, que escribe
  // `role: 'athlete'` explícito (firestore.rules ~296). Un rol ausente es un
  // doc viejo, no un atacante.
  it("rol ausente NO frena la promoción (PF legacy sin el campo)", async () => {
    const state = install({
      trainer_links: { L1: link() },
      users: { "trainer-1": { subscription: plan1Active } },
    });
    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });
    expect(result.promoted).toBe(true);
    expect(state.trainer_links.L1.status).toBe("active");
  });

  // El gate de rol va SÓLO en el camino de promoción. `linkLoadReconcile`
  // entra acá con `promotion: null` para recomputar
  // `users/{trainerId}.weightedLoad`, que es denormalizado y PARA MOSTRAR: el
  // gate nunca le cree y siempre recalcula en vivo (REQ-PAYWALL-GATE-006).
  //
  // Bloquear ese camino no autoriza nada y sí rompe algo: el trigger tiene un
  // catch-and-log, así que el número que ve un entrenador quedaría viejo en
  // silencio. Sin este test, mover el chequeo una llave más afuera pasa la
  // review sin que nada se ponga rojo.
  it("reconcile (promotion:null) recomputa aunque el rol no sea trainer", async () => {
    const state = install({
      trainer_links: { L1: link({ status: "active" }) },
      users: { "trainer-1": { role: "athlete", subscription: plan1Active } },
    });
    const result = await syncTrainerLoad(app, {
      trainerId: "trainer-1",
      promotion: null,
    });
    expect(result.promoted).toBe(false);
    expect(state.users["trainer-1"].weightedLoad).toBe(1.0);
  });
});

describe("syncTrainerLoad — gate boundary (strict <=)", () => {
  beforeEach(() => jest.clearAllMocks());

  function seedActiveLinks(count: number, trainerId = "trainer-1") {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < count; i++) {
      links[`active-${i}`] = link({ trainerId, athleteId: `a${i}`, status: "active" });
    }
    return links;
  }

  it("6.0 + accept(1.0) = 7.0 at plan1(7) — passes, writes active + weightedLoad", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(6), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });

    expect(result).toMatchObject({ trainerId: "trainer-1", weightedLoad: 7.0, limit: 7, promoted: true });
    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.users["trainer-1"].weightedLoad).toBe(7.0);
  });

  it("7.0 + accept(1.0) = 8.0 at plan1(7) — blocks resource-exhausted, nothing written", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(7), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      }),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "plan-limit", tier: "plan1", limit: 7, currentLoad: 7.0, projectedLoad: 8.0 },
    });

    expect(state.trainer_links.L1.status).toBe("pending");
    expect(state.users["trainer-1"].weightedLoad).toBeUndefined();
  });

  // ── Transition-specific link fields ─────────────────────────────────────
  //
  // The gate REPLACES TrainerLinkRepository.accept()/resume() (slices 2-3),
  // so it must write everything those methods wrote — not just `status`.
  // `accept()` stamped `acceptedAt`; `resume()` cleared `pausedAt`. Dropping
  // either is a SILENT data regression: `trainer_coach_view.dart` renders
  // `acceptedAt ?? requestedAt`, so a missing stamp shows the request date as
  // the start date instead of failing loudly.

  it("accept stamps acceptedAt (replaces repository.accept)", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(2), L1: link({ status: "pending" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
      nowMs: 1_700_000_000_000,
    });

    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.trainer_links.L1.acceptedAt).toEqual(
      Timestamp.fromMillis(1_700_000_000_000),
    );
  });

  it("resume clears pausedAt and does NOT restamp acceptedAt (replaces repository.resume)", async () => {
    const originalAcceptedAt = Timestamp.fromMillis(1_600_000_000_000);
    const state = install({
      trainer_links: {
        ...seedActiveLinks(2),
        L1: link({
          athleteId: "paused-1",
          status: "paused",
          acceptedAt: originalAcceptedAt,
          pausedAt: Timestamp.fromMillis(1_650_000_000_000),
        }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      nowMs: 1_700_000_000_000,
    });

    expect(state.trainer_links.L1.status).toBe("active");
    expect(state.trainer_links.L1.pausedAt).toBe(FieldValue.delete());
    // Preserved — a resumed link is NOT a new one (repository.resume contract).
    expect(state.trainer_links.L1.acceptedAt).toEqual(originalAcceptedAt);
  });

  // A2 — defensa en profundidad del gate que `firestore.rules` le puso a
  // `paused` (sólo desde `active`). Esta callable va por Admin SDK y SE SALTEA
  // las reglas, así que un vínculo que YA quedó en ese estado —revivido antes
  // del fix, o escrito por un script— se resumía igual.
  //
  // Y lo que el resume devuelve son datos de SALUD del alumno:
  // `syncSessionShareOnTrainerLink` re-otorga `session_shares` en la transición
  // a `active`, sobre una relación que el alumno ya había cortado.
  //
  // El discriminador es la EVIDENCIA POSITIVA de que se terminó, no la ausencia
  // de algo: `acceptedAt` NO sirve para esto —el repo lo llama «un DEFECTO DE
  // DATOS, no evidencia de lealtad» en select-blocked-links.ts ~192, o sea que
  // un vínculo real viejo puede no tenerlo— y exigirlo rompería resumes
  // legítimos. `terminatedAt` y `terminationReason`, en cambio, sólo aparecen
  // cuando alguien terminó el vínculo.
  it("A2: DENIEGA resumir un vínculo que arrastra terminatedAt", async () => {
    install({
      trainer_links: {
        L1: link({
          status: "paused",
          acceptedAt: Timestamp.fromMillis(1_600_000_000_000),
          terminatedAt: Timestamp.fromMillis(1_650_000_000_000),
        }),
      },
      users: { "trainer-1": { role: "trainer", subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("A2: DENIEGA resumir un vínculo que arrastra terminationReason", async () => {
    install({
      trainer_links: {
        L1: link({
          status: "paused",
          acceptedAt: Timestamp.fromMillis(1_600_000_000_000),
          terminationReason: "athlete-terminated",
        }),
      },
      users: { "trainer-1": { role: "trainer", subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      }),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  // El ancla de que esto NO toca el accept: una solicitud `pending` no arrastra
  // nada, y aceptar tiene que seguir andando. El ancla del resume legítimo vive
  // arriba, en "resume clears pausedAt and does NOT restamp acceptedAt".
  it("A2: aceptar un pending limpio sigue andando", async () => {
    const state = install({
      trainer_links: { L1: link() },
      users: { "trainer-1": { role: "trainer", subscription: plan1Active } },
    });

    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "pending" },
    });

    expect(result.promoted).toBe(true);
    expect(state.trainer_links.L1.status).toBe("active");
  });

  it("reconciliation (promotion:null) touches no link fields", async () => {
    const state = install({
      trainer_links: { ...seedActiveLinks(2), L1: link({ status: "paused" }) },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await syncTrainerLoad(app, { trainerId: "trainer-1", promotion: null });

    expect(state.trainer_links.L1.status).toBe("paused");
    expect(state.trainer_links.L1.acceptedAt).toBeUndefined();
    expect(state.trainer_links.L1.pausedAt).toBeUndefined();
  });

  it("resume: 6.5 + resume(0.5) = 7.0 at plan1(7) — passes", async () => {
    install({
      trainer_links: {
        ...seedActiveLinks(6),
        L1: link({ athleteId: "paused-1", status: "paused" }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    const result = await syncTrainerLoad(app, {
      promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
    });

    expect(result).toMatchObject({ weightedLoad: 7.0, limit: 7, promoted: true });
  });

  it("resume: two paused, resume one at load 7.0 → projects 7.5 — blocks", async () => {
    install({
      trainer_links: {
        ...seedActiveLinks(6),
        L1: link({ athleteId: "paused-1", status: "paused" }),
        L2: link({ athleteId: "paused-2", status: "paused" }),
      },
      users: { "trainer-1": { subscription: plan1Active } },
    });

    await expect(
      syncTrainerLoad(app, {
        promotion: { linkId: "L1", callerUid: "trainer-1", expectedFromStatus: "paused" },
      }),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
  });
});

describe("syncTrainerLoad — reconciliation (promotion: null)", () => {
  beforeEach(() => jest.clearAllMocks());

  it("recomputes and writes regardless of limit — never blocks, no promotion applied", async () => {
    const links: Record<string, FakeDoc> = {};
    for (let i = 0; i < 15; i++) {
      links[`p${i}`] = link({ athleteId: `a${i}`, status: "paused" });
    }
    const state = install({
      trainer_links: links,
      users: { "trainer-1": { subscription: plan1Active } }, // limit 7, real load 7.5 > limit
    });

    const result = await syncTrainerLoad(app, { trainerId: "trainer-1", promotion: null });

    expect(result).toMatchObject({ trainerId: "trainer-1", weightedLoad: 7.5, limit: 7, promoted: false });
    expect(state.users["trainer-1"].weightedLoad).toBe(7.5);
  });

  it("invalid-argument — trainerId missing with no promotion", async () => {
    install({ trainer_links: {}, users: {} });
    await expect(
      syncTrainerLoad(app, { promotion: null }),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("promotionDenialReason", () => {
  it("plan-limit — limit equals the subscription's nominal tier limit", () => {
    expect(promotionDenialReason({ tier: "plan1", status: "active" }, 7)).toBe("plan-limit");
  });

  it("subscription-inactive — limit is below the nominal tier limit (lapsed paid sub)", () => {
    // plan2 nominal = 15, but effectiveWeightLimit degraded to Free (2) because
    // e.g. status is 'pending'/'paused' — a paid trainer without entitlement.
    expect(promotionDenialReason({ tier: "plan2", status: "pending" }, 2)).toBe("subscription-inactive");
  });

  it("free-tier edge — no subscription, limit equals Free's own nominal (2) → plan-limit", () => {
    expect(promotionDenialReason(null, 2)).toBe("plan-limit");
  });
});
