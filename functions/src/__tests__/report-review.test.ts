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

  it("sin pendientes, no inventa un mas viejo", async () => {
    const s = await moderationStatsHandler(db);
    expect(s.pending).toBe(0);
    expect(s.oldestPendingAt).toBeNull();
    expect(s.oldestPendingHours).toBeNull();
  });
});
