/**
 * `report_reviews` y `moderation_removals` estan cerradas a todo cliente — y
 * `reports` sigue intacta.
 *
 * La segunda mitad es el criterio de aceptacion del plan, escrito como test:
 * «`reports` sigue con `allow read: if false` y su `hasOnly` intacto. Si este
 * PR toca esas dos lineas, esta mal resuelto.»
 *
 * Un criterio de aceptacion que vive solo en la descripcion de un PR se cumple
 * el dia del merge y nadie lo vuelve a mirar. Acá se rompe solo si alguien lo
 * afloja.
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` o no corre en CI.
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

const PROJECT_ID = "treino-rules-test-report-reviews";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

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

afterAll(async () => { await testEnv.cleanup(); });
afterEach(async () => { await testEnv.clearFirestore(); });

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

describe("report_reviews", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("report_reviews/post_p1_r1").set({
        status: "actioned",
        action: "contentRemoved",
        reviewedBy: "mod1",
        resolvedAt: new Date(),
      });
    });
  });

  it("nadie puede leer una resolucion", async () => {
    await assertFails(asUser("r1").doc("report_reviews/post_p1_r1").get());
  });

  it("ni el denunciante que la origino", async () => {
    // El id del reporte termina en el uid del denunciante, asi que es "suyo"
    // en algun sentido. No alcanza: saber si su denuncia prospero le dice si
    // la persona que denuncio fue sancionada, que es informacion de un tercero.
    await assertFails(asUser("r1").doc("report_reviews/post_p1_r1").get());
  });

  it("nadie puede listar la coleccion", async () => {
    await assertFails(asUser("r1").collection("report_reviews").get());
  });

  it("nadie puede escribir una resolucion", async () => {
    // Si se pudiera, cualquiera cierra su propio reporte y lo saca de la cola.
    await assertFails(
      asUser("r1").doc("report_reviews/post_p1_r1").set({ status: "dismissed" }),
    );
  });
});

describe("moderation_removals", () => {
  // Marcador de "este contenido ya lo retiro la moderacion", indexado por
  // CONTENIDO (`{targetKind}__{targetId}`) y no por reporte. Es lo que
  // permite cerrar los duplicados de una misma denuncia.
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("moderation_removals/post__p1").set({
        targetKind: "post",
        targetId: "p1",
        path: "posts/p1",
        reportId: "post_p1_r1",
        moderatorUid: "mod1",
        derivedOwnerUid: "o1",
        removedMedia: false,
        at: new Date(),
      });
    });
  });

  it("nadie puede leer un marcador", async () => {
    // Leerlo diria exactamente que contenido se retiro y cual no: el mismo
    // canal de evasion que cierra `moderation_quarantine`.
    await assertFails(asUser("r1").doc("moderation_removals/post__p1").get());
  });

  it("ni el autor del contenido retirado", async () => {
    await assertFails(asUser("o1").doc("moderation_removals/post__p1").get());
  });

  it("nadie puede listar la coleccion", async () => {
    await assertFails(asUser("r1").collection("moderation_removals").get());
  });

  it("nadie puede escribir un marcador", async () => {
    // Si se pudiera, cualquiera sembraria un marcador sobre contenido vivo y
    // habilitaria a cerrarlo como "ya retirado" sin que se haya retirado.
    await assertFails(
      asUser("r1").doc("moderation_removals/post__p2").set({
        targetKind: "post", targetId: "p2", reportId: "x", at: new Date(),
      }),
    );
  });

  it("ni borrarlo", async () => {
    // Borrarlo devolveria los duplicados al callejon sin salida.
    await assertFails(
      asUser("mod1").doc("moderation_removals/post__p1").delete(),
    );
  });
});

describe("reports NO se toco (criterio de aceptacion)", () => {
  const reportId = "post_p1_r1";
  const cuerpo = {
    reporterUid: "r1",
    targetKind: "post",
    targetId: "p1",
    targetOwnerUid: "o1",
    reason: "harassment",
    detail: "texto",
    createdAt: new Date(),
  };

  it("sigue sin poder leerse", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`reports/${reportId}`).set(cuerpo);
    });
    await assertFails(asUser("r1").doc(`reports/${reportId}`).get());
  });

  it("el create canonico del cliente SIGUE funcionando", async () => {
    // CONTROL POSITIVO. Sin el, los `assertFails` de arriba pasarian igual si
    // las reglas de `reports` se hubieran roto del todo — y "nadie puede leer"
    // se leeria como exito cuando en realidad nadie puede NADA.
    await assertSucceeds(
      asUser("r1").doc(`reports/${reportId}`).set(cuerpo),
    );
  });

  it("su hasOnly sigue rechazando un campo de estado", async () => {
    // Esto es lo que obliga a la coleccion separada. Si algun dia pasa, alguien
    // aflojo el create y la cola puede volver a mutar `reports`.
    await assertFails(
      asUser("r1").doc(`reports/${reportId}`).set({
        ...cuerpo,
        status: "open",
      }),
    );
  });

  it("sigue sin poder actualizarse", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`reports/${reportId}`).set(cuerpo);
    });
    await assertFails(
      asUser("r1").doc(`reports/${reportId}`).update({ reason: "spam" }),
    );
  });
});
