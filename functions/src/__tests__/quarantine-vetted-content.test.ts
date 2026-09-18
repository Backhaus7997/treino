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

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  QUARANTINE_COLLECTION,
  quarantineAuthorName,
  quarantineDisplayName,
  quarantineIfVetted,
} from "../moderation/quarantine-vetted-content";

const VETADO = "sos un hijo de puta";

const REVIEW = "sos un pelotudo";
const LIMPIO = "buena rutina, gracias";

let app: App;
let db: Firestore;

beforeAll(() => {
  app = initializeApp({ projectId: "treino-dev" }, "quarantine-tests");
  db = getFirestore(app);
});

afterAll(async () => {
  await deleteApp(app);
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
