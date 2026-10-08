/**
 * Enforcement real del piso de edad mínima en `users/{uid}` — `bornAtOk()` de
 * `firestore.rules`, en las cláusulas de CREATE y de UPDATE.
 *
 * Mismo criterio que `blocks-rules.test.ts`: `@firebase/rules-unit-testing`
 * con el `firestore.rules` REAL cargado y aplicado, no el Admin SDK.
 * `withSecurityRulesDisabled` se usa SOLO para sembrar estado previo.
 *
 * El caso que justifica el archivo es el de UPDATE. Sin esa cláusula, el gate
 * entero es decorativo: uno se da de alta con una fecha válida y después la
 * cambia desde el editor de perfil, y nada lo frena.
 *
 * El `assertSucceeds` del create SIN `bornAt` tampoco es relleno: la regla
 * valida el PISO y no la PRESENCIA, y tiene que seguir siendo así. El alta por
 * email crea este documento en `signUpWithEmail` ANTES de preguntar la fecha;
 * el día que alguien "endurezca" la regla exigiendo el campo, este test le
 * avisa que rompió el alta entera en vez de que lo descubra un usuario.
 *
 * ⚠ Ese test solo NO alcanzó, y es la lección de este archivo: sembraba el doc
 * SIN la clave, y la app nunca manda eso. `UserProfile.toJson()` emite
 * `bornAt: null` (`user_profile.g.dart`), y la primera versión de la regla
 * —`'bornAt' in data`— denegaba el null. Este archivo estaba verde mientras
 * nadie nuevo podía terminar el alta (sep-2026). Los casos con `bornAt: null`
 * son los que miden lo que de verdad llega; no los saques por redundantes.
 *
 * Este archivo tiene que matchear `[-]rules\.test\.ts$` (package.json
 * `test:rules`) o no corre en CI.
 *
 * Correr contra el emulador (requiere Java 21):
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
import {
  doc,
  setDoc,
  updateDoc,
  deleteField,
  setLogLevel,
} from "firebase/firestore";

const PROJECT_ID = "treino-rules-test-born-at";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const UID = "athlete-uid";

/**
 * Días con los que la regla aproxima la edad mínima: 13 × 365. Son TRES MENOS
 * que 13 años reales (4748, contando los bisiestos del período), y esa holgura
 * es deliberada — ver el comentario de `bornAtOk` en firestore.rules.
 */
const FLOOR_DAYS = 4745;

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

const daysAgo = (n: number) => new Date(Date.now() - n * 86_400_000);
const yearsAgo = (n: number) => daysAgo(Math.round(n * 365.25));

/**
 * Doc mínimo que satisface el RESTO de las cláusulas, create y update.
 *
 * `createdAt` no lo pide el create, pero el update lo pinea contra su valor
 * previo — y sobre un doc sembrado sin el campo, la comparación no deniega:
 * tira "Property createdAt is undefined on object", que es un error de
 * evaluación. Un `assertFails` sobre ese doc pasaría por el motivo equivocado
 * (campo ausente) y no por el piso de edad, que es lo que este archivo dice
 * estar midiendo. Ver docs/security.md §1.8.
 */
function newUserDoc(extra: Record<string, unknown> = {}) {
  return {
    uid: UID,
    role: "athlete",
    email: "a@example.com",
    createdAt: new Date("2026-01-01T00:00:00.000Z"),
    ...extra,
  };
}

/** Siembra un usuario ya existente, saltándose las rules. */
async function seedUser(extra: Record<string, unknown> = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", UID), newUserDoc(extra));
  });
}

describe("bornAtOk — piso de edad mínima en users/{uid}", () => {
  describe("create", () => {
    it("con la fecha de alguien de 20 → permitido", async () => {
      await assertSucceeds(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: yearsAgo(20) }),
        ),
      );
    });

    it("con la fecha de alguien de 12 → denegado", async () => {
      await assertFails(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: yearsAgo(12) }),
        ),
      );
    });

    // La banda 13-15 es el motivo del cambio de 16 a 13. Sin este caso, bajar
    // el piso en las reglas pasa con el valor viejo intacto: los de 20 y 12
    // dan igual con 5840 dias que con 4745.
    it("con la fecha de alguien de 14 → PERMITIDO (la banda nueva)", async () => {
      await assertSucceeds(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: yearsAgo(14) }),
        ),
      );
    });

    it("SIN bornAt → permitido (es el camino del alta por email)", async () => {
      // La regla valida el piso, NO la presencia. signUpWithEmail crea este
      // doc antes de que la fecha se haya preguntado: exigir el campo acá
      // rompe el alta por email entera.
      await assertSucceeds(
        setDoc(doc(asUser(UID), "users", UID), newUserDoc()),
      );
    });

    it("con bornAt: null → permitido (es lo que manda la app)", async () => {
      // El caso que importa de verdad: `UserProfile.toJson()` emite la clave
      // en null, y ese es el payload de getOrCreate y createIfAbsent en toda
      // versión de la app anterior al fix. Con `'bornAt' in data` esto era un
      // assertFails, y el alta entera estaba rota.
      await assertSucceeds(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: null }),
        ),
      );
    });

    it("con bornAt de otro tipo → denegado, no error de evaluación", async () => {
      // El `is timestamp` de la regla. Sin él esto no DENIEGA: tira error de
      // evaluación, que rebota la escritura con un mensaje que no dice nada.
      await assertFails(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: "1990-05-20" }),
        ),
      );
    });
  });

  describe("update — la cláusula sin la cual el gate es decorativo", () => {
    it("bajar bornAt a la fecha de alguien de 12 → denegado", async () => {
      await seedUser({ bornAt: yearsAgo(20) });
      await assertFails(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: yearsAgo(12),
        }),
      );
    });

    it("cambiar bornAt a la fecha de alguien de 30 → permitido", async () => {
      await seedUser({ bornAt: yearsAgo(20) });
      await assertSucceeds(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: yearsAgo(30),
        }),
      );
    });

    // Hallazgo de Codex en el PR #1162, verificado contra el emulador ANTES de
    // cerrarlo: sin `bornAtKept` este assertFails era un assertSucceeds.
    it("BORRAR un bornAt ya cargado → denegado", async () => {
      await seedUser({ bornAt: yearsAgo(20) });
      await assertFails(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: deleteField(),
        }),
      );
    });

    // El otro camino para borrarla, y el que se abriría si `bornAtKept`
    // volviera a preguntar por la clave: `bornAtOk` acepta null, así que lo
    // único que frena esto es que `bornAtKept` compare valores.
    it("PONER EN NULL un bornAt ya cargado → denegado", async () => {
      await seedUser({ bornAt: yearsAgo(20) });
      await assertFails(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: null,
        }),
      );
    });

    // Control de que la clausula nueva no rompio el resto: aplica a TODO
    // update, y un update que ni menciona bornAt tiene que seguir pasando
    // (`request.resource.data` es el documento resultante completo, no el diff).
    it("un update ajeno a bornAt sigue permitido", async () => {
      await seedUser({ bornAt: yearsAgo(20) });
      await assertSucceeds(
        updateDoc(doc(asUser(UID), "users", UID), {
          displayName: "carlitos",
        }),
      );
    });

    it("cargar bornAt por primera vez sobre un doc que no lo tenía", async () => {
      // El camino de BirthDateGateScreen: cuenta preexistente que nunca
      // declaró la fecha.
      await seedUser();
      await assertSucceeds(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: yearsAgo(25),
        }),
      );
    });

    // Las dos de abajo siembran la forma REAL de una cuenta sin fecha: la
    // clave presente en null, porque así la crea `toJson()`. Sembrarla sin la
    // clave es exactamente el fixture que dejó pasar el bug.
    it("cargar bornAt sobre un doc con bornAt: null → permitido", async () => {
      await seedUser({ bornAt: null });
      await assertSucceeds(
        updateDoc(doc(asUser(UID), "users", UID), {
          bornAt: yearsAgo(25),
        }),
      );
    });

    it("un update ajeno sobre un doc con bornAt: null → permitido", async () => {
      // Es la escritura del gimnasio durante el alta con un build viejo:
      // `{gymId}` sobre el doc recién creado, que todavía no tiene fecha.
      // Con la regla que preguntaba por la clave, esto se denegaba.
      await seedUser({ bornAt: null });
      await assertSucceeds(
        updateDoc(doc(asUser(UID), "users", UID), {
          gymId: "ChIJ_gym",
        }),
      );
    });
  });

  describe("el borde de la aproximación por días", () => {
    it(`justo en el piso (${FLOOR_DAYS} días) → permitido`, async () => {
      await assertSucceeds(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: daysAgo(FLOOR_DAYS) }),
        ),
      );
    });

    it(`un día por encima del piso (${FLOOR_DAYS - 1}) → denegado`, async () => {
      await assertFails(
        setDoc(
          doc(asUser(UID), "users", UID),
          newUserDoc({ bornAt: daysAgo(FLOOR_DAYS - 1) }),
        ),
      );
    });
  });
});
