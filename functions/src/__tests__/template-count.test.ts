/**
 * [EMULATOR-CI] `recountTemplates` y el handler de `maintainTemplateCount`
 * contra un Firestore emulador REAL (limite-plantillas-pf.md, PR1).
 *
 * Contra emulador y no con un fake, por lo mismo que
 * `custom-exercise-count.test.ts`, y por dos cosas mas que un fake no puede
 * probar: que el `count()` corra ADENTRO de una transaccion (verificado en los
 * tipos del SDK, pero hay que verlo andar), y que el recuento cierre la
 * carrera entre dos invocaciones concurrentes.
 *
 * El handler se llama directo con el `before`/`after` que leeria el trigger:
 * el emulador de Firestore no dispara triggers v2 solo. `escribir` hace
 * exactamente eso — lee, escribe con el Admin SDK, relee y llama al handler.
 *
 * Requiere el emulador de Firestore (Java 21+):
 *   firebase emulators:exec --only firestore,auth,storage --project treino-dev \
 *     "npm --prefix functions test -- --runInBand template-count"
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import {
  DocumentData,
  DocumentReference,
  Firestore,
  getFirestore,
} from "firebase-admin/firestore";

import {
  countsFor,
  handleTemplateWrite,
  ownersToRecount,
} from "../subscriptions/template-count";
import {
  recountTemplates,
  resolvePlanLimits,
} from "../subscriptions/trainer-plan-limits";

// `??=` y NUNCA `=`: bajo `firebase emulators:exec` el host YA esta seteado,
// posiblemente en un puerto alternativo si el 8080 es de otra sesion.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp(
    { projectId: process.env.GCLOUD_PROJECT },
    "template-count-test",
  );
});

afterAll(async () => {
  await deleteApp(testApp);
});

const db = (): Firestore => getFirestore(testApp);
const user = (uid: string): DocumentReference => db().collection("users").doc(uid);
const routine = (id: string): DocumentReference => db().collection("routines").doc(id);

const PF = "emu-templates-pf-1";
const PF2 = "emu-templates-pf-2";
const ALUMNO = "emu-templates-athlete-1";

/** Todas las rutinas que tocan estos tests, para limpiarlas. */
const rutinasCreadas = new Set<string>();

function plantilla(
  owner: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    name: "Full body",
    source: "trainer-template",
    assignedBy: owner,
    status: "active",
    ...extra,
  };
}

/**
 * Lo que ve el trigger real: el doc antes, la escritura, el doc despues. Con
 * `data === null` borra; con `merge` actualiza campos sueltos.
 */
async function escribir(
  id: string,
  data: Record<string, unknown> | null,
  { merge = false }: { merge?: boolean } = {},
): Promise<void> {
  rutinasCreadas.add(id);
  const ref = routine(id);
  const before: DocumentData | undefined = (await ref.get()).data();
  if (data === null) await ref.delete();
  else await ref.set(data, { merge });
  const after: DocumentData | undefined = (await ref.get()).data();
  await handleTemplateWrite(testApp, id, before, after);
}

/** Siembra una rutina SIN pasar por el handler (estado previo del test). */
async function sembrar(id: string, data: Record<string, unknown>): Promise<void> {
  rutinasCreadas.add(id);
  await routine(id).set(data);
}

async function uso(uid: string): Promise<unknown> {
  return (await user(uid).get()).get("templateUsage");
}

async function cleanup(): Promise<void> {
  await Promise.all([...rutinasCreadas].map((id) => routine(id).delete()));
  rutinasCreadas.clear();
  await Promise.all(
    [PF, PF2, ALUMNO].map((uid) => user(uid).delete().catch(() => undefined)),
  );
}

const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

// ─────────────────────────────────────────────────────────────────────────
// La guarda, sin emulador.
// ─────────────────────────────────────────────────────────────────────────

describe("countsFor", () => {
  it("una plantilla activa cuenta para su dueño", () => {
    expect(countsFor(plantilla("u1"))).toBe("u1");
  });

  it("una plantilla SIN status cuenta (default active del modelo)", () => {
    const { status: _omitida, ...sinStatus } = plantilla("u1");
    void _omitida;
    expect(countsFor(sinStatus)).toBe("u1");
  });

  it("archivada, de otra fuente, sin dueño o borrada: no cuenta", () => {
    expect(countsFor(plantilla("u1", { status: "archived" }))).toBeNull();
    expect(countsFor(plantilla("u1", { source: "trainer-assigned" }))).toBeNull();
    expect(countsFor(plantilla("u1", { source: "athlete" }))).toBeNull();
    expect(countsFor(plantilla("u1", { assignedBy: undefined }))).toBeNull();
    expect(countsFor(plantilla("u1", { assignedBy: "" }))).toBeNull();
    expect(countsFor(plantilla("u1", { assignedBy: 42 }))).toBeNull();
    expect(countsFor(undefined)).toBeNull();
  });
});

describe("ownersToRecount", () => {
  it("crear, borrar, archivar y restaurar: el dueño", () => {
    expect(ownersToRecount(undefined, plantilla("u1"))).toEqual(["u1"]);
    expect(ownersToRecount(plantilla("u1"), undefined)).toEqual(["u1"]);
    expect(
      ownersToRecount(plantilla("u1"), plantilla("u1", { status: "archived" })),
    ).toEqual(["u1"]);
    expect(
      ownersToRecount(plantilla("u1", { status: "archived" }), plantilla("u1")),
    ).toEqual(["u1"]);
  });

  it("editar el contenido o recibir un rating: nadie", () => {
    expect(
      ownersToRecount(plantilla("u1"), plantilla("u1", { name: "Otro nombre" })),
    ).toEqual([]);
    expect(
      ownersToRecount(plantilla("u1"), plantilla("u1", { ratingAvg: 4.5, ratingCount: 2 })),
    ).toEqual([]);
  });

  it("rutinas del alumno y planes asignados: nadie", () => {
    const propia = { source: "athlete", createdBy: "a1", status: "active" };
    const asignado = { source: "trainer-assigned", assignedBy: "u1", assignedTo: "a1" };
    expect(ownersToRecount(undefined, propia)).toEqual([]);
    expect(ownersToRecount(undefined, asignado)).toEqual([]);
    expect(ownersToRecount(asignado, { ...asignado, status: "archived" })).toEqual([]);
  });

  it("borrar o crear una plantilla YA archivada: nadie, no movia el conteo", () => {
    const archivada = plantilla("u1", { status: "archived" });
    expect(ownersToRecount(undefined, archivada)).toEqual([]);
    expect(ownersToRecount(archivada, undefined)).toEqual([]);
  });

  it("cambio de assignedBy: los DOS dueños", () => {
    expect(ownersToRecount(plantilla("u1"), plantilla("u2"))).toEqual(["u1", "u2"]);
  });

  it("cambio de source: el dueño, en las dos direcciones", () => {
    const asignado = plantilla("u1", { source: "trainer-assigned" });
    expect(ownersToRecount(asignado, plantilla("u1"))).toEqual(["u1"]);
    expect(ownersToRecount(plantilla("u1"), asignado)).toEqual(["u1"]);
  });

  it("cambio de assignedBy sobre una archivada: nadie, no contaba para ninguno", () => {
    expect(
      ownersToRecount(
        plantilla("u1", { status: "archived" }),
        plantilla("u2", { status: "archived" }),
      ),
    ).toEqual([]);
  });
});

// ─────────────────────────────────────────────────────────────────────────
// recountTemplates, contra el emulador.
// ─────────────────────────────────────────────────────────────────────────

describe("recountTemplates — contra el emulador real", () => {
  afterEach(cleanup);

  it("cuenta total menos archivadas: la que no tiene status cuenta", async () => {
    await user(PF).set({ role: "trainer" });
    await sembrar("rc-1", plantilla(PF));
    await sembrar("rc-2", plantilla(PF, { status: "archived" }));
    const { status: _s, ...sinStatus } = plantilla(PF);
    void _s;
    await sembrar("rc-3", sinStatus);
    // Del mismo PF pero no plantillas, y una plantilla de otro PF: no cuentan.
    await sembrar("rc-4", plantilla(PF, { source: "trainer-assigned", assignedTo: "x" }));
    await sembrar("rc-5", plantilla(PF2));

    const r = await recountTemplates(testApp, PF);

    expect(r).toEqual({ uid: PF, count: 2, changed: true });
    expect(await uso(PF)).toEqual({ count: 2 });
  });

  it("escribe el valor ABSOLUTO, y una redelivery no vuelve a escribir", async () => {
    await user(PF).set({ role: "trainer", templateUsage: { count: 99 } });
    await sembrar("rc-6", plantilla(PF));

    const primera = await recountTemplates(testApp, PF);
    const segunda = await recountTemplates(testApp, PF);

    expect(primera).toEqual({ uid: PF, count: 1, changed: true });
    expect(segunda).toEqual({ uid: PF, count: 1, changed: false });
    expect(await uso(PF)).toEqual({ count: 1 });
  });

  it("cero plantillas cuenta 0, no deja el campo ausente", async () => {
    await user(PF).set({ role: "trainer" });

    expect(await recountTemplates(testApp, PF)).toEqual({
      uid: PF,
      count: 0,
      changed: true,
    });
    expect(await uso(PF)).toEqual({ count: 0 });
  });

  it("un alumno no recibe contador, aunque tenga un trainer-template forjado", async () => {
    await user(ALUMNO).set({ role: "athlete" });
    await sembrar("rc-7", plantilla(ALUMNO));

    expect(await recountTemplates(testApp, ALUMNO)).toBeNull();
    expect(await uso(ALUMNO)).toBeUndefined();
  });

  it("sin doc de perfil no hay donde escribir — no crea el doc", async () => {
    await sembrar("rc-8", plantilla(PF));

    expect(await recountTemplates(testApp, PF)).toBeNull();
    expect((await user(PF).get()).exists).toBe(false);
  });

  it("dos recuentos concurrentes terminan en el valor real (R1 del plan)", async () => {
    // La carrera, escenificada: el contador esta en 1 y hay 2 plantillas. El
    // recuento A cuenta 2 y, antes de escribir, se crea la tercera y OTRA
    // invocacion (B) la cuenta. Sin transaccion B escribe 3 y despues A pisa
    // con 2: quedan 3 plantillas con el contador en 2, y la regla dejaria
    // crear una cuarta. En transaccion, el que escribe ultimo conto despues
    // del otro.
    //
    // B arranca SIN await adentro del hook: A tiene tomado el doc del usuario
    // (y, segun como bloquee el emulador, las plantillas), y esperar a B desde
    // adentro de A seria esperar a alguien que espera a A. La pausa le da a B
    // tiempo de terminar si nada lo frena, que es exactamente lo que pasa sin
    // transaccion.
    await user(PF).set({ role: "trainer", templateUsage: { count: 1 } });
    await sembrar("rc-9", plantilla(PF));
    await sembrar("rc-10", plantilla(PF));
    rutinasCreadas.add("rc-11");

    let yaIntercalado = false;
    let b: Promise<unknown> = Promise.resolve();
    const a = recountTemplates(testApp, PF, {
      afterCount: async () => {
        if (yaIntercalado) return; // un reintento de A no vuelve a intercalar
        yaIntercalado = true;
        b = routine("rc-11")
          .set(plantilla(PF))
          .then(() => recountTemplates(testApp, PF));
        await dormir(1500);
      },
    });

    await a;
    await b;

    expect(yaIntercalado).toBe(true);
    expect(await uso(PF)).toEqual({ count: 3 });
  }, 30_000);
});

// ─────────────────────────────────────────────────────────────────────────
// El handler del trigger, end to end contra el emulador.
// ─────────────────────────────────────────────────────────────────────────

describe("handleTemplateWrite — el handler del trigger", () => {
  afterEach(cleanup);

  it("crear, archivar, restaurar y borrar una plantilla recuentan", async () => {
    await user(PF).set({ role: "trainer" });

    await escribir("h-1", plantilla(PF));
    expect(await uso(PF)).toEqual({ count: 1 });

    await escribir("h-1", { status: "archived" }, { merge: true });
    expect(await uso(PF)).toEqual({ count: 0 });

    await escribir("h-1", { status: "active" }, { merge: true });
    expect(await uso(PF)).toEqual({ count: 1 });

    await escribir("h-1", null);
    expect(await uso(PF)).toEqual({ count: 0 });
  });

  it("una plantilla sin status cuenta", async () => {
    await user(PF).set({ role: "trainer" });
    const { status: _s, ...sinStatus } = plantilla(PF);
    void _s;

    await escribir("h-2", sinStatus);

    expect(await uso(PF)).toEqual({ count: 1 });
  });

  // Los que siguen siembran un contador EQUIVOCADO a proposito: si el handler
  // recontara, lo corregiria y el test lo veria. Que quede igual es la prueba
  // de que no escribio.

  it("editar el contenido o recibir un rating NO escribe", async () => {
    await user(PF).set({ role: "trainer", templateUsage: { count: 9 } });
    await sembrar("h-3", plantilla(PF));

    await escribir("h-3", { name: "Otro nombre", days: [] }, { merge: true });
    await escribir("h-3", { ratingAvg: 4.5, ratingCount: 2 }, { merge: true });

    expect(await uso(PF)).toEqual({ count: 9 });
  });

  it("una rutina del alumno o un plan asignado NO escriben", async () => {
    await user(PF).set({ role: "trainer", templateUsage: { count: 9 } });

    await escribir("h-4", { source: "athlete", createdBy: PF, status: "active" });
    await escribir("h-5", {
      source: "trainer-assigned",
      assignedBy: PF,
      assignedTo: ALUMNO,
      status: "active",
    });
    await escribir("h-5", { status: "archived" }, { merge: true });

    expect(await uso(PF)).toEqual({ count: 9 });
  });

  it("un alumno con un trainer-template forjado NO recibe contador", async () => {
    await user(ALUMNO).set({ role: "athlete" });

    await escribir("h-6", plantilla(ALUMNO));

    expect(await uso(ALUMNO)).toBeUndefined();
  });

  it("una redelivery del handler completo deja el mismo valor", async () => {
    await user(PF).set({ role: "trainer" });
    rutinasCreadas.add("h-7");
    await routine("h-7").set(plantilla(PF));
    const after = (await routine("h-7").get()).data();

    await handleTemplateWrite(testApp, "h-7", undefined, after);
    await handleTemplateWrite(testApp, "h-7", undefined, after);

    expect(await uso(PF)).toEqual({ count: 1 });
  });

  it("un cambio de assignedBy por Admin SDK recuenta a los DOS dueños", async () => {
    await user(PF).set({ role: "trainer", templateUsage: { count: 2 } });
    await user(PF2).set({ role: "trainer", templateUsage: { count: 1 } });
    await sembrar("h-8", plantilla(PF));
    await sembrar("h-9", plantilla(PF));
    await sembrar("h-10", plantilla(PF2));

    await escribir("h-9", { assignedBy: PF2 }, { merge: true });

    expect(await uso(PF)).toEqual({ count: 1 });
    expect(await uso(PF2)).toEqual({ count: 2 });
  });

  it("un cambio de source por Admin SDK recuenta", async () => {
    await user(PF).set({ role: "trainer", templateUsage: { count: 0 } });
    await sembrar("h-11", plantilla(PF, { source: "trainer-assigned" }));

    await escribir("h-11", { source: "trainer-template" }, { merge: true });

    expect(await uso(PF)).toEqual({ count: 1 });
  });
});

// ─────────────────────────────────────────────────────────────────────────
// El supuesto del mapa parcial de `resolvePlanLimits`.
// ─────────────────────────────────────────────────────────────────────────

describe("planLimits parcial + merge: true — contra el emulador real", () => {
  afterEach(cleanup);

  it("la clave que no viaja queda como estaba (mapas anidados, campo por campo)", async () => {
    // `resolvePlanLimits` con `degraded` y un interruptor prendido devuelve
    // un mapa PARCIAL, y `sync-entitlements.ts` lo escribe con `tx.set(...,
    // {merge: true})`. Todo el diseño de «cada interruptor gobierna solo su
    // clave» descansa en que Firestore mergee el mapa anidado campo por campo
    // y no lo reemplace entero. El fake de `sync-entitlements.test.ts` hace
    // spread SHALLOW, asi que esto solo se puede probar aca.
    await user(PF).set({
      role: "trainer",
      planLimits: { customExercises: 20, templates: 3 },
    });
    const parcial = resolvePlanLimits(
      { tier: "plan2", status: "active" },
      true,
      1_000,
      { customExercises: false, templates: true },
    );
    expect(parcial).toEqual({ customExercises: null });

    await db().runTransaction(async (tx) => {
      tx.set(user(PF), { planLimits: parcial }, { merge: true });
    });

    expect((await user(PF).get()).get("planLimits")).toEqual({
      customExercises: null,
      templates: 3,
    });
  });
});
