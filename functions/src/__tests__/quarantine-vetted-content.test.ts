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
    QUARANTINE_COLLECTION]) {
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

  it("no toca un nombre limpio", async () => {
    await db.doc("users/u9").set({ displayName: "Martín" });
    const v = await quarantineDisplayName(db, "u9", "Martín");
    expect(v).toBe("ok");
    expect((await db.doc("users/u9").get()).get("displayName")).toBe("Martín");
  });
});
