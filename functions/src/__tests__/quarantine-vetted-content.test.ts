/**
 * Tests de la cuarentena de terminos vetados, contra el emulador de Firestore.
 *
 * Lo que se mide no es que el filtro decida bien —de eso se ocupa
 * `vetted-terms-filter.test.ts` con el corpus compartido con Dart— sino que la
 * cuarentena HAGA lo que dice: redacte el campo, deje el registro, y no toque
 * lo que no tiene que tocar.
 *
 * Correr:
 *   firebase emulators:exec --only firestore --project treino-dev \
 *     "npx jest --forceExit quarantine-vetted-content"
 */

/**
 * El wrapper se prueba DIRECTO para el grupo "el wrapper real" de mas abajo:
 * el doble de `onDocumentWritten` devuelve el handler que recibe, asi que
 * `quarantineTrainerProfileName` ES esa funcion y se la puede invocar con un
 * evento armado a mano (mismo patron que `link-load-reconcile.test.ts`). El
 * resto del archivo sigue llamando a las funciones puras directo, sin pasar
 * por esto.
 */
jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentWritten: (_opts: unknown, handler: unknown) => handler,
}));

import { readFileSync } from "fs";
import { join } from "path";

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  QUARANTINE_COLLECTION,
  quarantineAuthorName,
  quarantineDisplayName,
  quarantineIfVetted,
  quarantineTrainerProfileName,
} from "../moderation/quarantine-vetted-content";

/** Firma real del handler una vez que el doble de arriba lo desenvuelve. */
type TriggerHandler = (event: {
  data: { after: FirebaseFirestore.DocumentSnapshot };
  params: { uid: string };
}) => Promise<void>;

// `trainerBio` reusa `quarantineIfVetted` (kind "profile") — no tiene una
// funcion propia como `quarantineDisplayName`, asi que sus tests viven en el
// describe de abajo en vez de sumar un import nuevo.

const VETADO = "sos un hijo de puta";

const REVIEW = "sos un pelotudo";
const LIMPIO = "buena rutina, gracias";

let app: App;
let db: Firestore;
let defaultApp: App;

beforeAll(() => {
  app = initializeApp({ projectId: "treino-dev" }, "quarantine-tests");
  db = getFirestore(app);
  // El wrapper real (`quarantineTrainerProfileName`, ver el describe "el
  // wrapper real" mas abajo) hace `getFirestore()` SIN argumentos, que
  // resuelve la app DEFAULT — no la nombrada de arriba. En produccion solo
  // existe una app, asi que nunca importa; aca hace falta una segunda app
  // (misma `projectId`, mismo emulador via las env vars de conexion) para
  // que ese `getFirestore()` interno encuentre algo en vez de tirar "The
  // default Firebase app does not exist".
  defaultApp = initializeApp({ projectId: "treino-dev" });
});

afterAll(async () => {
  await deleteApp(app);
  await deleteApp(defaultApp);
});

afterEach(async () => {
  for (const c of ["posts", "users", "userPublicProfiles",
    "trainerPublicProfiles", QUARANTINE_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const registro = (path: string) =>
  db.collection(QUARANTINE_COLLECTION).doc(path.replace(/\//g, "__")).get();

describe("quarantineIfVetted", () => {
  it("redacta el campo y deja registro cuando el veredicto es block", async () => {
    await db.doc("posts/p1").set({ text: VETADO, authorUid: "u1" });

    const v = await quarantineIfVetted({
      db, path: "posts/p1", field: "text",
      value: VETADO, kind: "post", authorUid: "u1",
    });

    expect(v).toBe("block");
    expect((await db.doc("posts/p1").get()).get("text")).toBe("");

    const reg = await registro("posts/p1");
    expect(reg.exists).toBe(true);
    expect(reg.get("verdict")).toBe("block");
    expect(reg.get("redacted")).toBe(true);
    expect(reg.get("authorUid")).toBe("u1");
  });

  it("NO guarda el texto vetado en el registro", async () => {
    // Puede tener datos personales de terceros, y en el chat datos de salud.
    // Quien modere abre el documento original, autenticado.
    await db.doc("posts/p1").set({ text: VETADO, authorUid: "u1" });
    await quarantineIfVetted({
      db, path: "posts/p1", field: "text", value: VETADO, kind: "post",
    });

    const data = JSON.stringify((await registro("posts/p1")).data());
    expect(data).not.toContain("puta");
    expect(data).not.toContain("hijo");
  });

  it("deja registro pero NO redacta cuando el veredicto es review", async () => {
    // `review` significa "que alguien lo mire", no "no podes publicar".
    // Redactarlo seria convertir una severidad en la otra.
    await db.doc("posts/p2").set({ text: REVIEW, authorUid: "u1" });

    const v = await quarantineIfVetted({
      db, path: "posts/p2", field: "text", value: REVIEW, kind: "post",
    });

    expect(v).toBe("review");
    expect((await db.doc("posts/p2").get()).get("text")).toBe(REVIEW);
    const reg = await registro("posts/p2");
    expect(reg.get("verdict")).toBe("review");
    expect(reg.get("redacted")).toBe(false);
  });

  it("no toca nada cuando el texto esta limpio", async () => {
    await db.doc("posts/p3").set({ text: LIMPIO, authorUid: "u1" });

    const v = await quarantineIfVetted({
      db, path: "posts/p3", field: "text", value: LIMPIO, kind: "post",
    });

    expect(v).toBe("ok");
    expect((await db.doc("posts/p3").get()).get("text")).toBe(LIMPIO);
    expect((await registro("posts/p3")).exists).toBe(false);
  });

  it("la segunda pasada sobre lo ya redactado no hace nada", async () => {
    // La funcion escribe sobre el documento que la disparo, asi que se vuelve
    // a disparar. Termina sola porque el campo redactado es la cadena vacia y
    // `checkText('')` da `ok`. Si esto se cae, hay bucle infinito en produccion
    // y la factura de Firestore lo cuenta antes que los tests.
    await db.doc("posts/p4").set({ text: VETADO, authorUid: "u1" });
    await quarantineIfVetted({
      db, path: "posts/p4", field: "text", value: VETADO, kind: "post",
    });

    const segunda = await quarantineIfVetted({
      db, path: "posts/p4", field: "text",
      value: (await db.doc("posts/p4").get()).get("text"), kind: "post",
    });

    expect(segunda).toBe("ok");
  });

  it("no crea un registro por intento: el id sale de la ruta", async () => {
    await db.doc("posts/p5").set({ text: VETADO, authorUid: "u1" });
    await quarantineIfVetted({
      db, path: "posts/p5", field: "text", value: VETADO, kind: "post",
    });
    await quarantineIfVetted({
      db, path: "posts/p5", field: "text", value: VETADO, kind: "post",
    });

    const todos = await db.collection(QUARANTINE_COLLECTION).get();
    expect(todos.size).toBe(1);
  });
});

describe("hallazgos de la revision", () => {
  it("no redacta si el documento cambio despues del evento", async () => {
    // Entre que el handler mira el valor y escribe, el usuario puede editar.
    // Sin precondicion el `update()` cae sobre la version NUEVA y borra una
    // edicion limpia que nadie reviso: la funcion termina destruyendo
    // contenido valido.
    //
    // Abandonar es lo correcto: esa escritura nueva disparo SU PROPIO
    // trigger y se revisa por su cuenta.
    const ref = db.doc("posts/p1");
    await ref.set({ text: VETADO, authorUid: "u1" });
    const viejo = (await ref.get()).updateTime;

    // Alguien edita entre medio.
    await ref.update({ text: "ya lo corregi" });

    await quarantineIfVetted({
      db, path: "posts/p1", field: "text", value: VETADO, kind: "post",
      updateTime: viejo,
    });

    expect((await ref.get()).get("text")).toBe("ya lo corregi");
  });

  it(
    "redacted queda en false cuando la redaccion se abandona por " +
      "precondicion, aunque el veredicto sea block",
    async () => {
      // El registro se escribe con `redacted: verdict === "block"` ANTES de
      // intentar el update() (para que exista aunque la funcion se caiga en
      // el medio). Si el update() despues aborta por FAILED_PRECONDITION, el
      // registro quedaba afirmando `redacted: true` sobre un documento que
      // en realidad no se toco — una advertencia falsa (§11.1): quien modera
      // filtrando por `redacted: false` para ver que falta atender no lo ve.
      const ref = db.doc("posts/p11");
      await ref.set({ text: VETADO, authorUid: "u1" });
      const viejo = (await ref.get()).updateTime;
      await ref.update({ text: "ya lo corregi" });

      await quarantineIfVetted({
        db, path: "posts/p11", field: "text", value: VETADO, kind: "post",
        updateTime: viejo,
      });

      const reg = await registro("posts/p11");
      expect(reg.get("verdict")).toBe("block");
      expect(reg.get("redacted")).toBe(false);
      expect((await ref.get()).get("text")).toBe("ya lo corregi");
    },
  );

  it(
    "una invocacion VIEJA no corrige a redacted:false un registro que ya " +
      "escribio una invocacion MAS NUEVA (carrera)",
    async () => {
      // finding 2 del PR #1227: `marcarRedaccionAbandonada` mezclaba
      // `{redacted: false}` sin condicion. Con el trigger disparado fuera de
      // orden, una invocacion VIEJA puede fallar su precondicion y ejecutar
      // esa correccion DESPUES de que una invocacion MAS NUEVA ya registro Y
      // redacto bien -- el registro final quedaba diciendo "no se redacto"
      // sobre un campo que si se redacto.
      //
      // Deterministico por orden de `await`, no por timing: no hay sleep ni
      // mock de reloj. Se simulan las DOS invocaciones llamando
      // `quarantineIfVetted` dos veces, en el orden en que TERMINAN (la mas
      // nueva primero, de punta a punta) y no en el orden en que un trigger
      // real las hubiera disparado.
      const ref = db.doc("posts/pCarrera");
      await ref.set({ text: VETADO, authorUid: "u1" });
      const versionVieja = (await ref.get()).updateTime;

      // El documento se reescribe -- un campo SIN RELACION, `text` queda
      // igual -- y esta es la version que gana la carrera del lado del
      // documento fuente. Con `text` sin cambios el emulador de Firestore no
      // avanza `updateTime` (lo probé: dos escrituras con el mismo valor
      // exacto dan el MISMO updateTime, y el test necesita dos timestamps
      // realmente distintos para ejercitar la comparacion). Tocar un campo
      // ajeno es ademas mas fiel al bug real: CUALQUIER write al documento
      // redispara el trigger para `text`, no solo una edicion de `text`
      // (ver el dartdoc de `quarantinePost`).
      await ref.update({ otroCampo: "cualquier cosa sin relacion" });
      const versionNueva = (await ref.get()).updateTime;

      // La invocacion MAS NUEVA corre PRIMERO y termina de punta a punta:
      // registra Y redacta con exito (su `updateTime` coincide con la
      // version actual del documento).
      await quarantineIfVetted({
        db, path: "posts/pCarrera", field: "text", value: VETADO,
        kind: "post", authorUid: "u1", updateTime: versionNueva,
      });
      expect((await ref.get()).get("text")).toBe("");
      expect((await registro("posts/pCarrera")).get("redacted")).toBe(true);

      // Recien ahora "llega" la invocacion VIEJA, con `versionVieja`: su
      // update() aborta por FAILED_PRECONDITION porque el documento ya esta
      // en la version que escribio la invocacion nueva.
      await quarantineIfVetted({
        db, path: "posts/pCarrera", field: "text", value: VETADO,
        kind: "post", authorUid: "u1", updateTime: versionVieja,
      });

      // El bug: esta correccion pisaba el registro con `redacted: false`.
      // Tiene que seguir en `true` -- el campo SI esta redactado.
      const regFinal = await registro("posts/pCarrera");
      expect(regFinal.get("redacted")).toBe(true);
      expect((await ref.get()).get("text")).toBe("");
    },
  );

  it("redacta el authorDisplayName vetado del post", async () => {
    // Viaja DENORMALIZADO y lo pone el cliente: la regla de create lo acepta
    // sin atarlo al perfil. Un post con `text` LIMPIO y nombre vetado en el
    // encabezado se renderiza tal cual, y mirando solo `text` se quedaba ahi
    // para siempre.
    const ref = db.doc("posts/p9");
    await ref.set({
      text: LIMPIO,
      authorDisplayName: VETADO,
      authorUid: "abcdef123",
    });

    const redacto = await quarantineAuthorName({
      db,
      path: "posts/p9",
      authorUid: "abcdef123",
      name: VETADO,
      updateTime: (await ref.get()).updateTime,
    });

    expect(redacto).toBe(true);
    expect((await ref.get()).get("authorDisplayName")).toBe("usuario_abcdef");
    // El texto limpio no se toca.
    expect((await ref.get()).get("text")).toBe(LIMPIO);
  });

  it("no toca un authorDisplayName limpio", async () => {
    const ref = db.doc("posts/p10");
    await ref.set({ text: LIMPIO, authorDisplayName: "Martín",
      authorUid: "abcdef123" });

    const redacto = await quarantineAuthorName({
      db, path: "posts/p10", authorUid: "abcdef123", name: "Martín",
    });

    expect(redacto).toBe(false);
    expect((await ref.get()).get("authorDisplayName")).toBe("Martín");
  });
});

describe("quarantineDisplayName", () => {
  it("reemplaza el nombre en users Y en userPublicProfiles", async () => {
    // `userPublicProfiles` es el que leen los demas. Redactar solo `users`
    // seria redactar la copia que nadie mira.
    await db.doc("users/abcdef123").set({ displayName: VETADO });
    await db.doc("userPublicProfiles/abcdef123").set({ displayName: VETADO });

    const v = await quarantineDisplayName(db, "abcdef123", VETADO);

    expect(v).toBe("block");
    expect((await db.doc("users/abcdef123").get()).get("displayName"))
      .toBe("usuario_abcdef");
    const pub = await db.doc("userPublicProfiles/abcdef123").get();
    expect(pub.get("displayName")).toBe("usuario_abcdef");
    expect(pub.get("displayNameLowercase")).toBe("usuario_abcdef");
  });

  it("el reemplazo sale del uid, asi que no le pone a nadie el nombre de otro", async () => {
    await db.doc("users/aaaaaa111").set({ displayName: VETADO });
    await db.doc("users/bbbbbb222").set({ displayName: VETADO });

    await quarantineDisplayName(db, "aaaaaa111", VETADO);
    await quarantineDisplayName(db, "bbbbbb222", VETADO);

    const a = (await db.doc("users/aaaaaa111").get()).get("displayName");
    const b = (await db.doc("users/bbbbbb222").get()).get("displayName");
    expect(a).not.toBe(b);
  });

  it("tambien limpia trainerPublicProfiles cuando existe", async () => {
    // Es el que alimenta el descubrimiento de PFs. Dejarlo vetado mientras
    // `users` queda limpio es redactar la copia que nadie mira.
    await db.doc("users/abcdef123").set({ displayName: VETADO });
    await db.doc("userPublicProfiles/abcdef123").set({ displayName: VETADO });
    await db.doc("trainerPublicProfiles/abcdef123").set({
      displayName: VETADO,
    });

    await quarantineDisplayName(db, "abcdef123", VETADO);

    const t = await db.doc("trainerPublicProfiles/abcdef123").get();
    expect(t.get("displayName")).toBe("usuario_abcdef");
    expect(t.get("displayNameLowercase")).toBe("usuario_abcdef");
  });

  it("NO crea trainerPublicProfiles para un atleta", async () => {
    // Un `set` con merge lo crearia, y un doc de entrenador fantasma en la
    // coleccion de descubrimiento es un problema nuevo, no la solucion de este.
    await db.doc("users/aaaaaa111").set({ displayName: VETADO });

    await quarantineDisplayName(db, "aaaaaa111", VETADO);

    expect((await db.doc("trainerPublicProfiles/aaaaaa111").get()).exists)
      .toBe(false);
  });

  it("no toca un nombre limpio", async () => {
    await db.doc("users/u9").set({ displayName: "Martín" });
    const v = await quarantineDisplayName(db, "u9", "Martín");
    expect(v).toBe("ok");
    expect((await db.doc("users/u9").get()).get("displayName")).toBe("Martín");
  });
});

describe("trainerBio (quarantineTrainerProfileName)", () => {
  // El filtro de terminos vetados llegaba a Feed, Chat, Resenas y
  // displayName, pero no a la bio del PF. `trainerBio` vive en
  // trainerPublicProfiles/{uid}, que cualquier autenticado puede leer
  // (firestore.rules:1843) — a diferencia de users/{uid}, que es owner-only
  // (firestore.rules:234). Por eso estos tests ejercitan `quarantineIfVetted`
  // directo sobre ESE documento, como lo hace el trigger real.
  it("redacta trainerBio vetada y deja registro", async () => {
    await db.doc("trainerPublicProfiles/t1").set({
      uid: "t1",
      trainerBio: VETADO,
    });

    const v = await quarantineIfVetted({
      db,
      path: "trainerPublicProfiles/t1",
      field: "trainerBio",
      value: VETADO,
      kind: "profile",
      authorUid: "t1",
    });

    expect(v).toBe("block");
    const doc = await db.doc("trainerPublicProfiles/t1").get();
    expect(doc.get("trainerBio")).toBe("");

    const reg = await registro("trainerPublicProfiles/t1");
    expect(reg.exists).toBe(true);
    expect(reg.get("field")).toBe("trainerBio");
    expect(reg.get("verdict")).toBe("block");
  });

  it("no toca una bio limpia", async () => {
    await db.doc("trainerPublicProfiles/t2").set({
      uid: "t2",
      trainerBio: LIMPIO,
    });

    const v = await quarantineIfVetted({
      db,
      path: "trainerPublicProfiles/t2",
      field: "trainerBio",
      value: LIMPIO,
      kind: "profile",
      authorUid: "t2",
    });

    expect(v).toBe("ok");
    expect((await db.doc("trainerPublicProfiles/t2").get()).get("trainerBio"))
      .toBe(LIMPIO);
  });

  it(
    "NO toca users/{uid}.trainerBio — esa copia es owner-only read, " +
      "nunca la lee otro usuario",
    async () => {
      // Decision de diseno: a diferencia de displayName (que SI se redacta
      // en users, userPublicProfiles Y trainerPublicProfiles porque las tres
      // copias son leidas por otros en algun punto del sistema), la bio solo
      // necesita redactarse en su espejo publico. Este test fija esa
      // decision: si alguien "simplifica" el trigger reusando
      // quarantineDisplayName-style multi-doc para bio, este test lo
      // atrapa.
      await db.doc("users/t3").set({ uid: "t3", trainerBio: VETADO });
      await db.doc("trainerPublicProfiles/t3").set({
        uid: "t3",
        trainerBio: VETADO,
      });

      await quarantineIfVetted({
        db,
        path: "trainerPublicProfiles/t3",
        field: "trainerBio",
        value: VETADO,
        kind: "profile",
        authorUid: "t3",
      });

      expect((await db.doc("trainerPublicProfiles/t3").get()).get("trainerBio"))
        .toBe("");
      expect((await db.doc("users/t3").get()).get("trainerBio")).toBe(VETADO);
    },
  );
});

describe("quarantineTrainerProfileName (el wrapper real, no las funciones puras)", () => {
  it(
    "redacta trainerBio EN LA PRIMERA PASADA cuando displayName tambien " +
      "esta vetado",
    async () => {
      // finding 5: el wrapper llama quarantineDisplayName primero, que
      // escribe un batch incluyendo ESTE MISMO documento
      // (trainerPublicProfiles/{uid}) cuando displayName da "block". El
      // codigo viejo usaba despues `after.updateTime` — el snapshot de ANTES
      // de ese batch — como precondicion para trainerBio: quedaba vieja, el
      // update() de trainerBio abortaba por FAILED_PRECONDITION, y la bio no
      // se tocaba en esta pasada aunque estuviera vetada. Se autocuraba en
      // una segunda pasada (el batch redispara este mismo trigger), pero eso
      // es una ventana de un round-trip que este test no deja pasar: tiene
      // que quedar redactada ACA, en la primera vuelta.
      await db.doc("users/abcdef123").set({
        uid: "abcdef123",
        displayName: VETADO,
      });
      await db.doc("trainerPublicProfiles/abcdef123").set({
        uid: "abcdef123",
        displayName: VETADO,
        trainerBio: VETADO,
      });
      const snap = await db.doc("trainerPublicProfiles/abcdef123").get();

      await (quarantineTrainerProfileName as unknown as TriggerHandler)({
        data: { after: snap },
        params: { uid: "abcdef123" },
      });

      const after = await db.doc("trainerPublicProfiles/abcdef123").get();
      expect(after.get("displayName")).toBe("usuario_abcdef");
      expect(after.get("trainerBio")).toBe("");

      const reg = await registro("trainerPublicProfiles/abcdef123");
      expect(reg.exists).toBe(true);
      expect(reg.get("verdict")).toBe("block");
      expect(reg.get("redacted")).toBe(true);
    },
  );

  it("no rompe el caso normal: displayName limpio, trainerBio vetada", async () => {
    // Control de que el fix de finding 5 no le agrego una precondicion
    // innecesaria al camino que ya andaba: si displayName NO se toca, el
    // updateTime releido tiene que seguir siendo valido para trainerBio.
    await db.doc("users/xyz999").set({ uid: "xyz999", displayName: "Xyz" });
    await db.doc("trainerPublicProfiles/xyz999").set({
      uid: "xyz999",
      displayName: "Xyz",
      trainerBio: VETADO,
    });
    const snap = await db.doc("trainerPublicProfiles/xyz999").get();

    await (quarantineTrainerProfileName as unknown as TriggerHandler)({
      data: { after: snap },
      params: { uid: "xyz999" },
    });

    const after = await db.doc("trainerPublicProfiles/xyz999").get();
    expect(after.get("displayName")).toBe("Xyz");
    expect(after.get("trainerBio")).toBe("");
  });
});

describe("superficies que NO se tocan", () => {
  // `athlete_notes/{trainerId}_{athleteId}` son las notas PRIVADAS que el PF
  // escribe sobre un alumno — a proposito, fuera del criterio de esta feature
  // ("si otro usuario lo va a leer, entra"): nadie mas que el propio PF las
  // lee (`firestore.rules:4040`). Sumar un trigger ahi seria censurar
  // contenido que nunca sale del backstage del entrenador.
  //
  // Assert de codigo fuente y no de Firestore, a proposito: no hay NINGUN
  // trigger escuchando `athlete_notes` hoy, asi que escribir un doc ahi y
  // comprobar que "no paso nada" no ejercita ningun camino de este modulo —
  // pasaria igual aunque alguien agregara el trigger manana con un bug que no
  // redacta. Leer el codigo fuente es lo unico que de verdad fija la
  // decision: si alguien agrega `onDocumentWritten` sobre `athlete_notes` en
  // este archivo, este test se pone rojo y obliga a una decision consciente
  // en vez de colarse en un PR sin que nadie lo note.
  it("quarantine-vetted-content.ts no declara ningun trigger sobre athlete_notes", () => {
    const source = readFileSync(
      join(__dirname, "..", "moderation", "quarantine-vetted-content.ts"),
      "utf8",
    );
    expect(source).not.toContain("athlete_notes");
  });
});
