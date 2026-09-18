/**
 * Cola de revision de reportes, contra el emulador de Firestore.
 *
 * Lo que se mide primero es el guard: los tres callables corren con Admin SDK
 * del otro lado, asi que `assertModerator` no es defensa en profundidad — es la
 * UNICA defensa. Si pasa, quien llame lee todos los reportes del producto.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  assertModerator,
  resolveContentPath,
  listPendingReportsHandler,
  moderationStatsHandler,
  resolveReportHandler,
  REVIEWS_COLLECTION,
} from "../moderation/report-review";

let app: App;
let db: Firestore;

beforeAll(() => {
  app = initializeApp({ projectId: "treino-dev" }, "report-review-tests");
  db = getFirestore(app);
});

afterAll(async () => {
  await deleteApp(app);
});

afterEach(async () => {
  for (const c of ["reports", REVIEWS_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const req = (token?: Record<string, unknown>) =>
  ({ auth: token ? { uid: "mod1", token } : null }) as
    unknown as CallableRequest<unknown>;

async function sembrarReporte(id: string, hace: number) {
  await db.collection("reports").doc(id).set({
    reporterUid: "r1",
    targetKind: "post",
    targetId: "p1",
    targetOwnerUid: "o1",
    reason: "harassment",
    detail: "me dijeron cosas",
    createdAt: new Date(Date.now() - hace),
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

  it("firstViewedAt se setea UNA vez y no se pisa", async () => {
    // Es lo que permite medir cuanto tardamos en MIRAR un reporte, que es la
    // promesa publicada. Si cada listado lo reescribiera, el numero mediria
    // "cuando fue el ultimo listado" y siempre daria bien.
    await sembrarReporte("r1", 3 * 3600_000);

    const primera = await listPendingReportsHandler(db);
    const t1 = primera.reports[0].firstViewedAt;

    await new Promise((r) => setTimeout(r, 25));
    const segunda = await listPendingReportsHandler(db);

    expect(segunda.reports[0].firstViewedAt).toBe(t1);
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

    await resolveReportHandler(db, "mod1", {
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
      resolveReportHandler(db, "mod1", {
        reportId: "no-existe", status: "dismissed", action: "none",
      }),
    ).rejects.toThrow(/no existe/);
  });

  it("rechaza status 'pending'", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, "mod1", {
        reportId: "r1", status: "pending", action: "none",
      }),
    ).rejects.toThrow(HttpsError);
  });

  it("rechaza una accion inventada", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, "mod1", {
        reportId: "r1", status: "actioned", action: "borrarTodo",
      }),
    ).rejects.toThrow(HttpsError);
  });

  it("rechaza una nota de mas de 1000", async () => {
    await sembrarReporte("r1", 3600_000);
    await expect(
      resolveReportHandler(db, "mod1", {
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

    await resolveReportHandler(db, "mod1", {
      reportId: "r1", status: "dismissed", action: "none",
    });

    const despues = (await db.collection("reports").doc("r1").get()).data();
    expect(despues).toEqual(antes);
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
