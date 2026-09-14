/**
 * Tests de enforcement real de las rules de `reports/{reportId}`.
 *
 * Mismo criterio que `follows-rules.test.ts`: `@firebase/rules-unit-testing`
 * con `firestore.rules` REAL cargado y APLICADO, no el Admin SDK.
 * `withSecurityRulesDisabled` se usa SOLO para sembrar el estado previo;
 * toda aserción corre en un contexto de cliente autenticado.
 *
 * El foco es NEGATIVO. design.md ("reports — el id previene el doble
 * reporte"): el `read` está cerrado a TODO cliente — los reportes se revisan
 * por consola, y un denunciante que pudiera leer reportes (propios o ajenos)
 * es un canal de acoso nuevo. Por eso acá no hay ningún caso "el dueño lee
 * su propio doc": ese caso no existe para `reports`.
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` (package.json
 * `test:rules`) o no corre en CI.
 *
 * Correr contra el emulador:
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

const PROJECT_ID = "treino-rules-test-reports";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const AT = new Date("2026-09-11T12:00:00.000Z");

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

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

const reportId = (targetKind: string, targetId: string, reporterUid: string) =>
  `${targetKind}_${targetId}_${reporterUid}`;

/** Cuerpo canónico de un reporte — `detail` queda afuera a propósito (opcional). */
function reportBody(
  targetKind: string,
  targetId: string,
  targetOwnerUid: string,
  reporterUid: string,
  reason = "harassment",
) {
  return {
    reporterUid,
    targetKind,
    targetId,
    targetOwnerUid,
    reason,
    createdAt: AT,
  };
}

/** Siembra un reporte ya existente (rules deshabilitadas, solo setup). */
async function seedReport(
  targetKind: string,
  targetId: string,
  targetOwnerUid: string,
  reporterUid: string,
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection("reports")
      .doc(reportId(targetKind, targetId, reporterUid))
      .set(reportBody(targetKind, targetId, targetOwnerUid, reporterUid));
  });
}

// ── create ──────────────────────────────────────────────────────────────────
describe("reports — create", () => {
  it("el denunciante crea su propio reporte con id determinístico", async () => {
    await assertSucceeds(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set(reportBody("post", "p1", "bob", "alice")),
    );
  });

  // Caso obligatorio del design: nadie falsifica el reporterUid de otro.
  it("deniega falsificar el reporterUid de otro", async () => {
    await assertFails(
      asUser("mallory")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set(reportBody("post", "p1", "bob", "alice")),
    );
  });

  it("deniega si el id no coincide con targetKind_targetId_reporterUid", async () => {
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc("cualquier_cosa")
        .set(reportBody("post", "p1", "bob", "alice")),
    );
  });

  it("deniega un targetKind fuera de la taxonomía", async () => {
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc(reportId("comment", "p1", "alice"))
        .set(reportBody("comment", "p1", "bob", "alice")),
    );
  });

  it("acepta los cuatro targetKind válidos: post, message, review, profile", async () => {
    const kinds = ["post", "message", "review", "profile"];
    for (const kind of kinds) {
      await assertSucceeds(
        asUser("alice")
          .collection("reports")
          .doc(reportId(kind, `t-${kind}`, "alice"))
          .set(reportBody(kind, `t-${kind}`, "bob", "alice")),
      );
    }
  });

  it("deniega un reason fuera de la taxonomía", async () => {
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set(reportBody("post", "p1", "bob", "alice", "porqueSi")),
    );
  });

  it("acepta cada reason válido de la taxonomía", async () => {
    const reasons = [
      "harassment",
      "sexualContent",
      "violenceOrSelfHarm",
      "dangerousHealthAdvice",
      "impersonation",
      "spam",
      "thirdPartyData",
      "intellectualProperty",
      "other",
    ];
    for (const reason of reasons) {
      await assertSucceeds(
        asUser("alice")
          .collection("reports")
          .doc(reportId("post", `p-${reason}`, "alice"))
          .set(reportBody("post", `p-${reason}`, "bob", "alice", reason)),
      );
    }
  });

  it("deniega detail mayor a 1000 caracteres", async () => {
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set({
          ...reportBody("post", "p1", "bob", "alice"),
          detail: "x".repeat(1001),
        }),
    );
  });

  it("acepta detail de hasta 1000 caracteres", async () => {
    await assertSucceeds(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set({
          ...reportBody("post", "p1", "bob", "alice"),
          detail: "x".repeat(1000),
        }),
    );
  });

  it("deniega un campo fuera de la allowlist", async () => {
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set({
          ...reportBody("post", "p1", "bob", "alice"),
          moderatorNote: "revisado",
        }),
    );
  });

  it("deniega un reporte anónimo", async () => {
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .set(reportBody("post", "p1", "bob", "alice")),
    );
  });
});

// ── read / update / delete: cerrados a TODO cliente ─────────────────────────
describe("reports — read/update/delete cerrados a todo cliente", () => {
  // Caso obligatorio del design: NADIE lee reportes, ni el propio
  // denunciante. Los reportes se revisan por consola — un denunciante que
  // pudiera leer reportes (propios o ajenos) es un canal de acoso nuevo.
  it("NADIE lee reportes, ni el propio denunciante", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      asUser("alice").collection("reports").doc(reportId("post", "p1", "alice")).get(),
    );
  });

  it("un tercero tampoco lee un reporte ajeno", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      asUser("mallory")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .get(),
    );
  });

  // El propio denunciado (targetOwnerUid) tampoco: enterarse de quién lo
  // reportó y por qué sería el mismo canal de acoso, sólo que desde el otro
  // lado.
  it("el denunciado tampoco lee el reporte en su contra", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      asUser("bob").collection("reports").doc(reportId("post", "p1", "alice")).get(),
    );
  });

  it("un anónimo no lee nada", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .get(),
    );
  });

  it("ni el denunciante puede actualizar su propio reporte", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      asUser("alice")
        .collection("reports")
        .doc(reportId("post", "p1", "alice"))
        .update({ reason: "spam" }),
    );
  });

  it("ni el denunciante puede borrar su propio reporte", async () => {
    await seedReport("post", "p1", "bob", "alice");
    await assertFails(
      asUser("alice").collection("reports").doc(reportId("post", "p1", "alice")).delete(),
    );
  });
});
