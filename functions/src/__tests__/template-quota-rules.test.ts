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

  it("un alumno crea su forjado como hasta hoy — la cuota no se le aplica", async () => {
    const uid = "alumno-forjado";
    await seedUser(uid, {
      role: "athlete",
      planLimits: { templates: 0 },
      templateUsage: { count: 999 },
    });

    await assertSucceeds(
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

  it("sin doc de perfil, la cuota no se aplica (falla abierta, como paywallEnforcedFor)", async () => {
    const uid = "pf-sin-doc-de-perfil";

    await assertSucceeds(
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
