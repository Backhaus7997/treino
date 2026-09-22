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
  extractStoragePath,
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

/**
 * Envuelve `db` para que la escritura de `audit_log` (el PASO 2 de
 * `resolveReportHandler`) dispare, justo antes de completarse, una edicion
 * REAL sobre otro documento — el autor editando su propio contenido en la
 * misma ventana que describe el commit 00472767.
 *
 * No es un mock de Firestore: el UNICO punto que se intercepta es el
 * `.set()` de `audit_log`, y lo que hace antes de dejarlo pasar es una
 * escritura de verdad contra el emulador (`interferir`). Todo lo demas
 * (`.doc()`, y `.collection()` para cualquier otro nombre) va directo al
 * `db` real, sin envolver nada — por eso el `lastUpdateTime` que el PASO 1
 * ya capturo queda viejo DE VERDAD, y la precondicion del PASO 3 falla por
 * su cuenta, no porque el test la haya forzado.
 */
function dbConCarrera(
  real: Firestore,
  interferir: () => Promise<unknown>,
): Firestore {
  const wrapped = {
    doc: (path: string) => real.doc(path),
    collection: (name: string) => {
      if (name !== "audit_log") return real.collection(name);
      return {
        doc: (id: string) => ({
          set: async (data: FirebaseFirestore.DocumentData) => {
            await interferir();
            return real.collection("audit_log").doc(id).set(data);
          },
        }),
      };
    },
    // PASO 0 de resolveReportHandler reclama el reporte con una transaccion
    // ANTES de llegar a nada de lo de arriba. Sin este passthrough, este
    // wrapper (que no implementaba runTransaction) rompe con "is not a
    // function" antes de que la carrera que este helper simula llegue a
    // importar.
    runTransaction: <T>(fn: (tx: FirebaseFirestore.Transaction) => Promise<T>) =>
      real.runTransaction(fn),
  };
  return wrapped as unknown as Firestore;
}

/**
 * Envuelve `db` para que la escritura a `mail_queue` (PASO 3 de
 * `resolveReportHandler`, accion `userWarned`) tire un error REAL en vez de
 * escribir — simula, por ejemplo, que Firestore rechaza el `.create()`.
 *
 * Mismo truco que `dbConCarrera`: solo se intercepta esa coleccion puntual,
 * todo lo demas (incluida `runTransaction`, que PASO 0 necesita) va al `db`
 * real sin envolver nada.
 *
 * El codigo del error es 14 (UNAVAILABLE), a proposito distinto de
 * ALREADY_EXISTS (6): si fuera 6, `enqueueWarningMailOrThrow` lo tragaria
 * como dedupe esperado, que es precisamente el caso que este test NO quiere
 * simular.
 */
function dbConEscrituraDeMailQueFalla(real: Firestore): Firestore {
  const wrapped = {
    doc: (path: string) => real.doc(path),
    collection: (name: string) => {
      if (name !== MAIL_QUEUE_COLLECTION) return real.collection(name);
      return {
        doc: () => ({
          create: async () => {
            const err = new Error("simulated Firestore write failure") as
              Error & { code?: number };
            err.code = 14;
            throw err;
          },
        }),
      };
    },
    runTransaction: <T>(fn: (tx: FirebaseFirestore.Transaction) => Promise<T>) =>
      real.runTransaction(fn),
  };
  return wrapped as unknown as Firestore;
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

    it("si el autor edita entre leer y redactar, tira aborted, NO redacta y el reporte sigue en la cola", async () => {
      // Commit 00472767: entre el PASO 1 (lee el contenido para
      // audit_log) y el PASO 3 (lo redacta) no habia precondicion, y el
      // autor puede editar lo suyo mientras tanto (firestore.rules:4366
      // deja actualizar una resena). Este test fuerza esa ventana de
      // verdad, sin mockear Firestore ni forzar el codigo 9 a mano.
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-race-1",
        targetOwnerUid: "owner-race-1",
      });
      await db.collection("posts").doc("post-race-1").set({
        text: "texto que el moderador miro",
      });
      extraCleanupPaths.push("posts/post-race-1", "audit_log/moderation__r1");

      const conCarrera = dbConCarrera(db, async () => {
        // El autor edita SU contenido justo en la ventana entre el PASO 1
        // (que ya leyo "texto que el moderador miro") y el PASO 3 (que
        // todavia no corrio). Escritura real contra el emulador, no un
        // efecto simulado.
        await db.collection("posts").doc("post-race-1").update({
          text: "texto nuevo que escribio el autor",
        });
      });

      let error: unknown;
      try {
        await resolveReportHandler(conCarrera, app, "mod1", {
          reportId: "r1", status: "actioned", action: "contentRemoved",
        });
      } catch (e) {
        error = e;
      }

      // 1. tira aborted.
      expect(error).toBeInstanceOf(HttpsError);
      expect((error as HttpsError).code).toBe("aborted");
      expect((error as HttpsError).message).toMatch(/cambio mientras lo revisabas/);

      // 2. el contenido NO quedo redactado — conserva el texto NUEVO, el
      // que escribio el autor durante la carrera.
      const post = await db.collection("posts").doc("post-race-1").get();
      expect(post.get("text")).toBe("texto nuevo que escribio el autor");

      // 3. report_reviews NO quedo marcado resuelto — el reporte sigue en
      // la cola. Es la diferencia entre "fallo" y "fallo mintiendo".
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
      // El autor tiene que derivarse del CONTENIDO (P1-A): sin este post,
      // deriveContentOwnerUid no encuentra nada que leer y userSuspended
      // tira failed-precondition en vez de suspender a nadie.
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-suspend-1", targetOwnerUid,
      });
      await db.collection("posts").doc("post-suspend-1").set({
        text: "x", authorUid: targetOwnerUid,
      });
      extraCleanupPaths.push("posts/post-suspend-1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "userSuspended",
      });

      const user = await getAuth(app).getUser(targetOwnerUid);
      expect(user.disabled).toBe(true);
    });

    it("sobre uno mismo tira invalid-argument", async () => {
      // El autor derivado del contenido (post-self-1.authorUid) tiene que
      // SER "mod1" para que este test ejercite el guard de autosuspension
      // — no el guard de "no se pudo derivar el autor", que tambien tira
      // HttpsError y taparia lo que este test dice probar.
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-self-1", targetOwnerUid: "mod1",
      });
      await db.collection("posts").doc("post-self-1").set({
        text: "x", authorUid: "mod1",
      });
      extraCleanupPaths.push("posts/post-self-1");

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "userSuspended",
        }),
      ).rejects.toThrow(/no te podes dar de baja a vos mismo/i);
    });

    it("sobre otro moderador tira permission-denied y no lo deshabilita", async () => {
      const otroModeradorUid = "mod2-target";
      await getAuth(app).createUser({
        uid: otroModeradorUid, email: `${otroModeradorUid}@test.com`,
      });
      await getAuth(app).setCustomUserClaims(otroModeradorUid, { moderator: true });
      extraCleanupUids.push(otroModeradorUid);
      // Idem: el autor derivado tiene que ser el otro moderador, para que
      // el guard que se ejercite sea el de "no podes dar de baja a otro
      // moderador" y no el de derivacion fallida.
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-othermod-1",
        targetOwnerUid: otroModeradorUid,
      });
      await db.collection("posts").doc("post-othermod-1").set({
        text: "x", authorUid: otroModeradorUid,
      });
      extraCleanupPaths.push("posts/post-othermod-1");

      await expect(
        resolveReportHandler(db, app, "mod1", {
          reportId: "r1", status: "actioned", action: "userSuspended",
        }),
      ).rejects.toThrow(/no podes dar de baja a otro moderador/i);

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

describe("resolveReport — P1-A: el dueno se deriva del contenido, no del reporte", () => {
  it("userSuspended deshabilita al AUTOR REAL, no al targetOwnerUid declarado, y el audit_log guarda los dos uids", async () => {
    // El ataque: alguien reporta un post GENUINAMENTE reportable de
    // `autorReal`, pero escribe el uid de `uidMentido` como
    // targetOwnerUid. firestore.rules:4622-4623 solo exige que sea un
    // string no vacio — nunca lo ata al autor real. El moderador ve
    // contenido que si viola las normas y aprieta "Dar de baja": sin este
    // fix, eso deshabilitaria a la persona equivocada.
    const autorReal = "autor-real-1";
    const uidMentido = "pedro-mentido-1";
    await getAuth(app).createUser({
      uid: autorReal, email: `${autorReal}@test.com`,
    });
    await getAuth(app).createUser({
      uid: uidMentido, email: `${uidMentido}@test.com`,
    });
    extraCleanupUids.push(autorReal, uidMentido);

    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-p1a-1", targetOwnerUid: uidMentido,
    });
    await db.collection("posts").doc("post-p1a-1").set({
      text: "post genuinamente reportable", authorUid: autorReal,
    });
    extraCleanupPaths.push("posts/post-p1a-1", "audit_log/moderation__r1");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "userSuspended",
    });

    const real = await getAuth(app).getUser(autorReal);
    expect(real.disabled).toBe(true);

    // La persona que el denunciante trato de incriminar NUNCA se toca.
    const pedro = await getAuth(app).getUser(uidMentido);
    expect(pedro.disabled).toBe(false);

    // La evidencia del intento queda en el audit_log: los DOS uids.
    const audit = await db.collection("audit_log").doc("moderation__r1").get();
    expect(audit.get("targetOwnerUid")).toBe(uidMentido);
    expect(audit.get("derivedOwnerUid")).toBe(autorReal);
  });

  it("contenido inexistente + userSuspended: tira failed-precondition, nunca dar de baja a partir de un uid no verificable", async () => {
    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-no-existe-p1a",
      targetOwnerUid: "cualquiera-p1a",
    });
    // A proposito: nunca se crea posts/post-no-existe-p1a, asi que no hay
    // de donde derivar el autor.

    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "userSuspended",
      }),
    ).rejects.toThrow(/no se pudo verificar el autor/i);

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.exists).toBe(false);
  });
});

describe("resolveReport — P1-B: contentRemoved tambien limpia la media", () => {
  it("mensaje de SOLO imagen (text vacio, media presente): contentRemoved limpia mediaUrl y el audit_log guarda la URL original", async () => {
    const reporterUid = "rep-msg-p1b-1";
    const targetOwnerUid = "owner-msg-p1b-1";
    const chatId = [reporterUid, targetOwnerUid].sort().join("_");
    const msgPath = `chats/${chatId}/messages/msg-p1b-1`;
    const originalUrl =
      "https://firebasestorage.googleapis.com/v0/b/x/o/chatMedia%2F" +
      `${chatId}%2F${targetOwnerUid}%2Fmsg-p1b-1.jpg?alt=media&token=abc123`;

    await sembrarReporte("r1", 3600_000, {
      targetKind: "message", targetId: "msg-p1b-1", reporterUid, targetOwnerUid,
    });
    // A proposito SIN `text` (o vacio): un mensaje de solo imagen. Antes de
    // este fix, "Contenido retirado" tenia exito sin tocar `mediaUrl`.
    await db.doc(msgPath).set({
      mediaUrl: originalUrl, mediaType: "image", senderId: targetOwnerUid,
    });
    extraCleanupPaths.push(msgPath, "audit_log/moderation__r1");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    const msg = await db.doc(msgPath).get();
    expect(msg.get("mediaUrl")).toBe("");

    const audit = await db.collection("audit_log").doc("moderation__r1").get();
    expect(audit.get("removedMediaUrl")).toBe(originalUrl);
  });

  it("sin texto ni media: contentRemoved tira en vez de tener exito silencioso", async () => {
    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-vacio-p1b-1",
      targetOwnerUid: "owner-vacio-p1b-1",
    });
    await db.collection("posts").doc("post-vacio-p1b-1").set({
      text: "", authorUid: "owner-vacio-p1b-1",
    });
    extraCleanupPaths.push("posts/post-vacio-p1b-1");

    await expect(
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      }),
    ).rejects.toThrow(/ni contenido multimedia/i);

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.exists).toBe(false);
  });
});

describe("resolveReport — P1-C: un fallo real al encolar el aviso aborta la resolucion", () => {
  it("si falla la escritura a mail_queue, la resolucion aborta y report_reviews NO queda resuelto", async () => {
    const targetOwnerUid = "advertido-p1c-1";
    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-p1c-1", targetOwnerUid,
    });
    await db.collection("posts").doc("post-p1c-1").set({
      text: "contenido", authorUid: targetOwnerUid,
    });
    extraCleanupPaths.push("posts/post-p1c-1", "audit_log/moderation__r1");

    const conFalloDeEscritura = dbConEscrituraDeMailQueFalla(db);

    await expect(
      resolveReportHandler(conFalloDeEscritura, app, "mod1", {
        reportId: "r1", status: "actioned", action: "userWarned",
      }),
    ).rejects.toThrow();

    // El reporte sigue sin resolver — no quedo marcado con el aviso
    // perdido para siempre.
    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    expect(rev.exists).toBe(false);

    // Y nada quedo encolado (la escritura fallo de verdad, no es dedupe).
    const id = dedupeKey("moderation-user-warned", "r1", targetOwnerUid);
    const mail = await db.collection(MAIL_QUEUE_COLLECTION).doc(id).get();
    expect(mail.exists).toBe(false);
  });
});

describe("resolveReport — P1-D: no se puede resolver el mismo reporte dos veces", () => {
  it("la segunda resolucion tira failed-precondition, y el audit_log conserva el removedContent ORIGINAL", async () => {
    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-double-1",
      targetOwnerUid: "owner-double-1",
    });
    await db.collection("posts").doc("post-double-1").set({
      text: "contenido original", authorUid: "owner-double-1",
    });
    extraCleanupPaths.push("posts/post-double-1", "audit_log/moderation__r1");

    // Moderador 1: resuelve contentRemoved. El texto queda vacio y el
    // audit_log guarda el original.
    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    // Moderador 2, con la cola vieja: intenta resolver el MISMO reporte de
    // nuevo. Sin el guard de PASO 0, esto leeria posts/post-double-1.text
    // YA VACIO (por la resolucion de mod1) y lo pisaria igual —"tenia
    // exito" sobre contenido que ya no existe como tal— y el audit_log
    // determinístico quedaria con removedContent: "".
    await expect(
      resolveReportHandler(db, app, "mod2", {
        reportId: "r1", status: "dismissed", action: "none",
      }),
    ).rejects.toThrow(/ya resolvio este reporte/i);

    // El texto sigue vacio (de la PRIMERA resolucion, no de una segunda).
    const post = await db.collection("posts").doc("post-double-1").get();
    expect(post.get("text")).toBe("");

    // Y la evidencia original sigue intacta: la escribio mod1, no mod2.
    const audit = await db.collection("audit_log").doc("moderation__r1").get();
    expect(audit.get("removedContent")).toBe("contenido original");
    expect(audit.get("moderatorUid")).toBe("mod1");
  });
});

describe("extractStoragePath", () => {
  it("deriva el path del objeto de una URL de descarga de Firebase Storage", () => {
    expect(
      extractStoragePath(
        "https://firebasestorage.googleapis.com/v0/b/x/o/" +
        "postPhotos%2Fuid1%2Fpost1.jpg?alt=media&token=abc",
      ),
    ).toBe("postPhotos/uid1/post1.jpg");
  });

  it("devuelve null para una URL que no es de Firebase Storage", () => {
    expect(extractStoragePath("https://example.com/foo.jpg")).toBeNull();
  });

  it("devuelve null para una URL malformada, sin tirar", () => {
    expect(extractStoragePath("no-es-una-url")).toBeNull();
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
