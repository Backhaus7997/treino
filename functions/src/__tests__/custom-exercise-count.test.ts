/**
 * [EMULATOR-CI] Integration tests for `handleCustomExerciseWrite` /
 * `recountCustomExercises` against un Firestore emulador REAL
 * (limite-ejercicios-pf.md, PR1).
 *
 * Contra emulador y no con un fake, a proposito: `recountCustomExercises` usa
 * `.count()`, la PRIMERA agregacion `count()` de Cloud Functions en este
 * repo. Es exactamente el riesgo que el plan marca como "verificar contra el
 * emulador, no asumir" — un fake de Firestore no ejercita la agregacion real.
 *
 * Se testea `handleCustomExerciseWrite` (el handler extraido, mismo patron
 * que `reassignFcmTokenHandler`), no el `onDocumentWritten` en si: el
 * emulador de Firestore NO dispara triggers v2 por si solo — hace falta el
 * emulador de Functions, que no esta en el comando de este archivo. Los
 * casos "create recuenta" / "delete recuenta" / "un alumno no escribe nada"
 * llaman al handler con los mismos argumentos que le pasaria el trigger real.
 *
 * Requiere el emulador de Firestore (Java 21+):
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand custom-exercise-count"
 *
 * Pattern mirrors reassign-fcm-token.integration.test.ts: Admin SDK contra
 * `FIRESTORE_EMULATOR_HOST`, app de test con nombre propio, seed/cleanup por
 * test.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { DocumentReference, Firestore, getFirestore } from "firebase-admin/firestore";

import {
  handleCustomExerciseWrite,
  isCreateOrDelete,
} from "../subscriptions/custom-exercise-count";
import { recountCustomExercises } from "../subscriptions/trainer-plan-limits";

// `??=` y NUNCA `=`: cuando este archivo corre bajo
// `firebase emulators:exec`, el host YA esta seteado (posiblemente en un
// puerto alternativo, si el 8080 estaba ocupado por otra sesion) y pisarlo
// con `=` desviaria este archivo a un emulador que no existe.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp(
    { projectId: process.env.GCLOUD_PROJECT },
    "custom-exercise-count-test",
  );
});

afterAll(async () => {
  await deleteApp(testApp);
});

const db = (): Firestore => getFirestore(testApp);
const user = (uid: string): DocumentReference => db().collection("users").doc(uid);
const customExercises = (uid: string) => user(uid).collection("customExercises");

const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function seedTrainer(uid: string, extra: Record<string, unknown> = {}) {
  await user(uid).set({ role: "trainer", ...extra });
}

async function seedAthlete(uid: string, extra: Record<string, unknown> = {}) {
  await user(uid).set({ role: "athlete", ...extra });
}

async function cleanup(...uids: string[]): Promise<void> {
  for (const uid of uids) {
    const exSnap = await customExercises(uid).get();
    await Promise.all(exSnap.docs.map((d) => d.ref.delete()));
    await user(uid).delete().catch(() => undefined);
  }
}

describe("isCreateOrDelete", () => {
  it("create (before ausente, after presente) → true", () => {
    expect(isCreateOrDelete(false, true)).toBe(true);
  });

  it("delete (before presente, after ausente) → true", () => {
    expect(isCreateOrDelete(true, false)).toBe(true);
  });

  it("update (los dos presentes) → false", () => {
    expect(isCreateOrDelete(true, true)).toBe(false);
  });
});

describe("recountCustomExercises — contra el emulador real", () => {
  const UID = "emu-exercises-trainer-1";

  afterEach(async () => cleanup(UID));

  it("cuenta los documentos reales de la subcoleccion con .count()", async () => {
    await seedTrainer(UID);
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });
    await customExercises(UID).doc("e2").set({ name: "Press banca" });

    const r = await recountCustomExercises(testApp, UID);

    expect(r.count).toBe(2);
    expect(r.changed).toBe(true);
    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 2 });
  });

  it("escribe el valor ABSOLUTO, no incrementa", async () => {
    await seedTrainer(UID, { customExerciseUsage: { count: 99 } });
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    const r = await recountCustomExercises(testApp, UID);

    expect(r.count).toBe(1);
    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 1 });
  });

  it("una REDELIVERY (llamar dos veces seguidas) deja el mismo valor y no vuelve a escribir", async () => {
    await seedTrainer(UID);
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    const primera = await recountCustomExercises(testApp, UID);
    expect(primera.changed).toBe(true);
    expect(primera.count).toBe(1);

    const segunda = await recountCustomExercises(testApp, UID);
    expect(segunda.changed).toBe(false);
    expect(segunda.count).toBe(1);

    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 1 });
  });

  it("cero ejercicios propios cuenta 0, no deja el campo ausente", async () => {
    await seedTrainer(UID);

    const r = await recountCustomExercises(testApp, UID);

    expect(r.count).toBe(0);
    expect(r.changed).toBe(true);
    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 0 });
  });

  it("sin doc de perfil, no hay donde escribir — no explota, no crea el doc", async () => {
    // Ni seedTrainer ni seedAthlete: UID sin `users/{uid}`.
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    const r = await recountCustomExercises(testApp, UID);

    expect(r.count).toBe(1);
    const snap = await user(UID).get();
    expect(snap.exists).toBe(false);
  });

  it("dos recuentos concurrentes terminan en el valor real (R1)", async () => {
    // La carrera, escenificada: el contador esta en 1 y hay 2 ejercicios. El
    // recuento A cuenta 2 y, antes de escribir, se crea el tercero y OTRA
    // invocacion (B) la cuenta. Sin transaccion B escribe 3 y despues A pisa
    // con 2: quedan 3 ejercicios con el contador en 2, y la regla dejaria
    // crear uno de mas. En transaccion, el que escribe ultimo conto despues
    // del otro.
    //
    // B arranca SIN await adentro del hook: A tiene tomado el doc del usuario
    // (y, segun como bloquee el emulador, la subcoleccion), y esperar a B
    // desde adentro de A seria esperar a alguien que espera a A. VERIFICADO,
    // no asumido: cambiar el `dormir` de abajo por `await b` cuelga el test
    // completo (timeout de 30s) contra el emulador real — B nunca llega a
    // comitear su transaccion mientras la de A este abierta. La pausa
    // acotada es la unica forma de intercalar sin deadlock; le da a B tiempo
    // de terminar si nada lo frena, que es exactamente lo que pasa sin
    // transaccion.
    await seedTrainer(UID, { customExerciseUsage: { count: 1 } });
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });
    await customExercises(UID).doc("e2").set({ name: "Press banca" });

    let yaIntercalado = false;
    let b: Promise<unknown> = Promise.resolve();
    const a = recountCustomExercises(testApp, UID, {
      afterCount: async () => {
        if (yaIntercalado) return; // un reintento de A no vuelve a intercalar
        yaIntercalado = true;
        b = customExercises(UID)
          .doc("e3")
          .set({ name: "Peso muerto" })
          .then(() => recountCustomExercises(testApp, UID));
        await dormir(1500);
      },
    });

    await a;
    await b;

    expect(yaIntercalado).toBe(true);
    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 3 });
  }, 30_000);
});

describe("handleCustomExerciseWrite — el handler del trigger, end to end contra el emulador", () => {
  const UID = "emu-exercises-trainer-2";
  const ATHLETE_UID = "emu-exercises-athlete-1";

  afterEach(async () => cleanup(UID, ATHLETE_UID));

  it("CREATE recuenta para un trainer", async () => {
    await seedTrainer(UID);
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    await handleCustomExerciseWrite(testApp, UID, false, true);

    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 1 });
  });

  it("DELETE recuenta para un trainer", async () => {
    await seedTrainer(UID, { customExerciseUsage: { count: 2 } });
    // Solo queda UNO en la subcoleccion real — el otro ya se borro antes de
    // que este handler corra, que es exactamente lo que ve el trigger real
    // despues de un delete.
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    await handleCustomExerciseWrite(testApp, UID, true, false);

    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 1 });
  });

  it("UPDATE no escribe nada — ni siquiera lee el doc del usuario", async () => {
    await seedTrainer(UID, { customExerciseUsage: { count: 5 } });
    // La subcoleccion real dice 1, pero un update NO tiene que disparar el
    // recuento: si lo hiciera, este test lo detectaria porque count() pasaria
    // de 5 a 1.
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    await handleCustomExerciseWrite(testApp, UID, true, true);

    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 5 });
  });

  it("un ALUMNO (role != trainer) no escribe nada, aunque cree un ejercicio", async () => {
    await seedAthlete(ATHLETE_UID);
    await customExercises(ATHLETE_UID).doc("e1").set({ name: "Sentadilla" });

    await handleCustomExerciseWrite(testApp, ATHLETE_UID, false, true);

    const snap = await user(ATHLETE_UID).get();
    expect(snap.get("customExerciseUsage")).toBeUndefined();
  });

  it("una redelivery del handler completo (dos llamadas seguidas) deja el mismo valor", async () => {
    await seedTrainer(UID);
    await customExercises(UID).doc("e1").set({ name: "Sentadilla" });

    await handleCustomExerciseWrite(testApp, UID, false, true);
    await handleCustomExerciseWrite(testApp, UID, false, true);

    const snap = await user(UID).get();
    expect(snap.get("customExerciseUsage")).toEqual({ count: 1 });
  });
});
