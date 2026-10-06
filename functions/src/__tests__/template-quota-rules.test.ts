/**
 * Firestore security-rules enforcement tests for el tope de plantillas del
 * PF por plan (limite-plantillas-pf.md §3 PR2).
 *
 * `templateQuotaOk`, en `firestore.rules`, corta en DOS lugares:
 *
 *   - CREATE branch 1 de `routines` (trainer-template), y SOLO si la
 *     plantilla creada cuenta (`status` != 'archived').
 *   - UPDATE path 6 de `routines` (archivar/restaurar), y SOLO al restaurar
 *     una trainer-template (`resource.data.status == 'archived'` antes del
 *     update).
 *
 * Nunca en: editar contenido (path 4), publicar (path 5), asignar un plan
 * (`trainer-assigned`), archivar, ni DELETE.
 *
 * Uses `@firebase/rules-unit-testing` against the Firestore emulator with
 * `firestore.rules` actually loaded and enforced — mismo patrón que
 * `custom-exercises-quota-rules.test.ts` y `template-publishing-rules.test.ts`.
 *
 * Run against the Firestore emulator:
 *   firebase emulators:exec --only firestore,auth,storage \
 *     "npm --prefix functions test -- --runInBand template-quota-rules"
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

const PROJECT_ID = "treino-rules-test-tplquota001";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const COL_USERS = "users";
const COL_ROUTINES = "routines";

let testEnv: RulesTestEnvironment;

// Mismo margen que template-publishing-rules.test.ts: bajo --runInBand jest
// corre las suites en el orden que las descubre, y la primera que arranca
// paga el cold start del emulador.
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
}, 120_000);

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

interface UserFixture {
  role: "athlete" | "trainer";
  planLimits?: Record<string, unknown> | null;
  templateUsage?: Record<string, unknown> | null;
}

async function seedUser(uid: string, fixture: UserFixture): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(COL_USERS).doc(uid).set(fixture);
  });
}

function templateDoc(owner: string, overrides: Record<string, unknown> = {}) {
  return {
    name: "Full body",
    split: "full-body",
    level: "beginner",
    days: [],
    numWeeks: 1,
    source: "trainer-template",
    visibility: "private",
    assignedBy: owner,
    assignedTo: null,
    status: "active",
    createdAt: new Date(),
    ...overrides,
  };
}

async function seedTemplate(
  id: string,
  owner: string,
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_ROUTINES)
      .doc(id)
      .set(templateDoc(owner, overrides));
  });
}

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

// ---------------------------------------------------------------------------
// 1. Crear plantillas: bajo el tope, en el tope, y sobre el tope.
// ---------------------------------------------------------------------------
describe("crear una trainer-template — CREATE branch 1", () => {
  it("un PF Free con 2 plantillas crea la tercera", async () => {
    const uid = "pf-bajo-tope";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 2 },
    });

    await assertSucceeds(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  it("un PF Free con 3 plantillas NO crea la cuarta", async () => {
    const uid = "pf-en-tope";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    });

    await assertFails(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  it("en el tope, crear una plantilla YA ARCHIVADA pasa — no suma al conteo", async () => {
    const uid = "pf-en-tope-archivada";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .add(templateDoc(uid, { status: "archived" })),
    );
  });

  it("límite null crea sin límite", async () => {
    const uid = "pf-plan-pago";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: null },
      templateUsage: { count: 999 },
    });

    await assertSucceeds(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  it("planLimits AUSENTE crea (interruptor apagado / sin primer sync)", async () => {
    const uid = "pf-sin-sync";
    await seedUser(uid, { role: "trainer" });

    await assertSucceeds(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  it("planLimits.templates NO numérico deniega (falla cerrado)", async () => {
    const uid = "pf-dato-corrupto";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: "3" as unknown as number },
      templateUsage: { count: 0 },
    });

    await assertFails(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  // A3 — este test afirmaba `assertSucceeds`: el forjado de un alumno pasaba, y
  // el nombre decía "como hasta hoy". Era cierto y era el agujero: la rama del
  // PF en el CREATE validaba `source`/`visibility`/`assignedTo` y nada más, así
  // que cualquier cuenta escribía un doc diciendo que lo hizo un entrenador.
  //
  // Ahora se deniega, y conviene ser preciso sobre POR QUÉ: no lo frena la
  // cuota —que efectivamente no se le aplica a un alumno, y eso no cambió— sino
  // el gate de rol del create. Los dos campos de cuota se dejan sembrados a
  // propósito, con valores que la harían fallar, para que el deny no se pueda
  // confundir con un rechazo por tope.
  it("un alumno NO puede crear un forjado: lo frena el rol, no la cuota", async () => {
    const uid = "alumno-forjado";
    await seedUser(uid, {
      role: "athlete",
      planLimits: { templates: 0 },
      templateUsage: { count: 999 },
    });

    await assertFails(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  it("crear un plan asignado (trainer-assigned) nunca mira la cuota", async () => {
    const uid = "pf-en-tope-asigna";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .add(
          templateDoc(uid, {
            source: "trainer-assigned",
            visibility: "private",
            assignedTo: "athlete-1",
          }),
        ),
    );
  });

  // Lo que este test mide es que la CUOTA falla abierta cuando no hay datos de
  // cuota — no que el create entero sea gratis sin doc de usuario.
  //
  // Antes esas dos cosas eran la misma, porque sin doc de perfil no había nada
  // que mirar. Con el gate de rol de A3 se separan, y la asimetría es
  // deliberada: la cuota falla ABIERTA (ante la duda, no le cobres a un PF real
  // por un dato que falta) y el rol falla CERRADO (ante la duda, no me consta
  // que sea PF). Es la política que el propio repo escribe en `promote-link.ts`:
  // la degradación de datos frena TRABAJO NUEVO, y crear una plantilla lo es.
  //
  // Así que el fixture siembra el rol y NADA de cuota, que es lo que el test
  // quiere observar. Sin eso miraría el deny del rol creyendo que mira el de la
  // cuota — un verde por el motivo equivocado.
  it("con rol pero sin datos de cuota, la cuota falla ABIERTA", async () => {
    const uid = "pf-sin-datos-de-cuota";
    await seedUser(uid, { role: "trainer" });

    await assertSucceeds(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });

  // Y la contracara, que antes no se podía escribir: sin doc de usuario no hay
  // rol que mostrar, y el create se deniega. Fija el fail-closed del gate.
  it("sin doc de usuario, el create se deniega (el rol falla CERRADO)", async () => {
    const uid = "pf-sin-doc-de-perfil";

    await assertFails(
      asUser(uid).collection(COL_ROUTINES).add(templateDoc(uid)),
    );
  });
});

// ---------------------------------------------------------------------------
// 2. Restaurar una plantilla archivada — UPDATE path 6.
// ---------------------------------------------------------------------------
describe("restaurar una trainer-template archivada — UPDATE path 6", () => {
  it("con lugar, restaura", async () => {
    const uid = "pf-restaura-con-lugar";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 2 },
    });
    await seedTemplate("tpl-a", uid, { status: "archived" });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-a")
        .update({ status: "active" }),
    );
  });

  it("en el tope, restaurar rebota", async () => {
    const uid = "pf-restaura-sin-lugar";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    });
    await seedTemplate("tpl-b", uid, { status: "archived" });

    await assertFails(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-b")
        .update({ status: "active" }),
    );
  });

  it("archivar sigue sin mirar la cuota, aunque quede pasado de tope", async () => {
    const uid = "pf-archiva-sobre-tope";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 5 },
    });
    await seedTemplate("tpl-c", uid, { status: "active" });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-c")
        .update({ status: "archived" }),
    );
  });

  it("restaurar un trainer-assigned nunca mira la cuota", async () => {
    const uid = "pf-restaura-asignado";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    });
    await seedTemplate("tpl-e", uid, {
      source: "trainer-assigned",
      status: "archived",
      assignedTo: "athlete-1",
    });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-e")
        .update({ status: "active" }),
    );
  });

  it("límite null restaura sin límite", async () => {
    const uid = "pf-plan-pago-restaura";
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: null },
      templateUsage: { count: 999 },
    });
    await seedTemplate("tpl-f", uid, { status: "archived" });

    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-f")
        .update({ status: "active" }),
    );
  });
});

// ---------------------------------------------------------------------------
// 3. Pasado de tope: todo lo demás sigue andando (P5).
// ---------------------------------------------------------------------------
describe("pasado de tope — todo salvo crear y restaurar sigue andando", () => {
  const uid = "pf-pasado-de-tope";

  beforeEach(async () => {
    await seedUser(uid, {
      role: "trainer",
      planLimits: { templates: 3 },
      templateUsage: { count: 5 },
    });
    await seedTemplate("tpl-editable", uid, { status: "active" });
  });

  it("edita el contenido (path 4)", async () => {
    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-editable")
        .update({ name: "Full body v2" }),
    );
  });

  it("publica (path 5)", async () => {
    await assertSucceeds(
      asUser(uid)
        .collection(COL_ROUTINES)
        .doc("tpl-editable")
        .update({ visibility: "public" }),
    );
  });

  it("borra (DELETE)", async () => {
    await assertSucceeds(
      asUser(uid).collection(COL_ROUTINES).doc("tpl-editable").delete(),
    );
  });
});
