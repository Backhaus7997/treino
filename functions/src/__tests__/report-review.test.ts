/**
 * Cola de revision de reportes, contra el emulador de Firestore.
 *
 * Lo que se mide primero es el guard: los tres callables corren con Admin SDK
 * del otro lado, asi que `assertModerator` no es defensa en profundidad — es la
 * UNICA defensa. Si pasa, quien llame lee todos los reportes del producto.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  assertModerator,
  markReportViewedHandler,
  resolveContentPath,
  listPendingReportsHandler,
  moderationStatsHandler,
  resolveReportHandler,
  REVIEWS_COLLECTION,
} from "../moderation/report-review";
import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";

let app: App;
let db: Firestore;

beforeAll(() => {
  app = initializeApp({ projectId: "treino-dev" }, "report-review-tests");
  db = getFirestore(app);
});

afterAll(async () => {
  await deleteApp(app);
});

// Rutas de Firestore y uids de Auth que un test individual crea fuera de
// "reports"/REVIEWS_COLLECTION (posts, reviews, mensajes, audit_log,
// mail_queue, usuarios). NO se barren esas colecciones enteras como las de
// arriba: las comparten otros archivos de test (mail-outbox.test.ts,
// notify-appointment.test.ts, audit-log.test.ts, etc.) corriendo contra el
// mismo proyecto, y un DELETE masivo ahi les borraria datos en el medio de
// una corrida completa de la suite.
let extraCleanupPaths: string[] = [];
let extraCleanupUids: string[] = [];

beforeEach(() => {
  extraCleanupPaths = [];
  extraCleanupUids = [];
});

afterEach(async () => {
  for (const c of ["reports", REVIEWS_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await Promise.all(
    extraCleanupPaths.map((p) => db.doc(p).delete().catch(() => undefined)),
  );
  await Promise.all(
    extraCleanupUids.map((u) =>
      getAuth(app).deleteUser(u).catch(() => undefined),
    ),
  );
});

const req = (token?: Record<string, unknown>) =>
  ({ auth: token ? { uid: "mod1", token } : null }) as
    unknown as CallableRequest<unknown>;

async function sembrarReporte(
  id: string,
  hace: number,
  overrides: Partial<{
    targetKind: string;
    targetId: string;
    targetOwnerUid: string;
    reporterUid: string;
    reason: string;
    detail: string;
  }> = {},
) {
  await db.collection("reports").doc(id).set({
    reporterUid: "r1",
    targetKind: "post",
    targetId: "p1",
    targetOwnerUid: "o1",
    reason: "harassment",
    detail: "me dijeron cosas",
    createdAt: new Date(Date.now() - hace),
    ...overrides,
  });
}

describe("assertModerator", () => {
  it("sin auth, permission-denied", () => {
    expect(() => assertModerator(req())).toThrow(HttpsError);
  });

  it("autenticado pero SIN el claim, permission-denied", () => {
    // El caso que importa: cualquier usuario logueado de la app.
    expect(() => assertModerator(req({ sub: "mod1" }))).toThrow(
      /No autorizado/,
    );
  });

  it("el claim en false no alcanza", () => {
    expect(() => assertModerator(req({ moderator: false }))).toThrow(HttpsError);
  });

  it("el claim como string 'true' NO alcanza", () => {
    // La comparacion es `!== true` estricta. Un claim seteado como cadena por
    // un script mal escrito no puede colarse.
    expect(() => assertModerator(req({ moderator: "true" }))).toThrow(
      HttpsError,
    );
  });

  it("con el claim, devuelve el uid", () => {
    expect(assertModerator(req({ moderator: true }))).toBe("mod1");
  });
});

describe("listPendingReports", () => {
  it("devuelve los pendientes, mas viejos primero", async () => {
    // Mas viejos primero porque la promesa es un TECHO de 24 horas: lo que hay
    // que atacar es lo que esta mas cerca de romperla.
    await sembrarReporte("viejo", 40 * 3600_000);
    await sembrarReporte("nuevo", 1 * 3600_000);

    const { reports } = await listPendingReportsHandler(db);

    expect(reports.map((r) => r.id)).toEqual(["viejo", "nuevo"]);
  });

  it("no devuelve los ya resueltos", async () => {
    await sembrarReporte("resuelto", 5 * 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("resuelto").set({
      status: "dismissed",
    });

    const { reports } = await listPendingReportsHandler(db);
    expect(reports).toHaveLength(0);
  });

  it("LISTAR NO ES MIRAR: el listado no estampa firstViewedAt", async () => {
    // La version anterior lo estampaba aca, y eso rompia la unica metrica que
    // prueba la promesa publicada: abrir la pantalla una vez marcaba los 50
    // reportes de la pagina como revisados —incluidos los que el ListView
    // perezoso ni renderiza— y `moderationStats` los contaba dentro del plazo
    // PARA SIEMPRE.
    //
    // Una metrica que se satisface abriendo una pantalla no mide nada.
    await sembrarReporte("r1", 3 * 3600_000);

    const res = await listPendingReportsHandler(db);

    expect(res.reports[0].firstViewedAt).toBeNull();
    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.get("firstViewedAt")).toBeUndefined();
  });
});

describe("listPendingReports — hallazgos de la revision", () => {
  it("NO devuelve vacio cuando los mas viejos ya estan resueltos", async () => {
    // El bug: la consulta pedia los `limit` mas viejos y filtraba los
    // resueltos DESPUES. El dia que los 50 mas viejos estuvieran resueltos,
    // la cola devolvia vacio para siempre con pendientes mas nuevos
    // esperando.
    //
    // Una cola que se vacia sola es peor que no tener cola: no dice "no hay
    // nada", lo dice MINTIENDO, y nadie vuelve a mirar.
    for (let i = 0; i < 55; i++) {
      await sembrarReporte(`viejo${i}`, (100 - i) * 3600_000);
      await db.collection(REVIEWS_COLLECTION).doc(`viejo${i}`).set({
        status: "dismissed",
      });
    }
    await sembrarReporte("elQueImporta", 2 * 3600_000);

    const { reports } = await listPendingReportsHandler(db);

    expect(reports.map((r) => r.id)).toEqual(["elQueImporta"]);
  });

  it("un listado NO reabre un reporte ya resuelto", async () => {
    // La estampa de `firstViewedAt` era un `set` con merge sobre una lectura
    // previa. Si otro moderador resolvia el reporte en el medio, el merge
    // escribia `status: "pending"` encima del estado resuelto —conservando
    // `resolvedAt`, que quedaba mintiendo— y el reporte reaparecia.
    await sembrarReporte("r1", 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("r1").set({
      status: "actioned",
      action: "contentRemoved",
      reviewedBy: "mod1",
      resolvedAt: new Date(),
    });

    await listPendingReportsHandler(db);

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.get("status")).toBe("actioned");
  });

  it("devuelve donde vive el contenido reportado", async () => {
    await sembrarReporte("r1", 3600_000);
    const { reports } = await listPendingReportsHandler(db);
    expect(reports[0].contentPath).toBe("posts/p1");
  });
});

describe("markReportViewed", () => {
  it("estampa firstViewedAt", async () => {
    await sembrarReporte("r1", 3600_000);

    const res = await markReportViewedHandler(db, "r1");

    expect(res.firstViewedAt).not.toBeNull();
    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.get("firstViewedAt")).toBeTruthy();
    expect(rev.get("status")).toBe("pending");
  });

  it("la segunda vez NO lo pisa", async () => {
    // Si cada render lo reescribiera, el numero mediria "cuando fue la
    // ultima vez que alguien abrio la pantalla" y siempre daria bien.
    await sembrarReporte("r1", 3600_000);

    const primera = await markReportViewedHandler(db, "r1");
    await new Promise((r) => setTimeout(r, 25));
    const segunda = await markReportViewedHandler(db, "r1");

    expect(segunda.firstViewedAt).toBe(primera.firstViewedAt);
  });

  it("NO reabre un reporte ya resuelto", async () => {
    // Marcar algo como visto no puede sacarlo del estado resuelto.
    await sembrarReporte("r1", 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("r1").set({
      status: "actioned",
      action: "contentRemoved",
      reviewedBy: "mod1",
      resolvedAt: new Date(),
    });

    await markReportViewedHandler(db, "r1");

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.get("status")).toBe("actioned");
  });

  it("rechaza un reportId vacio", async () => {
    await expect(markReportViewedHandler(db, "")).rejects.toThrow(HttpsError);
    await expect(markReportViewedHandler(db, null)).rejects
      .toThrow(HttpsError);
  });
});

describe("resolveContentPath", () => {
  it("el mensaje deriva su chat del par de uids", () => {
    // El cliente manda `message.id` pelado y el documento vive en
    // `chats/{chatId}/messages/{messageId}`. Un id sin su chat no localiza
    // nada — y la cola se presenta como el lugar donde se mira el contenido.
    //
    // El chatId no hace falta pedirlo: es deterministico (par ordenado unido
    // con `_`) y el reporte ya trae las dos puntas.
    expect(
      resolveContentPath({
        targetKind: "message",
        targetId: "m1",
        reporterUid: "zzz",
        targetOwnerUid: "aaa",
      }),
    ).toBe("chats/aaa_zzz/messages/m1");
  });

  it("el orden de los uids no cambia la ruta", () => {
    const a = resolveContentPath({
      targetKind: "message", targetId: "m1",
      reporterUid: "aaa", targetOwnerUid: "zzz",
    });
    const b = resolveContentPath({
      targetKind: "message", targetId: "m1",
      reporterUid: "zzz", targetOwnerUid: "aaa",
    });
    expect(a).toBe(b);
  });

  it("post, review y profile", () => {
    const base = { targetId: "x1", reporterUid: "r", targetOwnerUid: "o" };
    expect(resolveContentPath({ ...base, targetKind: "post" }))
      .toBe("posts/x1");
    expect(resolveContentPath({ ...base, targetKind: "review" }))
      .toBe("reviews/x1");
    expect(resolveContentPath({ ...base, targetKind: "profile" }))
      .toBe("users/x1");
  });

  it("un targetKind desconocido devuelve null, no una ruta inventada", () => {
    // Una ruta que no existe se lee igual que una que si, y manda al
    // moderador a buscar un documento que nunca estuvo ahi.
    expect(
      resolveContentPath({
        targetKind: "loQueSea", targetId: "x1",
        reporterUid: "r", targetOwnerUid: "o",
      }),
    ).toBeNull();
  });
});

describe("resolveReport", () => {
  it("escribe el resultado en report_reviews", async () => {
    await sembrarReporte("r1", 3600_000);
    // `contentRemoved` ahora EJECUTA de verdad, asi que el post tiene que
    // existir — antes de este cambio la etiqueta se escribia igual sin
    // tocar nada, y este fixture no lo necesitaba.
    await db.collection("posts").doc("p1").set({ text: "post a retirar" });
    extraCleanupPaths.push("posts/p1");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
      note: "post borrado",
    });

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.get("status")).toBe("actioned");
    expect(rev.get("action")).toBe("contentRemoved");
    expect(rev.get("reviewedBy")).toBe("mod1");
    expect(rev.get("resolvedAt")).toBeTruthy();
  });

  it("NO deja resolver un reporte que no existe", async () => {
    // Sin esto, report_reviews se llena de resoluciones de reportes
    // inexistentes —un id mal tipeado, un cliente viejo— y la cola miente
    // sobre cuanto se resolvio.
    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "no-existe", status: "dismissed", action: "none",
      }),
    ).rejects.toThrow(/no existe/);
  });

  it("rechaza status 'pending'", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "pending", action: "none",
      }),
    ).rejects.toThrow(HttpsError);
  });

  it("rechaza una accion inventada", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "borrarTodo",
      }),
    ).rejects.toThrow(HttpsError);
  });

  it("rechaza una nota de mas de 1000", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "dismissed", action: "none",
        note: "x".repeat(1001),
      }),
    ).rejects.toThrow(HttpsError);
  });

  it("NO toca el documento de reports", async () => {
    // `reports` es append-only e inmutable. Si este test se cae, el PR esta
    // mal resuelto: el punto entero de la coleccion separada es no mutarla.
    await sembrarReporte("r1", 3600_000);
    const antes = (await db.collection("reports").doc("r1").get()).data();

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "dismissed", action: "none",
    });

    const despues = (await db.collection("reports").doc("r1").get()).data();
    expect(despues).toEqual(antes);
  });
});

describe("resolveReport — ejecuta la accion de verdad", () => {
  // Hasta este cambio, `resolveReport` escribia solo la ETIQUETA y ninguna
  // accion se ejecutaba: el boton "Contenido retirado" no retiraba nada. Este
  // bloque prueba la EJECUCION, no la etiqueta — cada test lee el efecto
  // directo (Firestore, Auth, mail_queue), nunca el valor de retorno.

  describe("contentRemoved", () => {
    it("en un post deja el campo text vacio EN FIRESTORE", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-cr-1", targetOwnerUid: "owner-cr-1",
      });
      await db.collection("posts").doc("post-cr-1").set({
        text: "contenido original del post", authorUid: "owner-cr-1",
      });
      extraCleanupPaths.push("posts/post-cr-1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      });

      const post = await db.collection("posts").doc("post-cr-1").get();
      expect(post.get("text")).toBe("");
    });

    it("en una review deja el campo comment vacio EN FIRESTORE", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "review", targetId: "review-cr-1",
        targetOwnerUid: "owner-cr-2",
      });
      await db.collection("reviews").doc("review-cr-1").set({
        comment: "comentario original de la review",
      });
      extraCleanupPaths.push("reviews/review-cr-1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      });

      const review = await db.collection("reviews").doc("review-cr-1").get();
      expect(review.get("comment")).toBe("");
    });

    it("en un mensaje deja el texto vacio, con el chatId derivado del par de uids", async () => {
      const reporterUid = "rep-msg-cr-1";
      const targetOwnerUid = "owner-msg-cr-1";
      const chatId = [reporterUid, targetOwnerUid].sort().join("_");
      const msgPath = `chats/${chatId}/messages/msg-cr-1`;

      await sembrarReporte("r1", 3600_000, {
        targetKind: "message", targetId: "msg-cr-1", reporterUid, targetOwnerUid,
      });
      await db.doc(msgPath).set({
        text: "mensaje original", senderId: targetOwnerUid,
      });
      extraCleanupPaths.push(msgPath);

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      });

      const msg = await db.doc(msgPath).get();
      expect(msg.get("text")).toBe("");
    });

    it("sobre un perfil tira invalid-argument y NO toca el documento del usuario", async () => {
      const targetOwnerUid = "owner-profile-cr-1";
      await sembrarReporte("r1", 3600_000, {
        targetKind: "profile", targetId: targetOwnerUid, targetOwnerUid,
      });
      await db.collection("users").doc(targetOwnerUid).set({
        displayName: "Nombre Original",
      });
      extraCleanupPaths.push(`users/${targetOwnerUid}`);

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "contentRemoved",
        }),
      ).rejects.toThrow(/perfil/);

      const user = await db.collection("users").doc(targetOwnerUid).get();
      expect(user.get("displayName")).toBe("Nombre Original");
    });

    it("sobre contenido inexistente tira, y report_reviews NO queda marcado resuelto", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-no-existe-cr-1",
        targetOwnerUid: "owner-cr-3",
      });
      // A proposito: nunca se crea posts/post-no-existe-cr-1.

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "contentRemoved",
        }),
      ).rejects.toThrow(HttpsError);

      const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
      expect(rev.exists).toBe(false);
    });
  });

  describe("userSuspended", () => {
    it("deja al usuario disabled:true en Firebase Auth", async () => {
      const targetOwnerUid = "user-to-suspend-1";
      await getAuth(app).createUser({
        uid: targetOwnerUid, email: `${targetOwnerUid}@test.com`,
      });
      extraCleanupUids.push(targetOwnerUid);
      await sembrarReporte("r1", 3600_000, { targetKind: "post", targetOwnerUid });

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "userSuspended",
      });

      const user = await getAuth(app).getUser(targetOwnerUid);
      expect(user.disabled).toBe(true);
    });

    it("sobre uno mismo tira invalid-argument", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetOwnerUid: "mod1",
      });

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "userSuspended",
        }),
      ).rejects.toThrow(HttpsError);
    });

    it("sobre otro moderador tira permission-denied y no lo deshabilita", async () => {
      const otroModeradorUid = "mod2-target";
      await getAuth(app).createUser({
        uid: otroModeradorUid, email: `${otroModeradorUid}@test.com`,
      });
      await getAuth(app).setCustomUserClaims(otroModeradorUid, { moderator: true });
      extraCleanupUids.push(otroModeradorUid);
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetOwnerUid: otroModeradorUid,
      });

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "userSuspended",
        }),
      ).rejects.toThrow(HttpsError);

      const user = await getAuth(app).getUser(otroModeradorUid);
      expect(user.disabled).toBe(false);
    });
  });

  describe("userWarned", () => {
    it("encola un mail sin el contenido reportado ni nada que identifique al denunciante", async () => {
      const reporterUid = "denunciante-secreto-1";
      const targetOwnerUid = "advertido-1";
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-warn-1", reporterUid, targetOwnerUid,
        reason: "harassment", detail: "texto MUY identificable que escribio el denunciante",
      });
      await db.collection("posts").doc("post-warn-1").set({
        text: "contenido reportado sensible", authorUid: targetOwnerUid,
      });
      extraCleanupPaths.push("posts/post-warn-1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "userWarned",
      });

      const id = dedupeKey("moderation-user-warned", "r1", targetOwnerUid);
      extraCleanupPaths.push(`${MAIL_QUEUE_COLLECTION}/${id}`);
      const mail = await db.collection(MAIL_QUEUE_COLLECTION).doc(id).get();
      expect(mail.exists).toBe(true);
      expect(mail.get("toUid")).toBe(targetOwnerUid);

      // El documento COMPLETO, no solo `params`: si algun dia alguien mete el
      // dato sensible en otra clave del doc, esto lo agarra igual.
      const crudo = JSON.stringify(mail.data());
      expect(crudo).not.toContain(reporterUid);
      expect(crudo).not.toContain("texto MUY identificable");
      expect(crudo).not.toContain("contenido reportado sensible");
    });
  });

  describe("audit_log", () => {
    it("moderation__{reportId} guarda el contenido original y quien resolvio", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-audit-1", targetOwnerUid: "owner-audit-1",
      });
      await db.collection("posts").doc("post-audit-1").set({
        text: "el original que hace falta para poder apelar",
      });
      extraCleanupPaths.push("posts/post-audit-1", "audit_log/moderation__r1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      });

      const audit = await db.collection("audit_log").doc("moderation__r1").get();
      expect(audit.exists).toBe(true);
      expect(audit.get("kind")).toBe("moderation");
      expect(audit.get("action")).toBe("contentRemoved");
      expect(audit.get("moderatorUid")).toBe("mod1");
      expect(audit.get("removedContent")).toBe(
        "el original que hace falta para poder apelar",
      );
    });

    it("dismissed/none NO escribe audit_log y NO toca ningun contenido", async () => {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-dismiss-1", targetOwnerUid: "owner-dismiss-1",
      });
      await db.collection("posts").doc("post-dismiss-1").set({
        text: "esto no se toca",
      });
      extraCleanupPaths.push("posts/post-dismiss-1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "dismissed", action: "none",
      });

      const audit = await db.collection("audit_log").doc("moderation__r1").get();
      expect(audit.exists).toBe(false);

      const post = await db.collection("posts").doc("post-dismiss-1").get();
      expect(post.get("text")).toBe("esto no se toca");
    });
  });
});

describe("moderationStats", () => {
  it("cuenta pendientes, el mas viejo, y los que rompen las 24 horas", async () => {
    // Es lo que permite PROBAR que se cumple la promesa en vez de afirmarla.
    await sembrarReporte("viejo", 40 * 3600_000);
    await sembrarReporte("nuevo", 2 * 3600_000);
    await sembrarReporte("cerrado", 100 * 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("cerrado").set({
      status: "actioned",
    });

    const s = await moderationStatsHandler(db);

    expect(s.pending).toBe(2);
    expect(s.breachingSla).toBe(1);
    expect(s.oldestPendingHours).toBeGreaterThanOrEqual(39);
  });

  it("mirado en tiempo y todavia abierto NO es incumplimiento", async () => {
    // Lo que se promete es REVISAR dentro de las 24 horas, no resolver. La
    // version anterior contaba todo pendiente viejo, mirado o no: un reporte
    // atendido a las dos horas que sigue abierto —porque resolverlo requiere
    // decidir algo— aparecia como promesa rota, y el numero dejaba de poder
    // probar nada.
    await sembrarReporte("r1", 100 * 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("r1").set({
      status: "pending",
      // Mirado una hora despues de creado: bien adentro del plazo.
      firstViewedAt: new Date(Date.now() - 99 * 3600_000),
    });

    const s = await moderationStatsHandler(db);

    expect(s.pending).toBe(1);
    expect(s.breachingSla).toBe(0);
  });

  it("mirado TARDE sigue contando como incumplimiento", async () => {
    // Mirarlo despues no deshace el incumplimiento.
    await sembrarReporte("r1", 100 * 3600_000);
    await db.collection(REVIEWS_COLLECTION).doc("r1").set({
      status: "pending",
      firstViewedAt: new Date(Date.now() - 10 * 3600_000),
    });

    const s = await moderationStatsHandler(db);
    expect(s.breachingSla).toBe(1);
  });

  it("nunca mirado y todavia en plazo tampoco es incumplimiento", async () => {
    await sembrarReporte("r1", 2 * 3600_000);
    const s = await moderationStatsHandler(db);
    expect(s.pending).toBe(1);
    expect(s.breachingSla).toBe(0);
  });

  it("sin pendientes, no inventa un mas viejo", async () => {
    const s = await moderationStatsHandler(db);
    expect(s.pending).toBe(0);
    expect(s.oldestPendingAt).toBeNull();
    expect(s.oldestPendingHours).toBeNull();
  });
});
