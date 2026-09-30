/**
 * delete-account-suscripcion-emulador.test.ts — el CABLEADO de `runDeleteAccount`
 * con la baja de la suscripcion.
 *
 * EMULADOR (Firestore + Auth + Storage). Corre como el job `functions-test`:
 *
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand delete-account-suscripcion-emulador"
 *
 * `delete-account-suscripcion.test.ts` (local) prueba el paso por separado. Esto
 * prueba lo que ese no puede: que `runDeleteAccount` lo llame ANTES de la
 * cascada, y que cuando falla no quede NADA tocado —ni el usuario, ni Auth, ni
 * el registro de auditoria—. Un paso correcto, llamado despues, o con el error
 * tragado como los demas pasos de la cascada, reintroduce el bug original: la
 * cuenta borrada con el cobro vivo.
 */

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT ??= "treino-dev";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";

import { DeleteAccountDeps, runDeleteAccount } from "../delete-account";
import { CAMPO_CUENTA_ELIMINADA, reconcileSubscription } from "../subscriptions/mp/reconcile";

const UID = "elimina-con-suscripcion";
const PLAN = "plan-elimina-con-suscripcion";
const AHORA = Date.parse("2026-09-30T12:00:00.000Z");
const DIA_MS = 24 * 60 * 60 * 1000;

let app: App;

beforeAll(() => {
  app = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "suscripcion-test",
  );
});

afterAll(async () => {
  await deleteApp(app);
});

const db = () => getFirestore(app);
const existe = async (col: string, id: string) => (await db().collection(col).doc(id).get()).exists;
const hayAuth = () => getAuth(app).getUser(UID).then(() => true, () => false);

const VIVA = {
  id: "sub-1",
  status: "authorized",
  external_reference: UID,
  preapproval_plan_id: PLAN,
  next_payment_date: new Date(AHORA + 10 * DIA_MS).toISOString(),
  auto_recurring: { transaction_amount: 3500 },
  summarized: { pending_charge_quantity: 0 },
};

function fakeMp(over: { fallaBusqueda?: boolean; subs?: Record<string, unknown>[] } = {}) {
  const canceladas: string[] = [];
  const mpClient = {
    getPreapproval: async () => ({}),
    createPreapprovalPlan: async () => ({}),
    searchPreapprovalsByPlan: async () => {
      if (over.fallaBusqueda) throw new Error("MP 503");
      return over.subs ?? [];
    },
    cancelPreapproval: async (id: string) => {
      canceladas.push(id);
      return { id, status: "cancelled" };
    },
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const deps: DeleteAccountDeps = { nowMs: AHORA, getMpClient: () => mpClient as any };
  return { canceladas, deps, mpClient };
}

async function sembrar(conPlan: boolean) {
  await getAuth(app).createUser({ uid: UID, email: `${UID}@test.com` });
  await db().collection("users").doc(UID).set({
    uid: UID,
    role: "athlete",
    email: `${UID}@test.com`,
    athleteSubscription: { status: "active" },
  });
  if (conPlan) {
    await db().collection("mp_plans").doc(PLAN).set({ producto: "athlete", uid: UID, cycle: "monthly" });
  }
}

afterEach(async () => {
  await Promise.all([
    getAuth(app).deleteUser(UID).catch(() => undefined),
    db().recursiveDelete(db().collection("users").doc(UID)).catch(() => undefined),
    db().collection("mp_plans").doc(PLAN).delete().catch(() => undefined),
    db().collection("mp_cancelaciones").doc(UID).delete().catch(() => undefined),
    db().collection("audit_log").doc(UID).delete().catch(() => undefined),
    db().collection("userPublicProfiles").doc(UID).delete().catch(() => undefined),
  ]);
});

describe("runDeleteAccount con una suscripcion viva", () => {
  it("la cancela en MP, borra la cuenta y deja el plan marcado", async () => {
    await sembrar(true);
    const mp = fakeMp({ subs: [VIVA] });

    const r = await runDeleteAccount(app, UID, "password", mp.deps);

    expect(r.status).toBe("success");
    expect(r.deletedCollections).toContain("mp-subscriptions");
    expect(mp.canceladas).toEqual(["sub-1"]);
    expect(await existe("users", UID)).toBe(false);
    expect(await hayAuth()).toBe(false);
    // El plan se conserva —es un registro de cobro, con uid— pero marcado.
    const plan = (await db().collection("mp_plans").doc(PLAN).get()).data();
    expect(plan?.[CAMPO_CUENTA_ELIMINADA]).toBe(AHORA);
  });

  it("y el aviso posterior de MP NO recrea el usuario fantasma", async () => {
    // El `cancelled` que MP manda por webhook llega DESPUES de la cascada. El
    // reconciliador escribe con `set` + `merge` sobre `users/{uid}`: sin la
    // guarda, el documento reaparece vacio.
    await sembrar(true);
    const mp = fakeMp({ subs: [VIVA] });
    await runDeleteAccount(app, UID, "password", mp.deps);

    const r = await reconcileSubscription(
      app,
      PLAN,
      { mpClient: mp.mpClient, nowMs: AHORA + 5_000 } as never,
      { ...VIVA, status: "cancelled" },
    );

    expect(r.outcome).toBe("skipped-cuenta-eliminada");
    expect(await existe("users", UID)).toBe(false);
  });

  it("si MP no contesta NO se toca nada: ni el usuario, ni Auth, ni la auditoria", async () => {
    await sembrar(true);
    const mp = fakeMp({ fallaBusqueda: true });

    await expect(runDeleteAccount(app, UID, "password", mp.deps)).rejects.toMatchObject({
      code: "unavailable",
    });

    expect(await existe("users", UID)).toBe(true);
    expect(await hayAuth()).toBe(true);
    // `writeStarted` tampoco corrio: no quedo un «started» sin final.
    expect(await existe("audit_log", UID)).toBe(false);
    const plan = (await db().collection("mp_plans").doc(PLAN).get()).data();
    expect(plan?.[CAMPO_CUENTA_ELIMINADA]).toBeUndefined();
  });
});

describe("runDeleteAccount sin planes", () => {
  it("borra sin armar el cliente de MP (un token vacio no puede frenar a quien nunca pago)", async () => {
    await sembrar(false);
    const deps: DeleteAccountDeps = {
      nowMs: AHORA,
      getMpClient: () => {
        throw new Error("no deberia armarse");
      },
    };

    const r = await runDeleteAccount(app, UID, "password", deps);

    expect(r.status).toBe("success");
    expect(r.deletedCollections).not.toContain("mp-subscriptions");
    expect(await hayAuth()).toBe(false);
  });
});
