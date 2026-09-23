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
import { getStorage } from "firebase-admin/storage";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

import {
  assertModerator,
  markReportViewedHandler,
  resolveContentPath,
  listPendingReportsHandler,
  moderationStatsHandler,
  resolveReportHandler,
  extractStoragePath,
  removalDocId,
  REVIEWS_COLLECTION,
  REMOVALS_COLLECTION,
} from "../moderation/report-review";
import { dedupeKey } from "../mail/enqueue-mail";
import { MAIL_QUEUE_COLLECTION } from "../mail/types";

let app: App;
let db: Firestore;

beforeAll(() => {
  // `storageBucket` explicito: sin el, `getStorage(app).bucket()` (sin
  // argumento — lo que usa `resolveReportHandler` en produccion, donde SI
  // hay un bucket por defecto configurado) tira "Bucket name not specified
  // or invalid". Mismo nombre que `cascade/storage.test.ts` y
  // `delete-account.smoke.test.ts` para el mismo `projectId`.
  app = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "report-review-tests",
  );
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
  for (const c of ["reports", REVIEWS_COLLECTION, REMOVALS_COLLECTION]) {
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
    // Igual que `runTransaction`: el PASO 3 de contentRemoved redacta y
    // escribe el marcador de retiro en UN batch atomico, asi que sin este
    // passthrough el wrapper rompe con "is not a function" antes de llegar
    // a lo que el helper simula.
    batch: () => real.batch(),
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
    // Igual que `runTransaction`: el PASO 3 de contentRemoved redacta y
    // escribe el marcador de retiro en UN batch atomico, asi que sin este
    // passthrough el wrapper rompe con "is not a function" antes de llegar
    // a lo que el helper simula.
    batch: () => real.batch(),
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
  it("userSuspended deshabilita al AUTOR REAL, no al declarado; audit_log guarda los dos uids", async () => {
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

  it("contenido inexistente + userSuspended: falla, no dar de baja con uid no verificable", async () => {
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
  it("mensaje de SOLO imagen: contentRemoved limpia mediaUrl y audit_log guarda la URL original", async () => {
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
  it("una accion DISTINTA sobre un reporte ya resuelto tira failed-precondition, sin ejecutar nada", async () => {
    // Deliberadamente aislado de P1-B: si la segunda accion fuera OTRO
    // contentRemoved sobre el mismo post, el guard "ni texto ni media" de
    // P1-B ya lo bloquearia por su cuenta (el texto quedo vacio tras la
    // primera resolucion) y este test no probaria PASO 0 en soledad. Con
    // una accion DISTINTA (userSuspended) — el escenario que describe el
    // bug: "una accion distinta puede suspender a alguien despues de que
    // otro moderador ya descarto el reporte" — nada MAS que PASO 0 puede
    // bloquear esto: el usuario existe en Auth y el post existe con
    // authorUid == targetOwnerUid, asi que sin el guard la suspension
    // SI se ejecutaria.
    const targetOwnerUid = "owner-double-1";
    await getAuth(app).createUser({
      uid: targetOwnerUid, email: `${targetOwnerUid}@test.com`,
    });
    extraCleanupUids.push(targetOwnerUid);

    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-double-1", targetOwnerUid,
    });
    await db.collection("posts").doc("post-double-1").set({
      text: "contenido original", authorUid: targetOwnerUid,
    });
    extraCleanupPaths.push("posts/post-double-1", "audit_log/moderation__r1");

    // Moderador 1: resuelve contentRemoved. El texto queda vacio y el
    // audit_log guarda el original.
    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    // Moderador 2, con la cola vieja: intenta userSuspended sobre el MISMO
    // reporte, ya resuelto por mod1.
    await expect(
      resolveReportHandler(db, app, "mod2", {
        reportId: "r1", status: "actioned", action: "userSuspended",
      }),
    ).rejects.toThrow(/ya resolvio este reporte/i);

    // Nunca se llego a deshabilitar a nadie.
    const user = await getAuth(app).getUser(targetOwnerUid);
    expect(user.disabled).toBe(false);

    // Y la evidencia original de mod1 sigue intacta — nadie la piso.
    const audit = await db.collection("audit_log").doc("moderation__r1").get();
    expect(audit.get("removedContent")).toBe("contenido original");
    expect(audit.get("moderatorUid")).toBe("mod1");
  });
});

describe("resolveReport — P2-A: el borrado de Storage exige que el path sea del dueno derivado", () => {
  it("un photoUrl que apunta al objeto de OTRO usuario: el objeto NO se borra, y el audit_log lo registra", async () => {
    // El ataque real: el atacante es autor de SU PROPIO post (asi que
    // `authorUid`/derivedOwnerUid es el atacante mismo — esto NO es P1-A,
    // aca no hay mentira sobre quien es el dueno), pero copio como
    // `photoUrl` el path de un objeto ajeno. Sin el chequeo de prefijo,
    // "Contenido retirado" borraria el archivo de la victima.
    const atacanteUid = "atacante-p2a-1";
    const victimaUid = "victima-p2a-1";
    const bucket = getStorage(app).bucket();
    const victimPath = `postPhotos/${victimaUid}/foto-victima-p2a.jpg`;
    const fakePhotoUrl =
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodeURIComponent(victimPath)}?alt=media&token=xyz`;

    // El objeto REAL de la victima, para poder confirmar que sigue ahi
    // despues. Bucket real (no un mock): si el chequeo de prefijo tuviera
    // un bug y de verdad intentara borrar, este test lo detectaria.
    await bucket.file(victimPath).save(Buffer.from("foto de la victima"));

    try {
      await sembrarReporte("r1", 3600_000, {
        targetKind: "post", targetId: "post-p2a-1", targetOwnerUid: atacanteUid,
      });
      await db.collection("posts").doc("post-p2a-1").set({
        text: "post con photoUrl ajeno", authorUid: atacanteUid,
        photoUrl: fakePhotoUrl,
      });
      extraCleanupPaths.push("posts/post-p2a-1", "audit_log/moderation__r1");

      await resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      });

      // El objeto de la victima SIGUE existiendo — no se borro.
      const [existe] = await bucket.file(victimPath).exists();
      expect(existe).toBe(true);

      // El texto SI se redacto (eso no depende de Storage) y el audit_log
      // deja explicito que el path del media NO era de confianza.
      const post = await db.collection("posts").doc("post-p2a-1").get();
      expect(post.get("text")).toBe("");

      const audit = await db.collection("audit_log").doc("moderation__r1").get();
      expect(audit.get("removedMediaPathTrusted")).toBe(false);
      expect(audit.get("removedMediaUrl")).toBe(fakePhotoUrl);
    } finally {
      await bucket.file(victimPath).delete().catch(() => undefined);
    }
  });
});

describe("resolveReport — P2-B: el claim del PASO 0 excluye una carrera de verdad", () => {
  it("dos resoluciones SIMULTANEAS sobre el mismo reporte: exactamente una tiene exito y el estado final es coherente", async () => {
    // A diferencia de P1-D —secuencial: la primera resolucion termina
    // ANTES de que arranque la segunda, asi que solo ejercita el chequeo
    // de "status ya resuelto"— las dos promesas de aca arrancan JUNTAS, sin
    // esperarse. Es la ventana de milisegundos que el PASO 0 tiene que
    // excluir con una ESCRITURA, no con una lectura.
    const targetOwnerUid = "owner-race2-1";
    await getAuth(app).createUser({
      uid: targetOwnerUid, email: `${targetOwnerUid}@test.com`,
    });
    extraCleanupUids.push(targetOwnerUid);

    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-race2-1", targetOwnerUid,
    });
    await db.collection("posts").doc("post-race2-1").set({
      text: "contenido", authorUid: targetOwnerUid,
    });
    extraCleanupPaths.push("posts/post-race2-1", "audit_log/moderation__r1");

    const [r1, r2] = await Promise.allSettled([
      resolveReportHandler(db, app, "mod1", {
        reportId: "r1", status: "dismissed", action: "none",
      }),
      resolveReportHandler(db, app, "mod2", {
        reportId: "r1", status: "actioned", action: "userSuspended",
      }),
    ]);

    // Exactamente una de las dos tiene exito.
    const resultados = [r1, r2];
    expect(resultados.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const fallida = resultados.find((r) => r.status === "rejected") as
      PromiseRejectedResult;
    expect(fallida.reason).toBeInstanceOf(HttpsError);
    expect((fallida.reason as HttpsError).code).toBe("failed-precondition");

    // El estado final es EXACTAMENTE el de la que gano — nunca una mezcla.
    // El bug original permitia esto: mod2 deshabilita al usuario en Auth,
    // pero mod1 gana el PASO 4 y deja report_reviews diciendo
    // "dismissed"/"none" — una cuenta dada de baja con el registro
    // diciendo que no se hizo nada.
    const rev = await db.collection(REVIEWS_COLLECTION).doc("r1").get();
    const user = await getAuth(app).getUser(targetOwnerUid);

    if (r1.status === "fulfilled") {
      expect(rev.get("status")).toBe("dismissed");
      expect(rev.get("action")).toBe("none");
      expect(user.disabled).toBe(false);
    } else {
      expect(rev.get("status")).toBe("actioned");
      expect(rev.get("action")).toBe("userSuspended");
      expect(user.disabled).toBe(true);
    }
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

  describe("regresion CodeQL — alerta 29 (Incomplete URL substring sanitization)", () => {
    // Los tres tests de arriba pasaban igual con el bug puesto: ninguno
    // ejercitaba un host que CONTIENE el dominio real sin SER el dominio
    // real, ni un path bien-hosteado pero con otra forma.
    it("no confunde un host que CONTIENE el dominio real con el dominio real", () => {
      // Con `hostname.includes(...)` (el codigo original que marco
      // CodeQL) este host pasaba el chequeo: el dominio REAL es
      // "evil.com", "firebasestorage.googleapis.com" es solo un prefijo.
      expect(
        extractStoragePath(
          "https://firebasestorage.googleapis.com.evil.com/v0/b/x/o/p.jpg",
        ),
      ).toBeNull();
    });

    it("no toma el ultimo segmento de cualquier path como si fuera /v0/b/.../o/...", () => {
      // Con el codigo original (`pathSegments.lastWhere` sin validar la
      // forma completa) esto devolvia "cosa". La forma real de una URL de
      // descarga tiene exactamente 5 segmentos.
      expect(
        extractStoragePath(
          "https://firebasestorage.googleapis.com/cualquier/cosa",
        ),
      ).toBeNull();
    });
  });

  describe("expectedBucket", () => {
    it("sin expectedBucket, no valida el bucket (compat con los tests de arriba)", () => {
      expect(
        extractStoragePath(
          "https://firebasestorage.googleapis.com/v0/b/cualquier-bucket/o/" +
          "postPhotos%2Fuid1%2Fpost1.jpg",
        ),
      ).toBe("postPhotos/uid1/post1.jpg");
    });

    it("con expectedBucket, devuelve null si el segmento de la URL no coincide", () => {
      expect(
        extractStoragePath(
          "https://firebasestorage.googleapis.com/v0/b/bucket-ajeno/o/" +
          "postPhotos%2Fuid1%2Fpost1.jpg",
          "mi-bucket-real",
        ),
      ).toBeNull();
    });

    it("con expectedBucket, deriva el path si el segmento SI coincide", () => {
      expect(
        extractStoragePath(
          "https://firebasestorage.googleapis.com/v0/b/mi-bucket-real/o/" +
          "postPhotos%2Fuid1%2Fpost1.jpg",
          "mi-bucket-real",
        ),
      ).toBe("postPhotos/uid1/post1.jpg");
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

describe("resolveReport — P3-A: los duplicados de un reporte ya accionado", () => {
  /**
   * Siembra DOS reportes sobre el mismo post, de denunciantes distintos —
   * que es lo que pasa de verdad: el id de un reporte incluye al
   * denunciante (`firestore.rules:4614-4616`), asi que veinte denuncias
   * sobre el mismo post son veinte documentos.
   */
  async function sembrarDosDenunciasDelMismoPost(postId: string) {
    const owner = `owner-${postId}`;
    await sembrarReporte("r1", 4 * 3600_000, {
      targetKind: "post", targetId: postId,
      targetOwnerUid: owner, reporterUid: "denunciante-1",
    });
    await sembrarReporte("r2", 3 * 3600_000, {
      targetKind: "post", targetId: postId,
      targetOwnerUid: owner, reporterUid: "denunciante-2",
    });
    await db.collection("posts").doc(postId).set({
      text: "contenido que viola las normas", authorUid: owner,
    });
    extraCleanupPaths.push(
      `posts/${postId}`,
      "audit_log/moderation__r1",
      "audit_log/moderation__r2",
    );
    return owner;
  }

  it("el duplicado se cierra como contentRemoved y apunta al reporte que lo ejecuto", async () => {
    const owner = await sembrarDosDenunciasDelMismoPost("post-p3a-1");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    // El segundo: mismo contenido, ya vacio. Antes tiraba "no tiene texto ni
    // contenido multimedia para retirar" — un mensaje FALSO — y dejaba al
    // moderador sin forma de cerrarlo salvo como dismissed/none.
    await resolveReportHandler(db, app, "mod1", {
      reportId: "r2", status: "actioned", action: "contentRemoved",
    });

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r2").get();
    expect(rev.get("status")).toBe("actioned");
    expect(rev.get("action")).toBe("contentRemoved");

    const audit = await db.collection("audit_log").doc("moderation__r2").get();
    expect(audit.get("action")).toBe("contentRemoved");
    // Apunta a donde esta la evidencia, y NO duplica el texto original con
    // una copia vacia que leeria como "lo retirado era la cadena vacia".
    expect(audit.get("alreadyRemovedByReportId")).toBe("r1");
    expect(audit.get("removedContent")).toBeNull();
    // El dueno derivado sigue saliendo del contenido, no del reporte.
    expect(audit.get("derivedOwnerUid")).toBe(owner);
  });

  it("el retiro deja el marcador indexado por CONTENIDO, no por reporte", async () => {
    const owner = await sembrarDosDenunciasDelMismoPost("post-p3a-2");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    const marca = await db
      .collection(REMOVALS_COLLECTION)
      .doc(removalDocId("post", "post-p3a-2"))
      .get();
    expect(marca.exists).toBe(true);
    expect(marca.get("reportId")).toBe("r1");
    expect(marca.get("derivedOwnerUid")).toBe(owner);
    expect(marca.get("path")).toBe("posts/post-p3a-2");
    expect(marca.get("removedMedia")).toBe(false);
    // El texto retirado NO se copia aca: vive en el audit_log.
    expect(marca.get("removedContent")).toBeUndefined();
  });

  it("el duplicado NO vuelve a tocar el contenido", async () => {
    await sembrarDosDenunciasDelMismoPost("post-p3a-3");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });
    const despuesDelPrimero =
      (await db.collection("posts").doc("post-p3a-3").get()).updateTime;

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r2", status: "actioned", action: "contentRemoved",
    });

    const post = await db.collection("posts").doc("post-p3a-3").get();
    expect(post.get("text")).toBe("");
    // Misma version del documento: el duplicado no escribio nada encima.
    expect(post.updateTime?.isEqual(despuesDelPrimero!)).toBe(true);
  });

  it("si el contenido ademas se borro, el duplicado se cierra igual", async () => {
    await sembrarDosDenunciasDelMismoPost("post-p3a-4");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });
    // El autor borra el post despues de que la moderacion lo retiro. El
    // hecho de que se retiro no deja de ser cierto porque el documento ya
    // no este.
    await db.collection("posts").doc("post-p3a-4").delete();

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r2", status: "actioned", action: "contentRemoved",
    });

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r2").get();
    expect(rev.get("action")).toBe("contentRemoved");
    const audit = await db.collection("audit_log").doc("moderation__r2").get();
    // El dueno derivado sale del marcador cuando el documento ya no esta.
    expect(audit.get("derivedOwnerUid")).toBe("owner-post-p3a-4");
  });

  it("el marcador NO cubre contenido NUEVO: si el autor reescribe, se redacta", async () => {
    await sembrarDosDenunciasDelMismoPost("post-p3a-5");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });
    // El autor reescribe el mismo post. Hay contenido NUEVO: el segundo
    // reporte tiene que retirarlo de verdad, no cerrarse como duplicado.
    await db.collection("posts").doc("post-p3a-5").update({
      text: "lo volvi a escribir igual",
    });

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r2", status: "actioned", action: "contentRemoved",
    });

    const post = await db.collection("posts").doc("post-p3a-5").get();
    expect(post.get("text")).toBe("");
    const audit = await db.collection("audit_log").doc("moderation__r2").get();
    expect(audit.get("removedContent")).toBe("lo volvi a escribir igual");
    expect(audit.get("alreadyRemovedByReportId")).toBeNull();
  });

  it("si el autor republica antes del cierre, el duplicado aborta", async () => {
    // El camino del duplicado no escribe sobre el contenido, asi que no
    // tiene donde poner el `lastUpdateTime` que protege al camino normal.
    // Sin la revalidacion del PASO 4, el reporte quedaria cerrado como
    // "contenido retirado" sobre contenido VIVO.
    await sembrarDosDenunciasDelMismoPost("post-p3a-7");

    await resolveReportHandler(db, app, "mod1", {
      reportId: "r1", status: "actioned", action: "contentRemoved",
    });

    // El autor restaura el texto DESPUES de que el PASO 1 del duplicado lo
    // vio vacio — `dbConCarrera` interfiere en la escritura del audit_log,
    // que es justo esa ventana.
    const conCarrera = dbConCarrera(db, () =>
      db.collection("posts").doc("post-p3a-7").update({
        text: "lo republique",
      }),
    );

    await expect(
      resolveReportHandler(conCarrera, app, "mod1", {
        reportId: "r2", status: "actioned", action: "contentRemoved",
      }),
    ).rejects.toThrow(/cambio mientras lo revisabas/i);

    const rev = await db.collection(REVIEWS_COLLECTION).doc("r2").get();
    expect(rev.exists).toBe(false);
    // Y el contenido republicado sigue en pie: el reporte vuelve a la cola
    // para que lo miren de nuevo, ahora con texto.
    expect((await db.collection("posts").doc("post-p3a-7").get()).get("text"))
      .toBe("lo republique");
  });

  it("la redaccion y el marcador son atomicos: si el autor edita en el medio, no entra ninguno", async () => {
    const owner = "owner-post-p3a-6";
    await sembrarReporte("r1", 3600_000, {
      targetKind: "post", targetId: "post-p3a-6", targetOwnerUid: owner,
    });
    await db.collection("posts").doc("post-p3a-6").set({
      text: "texto original", authorUid: owner,
    });
    extraCleanupPaths.push("posts/post-p3a-6", "audit_log/moderation__r1");

    // El autor edita entre el PASO 1 y el PASO 3 — la misma carrera que
    // cubre el test de `aborted`, mirada desde el marcador.
    const conCarrera = dbConCarrera(db, () =>
      db.collection("posts").doc("post-p3a-6").update({ text: "lo edite" }),
    );

    await expect(
      resolveReportHandler(conCarrera, app, "mod1", {
        reportId: "r1", status: "actioned", action: "contentRemoved",
      }),
    ).rejects.toThrow(/cambio mientras lo revisabas/i);

    const marca = await db
      .collection(REMOVALS_COLLECTION)
      .doc(removalDocId("post", "post-p3a-6"))
      .get();
    // Sin esta atomicidad el marcador quedaria diciendo que se retiro algo
    // que sigue publicado — y habilitaria a cerrar los duplicados sobre
    // contenido vivo.
    expect(marca.exists).toBe(false);
    expect((await db.collection("posts").doc("post-p3a-6").get()).get("text"))
      .toBe("lo edite");
  });
});
