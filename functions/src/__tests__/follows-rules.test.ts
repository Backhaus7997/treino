/**
 * Tests de enforcement real de las rules de `follows/{followId}`.
 *
 * Usa `@firebase/rules-unit-testing` con `firestore.rules` cargado y APLICADO,
 * no el Admin SDK. La distinción no es cosmética: los tests de rules que corrían
 * en CI hasta ahora sembraban con `withSecurityRulesDisabled` y después
 * verificaban con privilegios de admin, o sea **bypasseaban las reglas que
 * decían estar probando**. Acá `withSecurityRulesDisabled` se usa SOLO para
 * sembrar el estado previo; toda aserción corre en un contexto de cliente
 * autenticado.
 *
 * Este archivo tiene que estar en el regex de `test:rules` del package.json o
 * no corre en el job `functions-test` — sin eso no se cumple LD-09 y estaríamos
 * migrando el gate de acceso más crítico de la app arrastrando la misma falta
 * de cobertura que ya nos dejó reglas "verdes en emulador, muertas en el
 * teléfono".
 *
 * Correr contra el emulador:
 *   npm --prefix functions run test:rules:emulator
 *
 * REQ: REQ-FOLLOW-001/003/004/005/006/008 · SCENARIO-800/804/805/806/809
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

const PROJECT_ID = "treino-rules-test";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");
const COL_FOLLOWS = "follows";
const COL_PROFILES = "userPublicProfiles";

const AT = new Date("2026-08-04T12:00:00.000Z");

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

const edgeId = (follower: string, followee: string) =>
  `${follower}_${followee}`;

/** Cuerpo canónico de una arista — las 6 keys de la allowlist, nada más. */
function edgeBody(
  follower: string,
  followee: string,
  status: "pending" | "accepted",
) {
  return {
    id: edgeId(follower, followee),
    followerUid: follower,
    followeeUid: followee,
    status,
    members: [follower, followee],
    createdAt: AT,
  };
}

/** Siembra el perfil público del target (rules deshabilitadas, solo setup). */
async function seedProfile(uid: string, isProfilePublic?: boolean) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const body: Record<string, unknown> = { uid, displayName: uid };
    if (isProfilePublic !== undefined) body.isProfilePublic = isProfilePublic;
    await ctx.firestore().collection(COL_PROFILES).doc(uid).set(body);
  });
}

/** Siembra una arista ya existente (rules deshabilitadas, solo setup). */
async function seedEdge(
  follower: string,
  followee: string,
  status: "pending" | "accepted",
) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection(COL_FOLLOWS)
      .doc(edgeId(follower, followee))
      .set(edgeBody(follower, followee, status));
  });
}

const asUser = (uid: string) => testEnv.authenticatedContext(uid).firestore();

// ── create ──────────────────────────────────────────────────────────────────
describe("follows — create", () => {
  // REQ-FOLLOW-001 / SCENARIO-800
  it("el follower crea su propia arista con id determinístico", async () => {
    await seedProfile("bob", false);
    const db = asUser("alice");

    await assertSucceeds(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "pending")),
    );
  });

  it("deniega crear una arista en nombre de otro", async () => {
    await seedProfile("bob", false);
    const db = asUser("mallory");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "pending")),
    );
  });

  it("deniega si el doc id no coincide con follower_followee", async () => {
    // Sin esto, el lookup por doc id que hacen las rules de posts deja de ser
    // confiable: el id podría no describir la arista que el documento dice ser.
    await seedProfile("bob", false);
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc("cualquier_cosa")
        .set(edgeBody("alice", "bob", "pending")),
    );
  });

  it("deniega seguirse a uno mismo", async () => {
    await seedProfile("alice", true);
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "alice"))
        .set(edgeBody("alice", "alice", "accepted")),
    );
  });

  it("deniega un campo fuera de la allowlist de 6 keys", async () => {
    await seedProfile("bob", false);
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set({ ...edgeBody("alice", "bob", "pending"), esAdmin: true }),
    );
  });

  it("deniega members que no sea [follower, followee]", async () => {
    await seedProfile("bob", false);
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set({
          ...edgeBody("alice", "bob", "pending"),
          members: ["bob", "alice"],
        }),
    );
  });

  // REQ-FOLLOW-004 / SCENARIO-804
  it("cuenta PÚBLICA: permite crear directamente accepted", async () => {
    await seedProfile("bob", true);
    const db = asUser("alice");

    await assertSucceeds(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "accepted")),
    );
  });

  it("perfil legacy SIN el campo: se trata como público", async () => {
    // Los perfiles anteriores a la feature de privacidad no tienen el campo.
    // Tratarlos como privados les rompería el auto-accept a cuentas que nunca
    // pidieron ser privadas.
    await seedProfile("bob");
    const db = asUser("alice");

    await assertSucceeds(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "accepted")),
    );
  });

  // REQ-FOLLOW-005 / SCENARIO-805
  it("cuenta PRIVADA: deniega accepted directo, permite pending", async () => {
    await seedProfile("bob", false);
    const db = asUser("alice");

    await assertFails(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "accepted")),
    );
    await assertSucceeds(
      db
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .set(edgeBody("alice", "bob", "pending")),
    );
  });
});

// ── update (aceptar) ────────────────────────────────────────────────────────
describe("follows — update", () => {
  // REQ-FOLLOW-005 / SCENARIO-805
  it("el followee acepta: pending → accepted", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertSucceeds(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted" }),
    );
  });

  it("el follower NO puede auto-aceptarse (equivalente a SCENARIO-132)", async () => {
    // En el modelo viejo esto era una condición explícita que alguien podía
    // borrar sin querer. Acá es estructural: solo el followee puede hacer
    // update, y el doc id fija quién es cada uno.
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted" }),
    );
  });

  it("un tercero no puede aceptar", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted" }),
    );
  });

  it("deniega volver accepted → pending", async () => {
    await seedEdge("alice", "bob", "accepted");

    await assertFails(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "pending" }),
    );
  });

  it("deniega cambiar la DIRECCIÓN al aceptar", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted", followerUid: "bob", followeeUid: "alice" }),
    );
  });

  // 1.25b — allowlist cerrada TAMBIÉN en el update
  it("deniega agregar un campo fuera de la allowlist al aceptar", async () => {
    // El update es la única escritura que hace alguien distinto del creador del
    // doc. Sin `hasOnly`, aceptar una solicitud sería una vía para inyectar
    // campos que las rules no validan — y el documento resultante lo rechaza
    // después la verificación de la migración (V5).
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted", campoPlantado: "x" }),
    );
  });

  it("deniega desincronizar `id` del doc id al aceptar", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted", id: "otra_cosa" }),
    );
  });

  it("deniega mover createdAt al aceptar", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .update({ status: "accepted", createdAt: new Date("2020-01-01") }),
    );
  });
});

// ── delete ──────────────────────────────────────────────────────────────────
describe("follows — delete", () => {
  // REQ-FOLLOW-006 / SCENARIO-806
  it("el follower cancela su propia solicitud pending", async () => {
    // Hoy esto es IMPOSIBLE en la app: el pill "SOLICITUD ENVIADA" tiene
    // onTap null. Es uno de los agujeros que el change viene a tapar.
    await seedEdge("alice", "bob", "pending");

    await assertSucceeds(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .delete(),
    );
  });

  it("el followee rechaza una solicitud recibida", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertSucceeds(
      asUser("bob").collection(COL_FOLLOWS).doc(edgeId("alice", "bob")).delete(),
    );
  });

  // REQ-FOLLOW-008 / SCENARIO-809
  it("CUALQUIERA de los dos miembros borra una arista accepted", async () => {
    await seedEdge("alice", "bob", "accepted");
    await assertSucceeds(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .delete(),
    );

    // Y el otro lado también: es lo que va a habilitar "quitar seguidor".
    await seedEdge("carol", "dave", "accepted");
    await assertSucceeds(
      asUser("dave")
        .collection(COL_FOLLOWS)
        .doc(edgeId("carol", "dave"))
        .delete(),
    );
  });

  it("un tercero no puede borrar una arista ajena", async () => {
    await seedEdge("alice", "bob", "accepted");

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .delete(),
    );
  });

  it("borrar una dirección NO borra la inversa", async () => {
    // El caso mutuo: las dos aristas del par son documentos independientes.
    await seedEdge("alice", "bob", "accepted");
    await seedEdge("bob", "alice", "accepted");

    await assertSucceeds(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .delete(),
    );
    await assertSucceeds(
      asUser("bob").collection(COL_FOLLOWS).doc(edgeId("bob", "alice")).get(),
    );
  });
});

// ── read ────────────────────────────────────────────────────────────────────
describe("follows — read", () => {
  // REQ-FOLLOW-003 / SCENARIO-802
  it("un miembro lee su arista", async () => {
    await seedEdge("alice", "bob", "accepted");

    await assertSucceeds(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .get(),
    );
  });

  // REQ-FOLLOWLIST-001
  //
  // Las listas de SEGUIDORES/SEGUIDOS de cualquier usuario son públicas para
  // usuarios autenticados, así que un tercero SÍ lee una arista `accepted`
  // ajena. Antes de `follow-lists` esto estaba denegado: la lista propia se
  // podía listar y la ajena no.
  it("un tercero lee una arista accepted ajena", async () => {
    await seedEdge("alice", "bob", "accepted");

    await assertSucceeds(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .get(),
    );
  });

  // La apertura llega hasta `accepted` y ni un paso más: una solicitud sin
  // resolver sigue siendo asunto de los dos involucrados.
  it("un tercero NO lee una arista pending ajena", async () => {
    await seedEdge("alice", "bob", "pending");

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .get(),
    );
  });

  it("leer una arista inexistente resuelve, no explota", async () => {
    // `getEdge` se usa para preguntar "¿lo sigo?" y la respuesta legítima más
    // común es "no". Si eso fallara, la pantalla de perfil no podría dibujar el
    // botón SEGUIR sin comerse un permission-denied.
    await assertSucceeds(
      asUser("alice")
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "nadie"))
        .get(),
    );
  });

  it("un anónimo no lee nada", async () => {
    await seedEdge("alice", "bob", "accepted");

    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection(COL_FOLLOWS)
        .doc(edgeId("alice", "bob"))
        .get(),
    );
  });
});

// ── listas de seguidores / seguidos ─────────────────────────────────────────
//
// Firestore evalúa la regla documento por documento y **no ve las cláusulas
// `where`**: no hay forma de que la regla sepa de quién es la lista pedida. Y
// si una sola fila del resultado no pasa, rechaza la QUERY ENTERA en vez de
// filtrarla. Los dos hechos juntos son los que fuerzan la forma de la regla:
// el permiso tiene que depender sólo de campos del documento evaluado
// (`status == 'accepted'`), y el filtro del cliente tiene que alinearse con él
// o la lista se cae completa.
//
// REQ-FOLLOWLIST-001 / REQ-FOLLOWLIST-002
describe("follows — listas de seguidores/seguidos", () => {
  /** alice y carol siguen a bob; bob sigue a dave; erin le mandó pending a bob. */
  async function seedGraph() {
    await seedEdge("alice", "bob", "accepted");
    await seedEdge("carol", "bob", "accepted");
    await seedEdge("bob", "dave", "accepted");
    await seedEdge("erin", "bob", "pending");
  }

  it("un tercero lista los SEGUIDORES de otro", async () => {
    await seedGraph();

    const snap = await assertSucceeds(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .where("status", "==", "accepted")
        .get(),
    );
    expect(
      snap.docs.map((d: { id: string }) => d.id).sort(),
    ).toEqual(["alice_bob", "carol_bob"]);
  });

  it("un tercero lista los SEGUIDOS de otro", async () => {
    await seedGraph();

    const snap = await assertSucceeds(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followerUid", "==", "bob")
        .where("status", "==", "accepted")
        .get(),
    );
    expect(snap.docs.map((d: { id: string }) => d.id)).toEqual(["bob_dave"]);
  });

  // El filtro `status == 'accepted'` NO es cosmético ni una optimización: es
  // lo único que impide enumerar las solicitudes pendientes de cualquiera.
  // Sin él la query devolvería la arista de erin y se cae entera — que es
  // exactamente el comportamiento que queremos.
  it("sin el filtro de status, la query de SEGUIDORES se cae entera", async () => {
    await seedGraph();

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .get(),
    );
  });

  it("un tercero no puede enumerar las solicitudes pendientes de otro", async () => {
    await seedGraph();

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .where("status", "==", "pending")
        .get(),
    );
  });

  it("el dueño lista sus propios seguidos", async () => {
    await seedGraph();

    const snap = await assertSucceeds(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .where("followerUid", "==", "bob")
        .where("status", "==", "accepted")
        .get(),
    );
    expect(snap.docs.map((d: { id: string }) => d.id)).toEqual(["bob_dave"]);
  });

  it("un anónimo no lista nada", async () => {
    await seedGraph();

    await assertFails(
      testEnv
        .unauthenticatedContext()
        .firestore()
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .where("status", "==", "accepted")
        .get(),
    );
  });
});

// ── queries que la app ya hacía (regresión) ─────────────────────────────────
//
// Las tres queries de `FollowRepository` que NO son por doc id. Hasta
// `follow-lists` la regla de `read` sólo nombraba `members`, así que dos de
// las tres estaban denegadas en producción: el planner no puede probar
// `uid in resource.data.members` desde un `where` sobre `followerUid` o
// `followeeUid`. El `describe("follows — read")` no lo agarró porque cubría
// únicamente lecturas por doc id.
describe("follows — queries de FollowRepository", () => {
  it("allOf: members array-contains — la única que ya funcionaba", async () => {
    await seedEdge("alice", "bob", "accepted");
    await seedEdge("bob", "dave", "accepted");
    await seedEdge("erin", "bob", "pending");

    const snap = await assertSucceeds(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .where("members", "array-contains", "bob")
        .get(),
    );
    expect(snap.docs.map((d: { id: string }) => d.id).sort()).toEqual([
      "alice_bob",
      "bob_dave",
      "erin_bob",
    ]);
  });

  it("followingOf: followerUid == uid && status == accepted", async () => {
    await seedEdge("bob", "dave", "accepted");

    const snap = await assertSucceeds(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .where("followerUid", "==", "bob")
        .where("status", "==", "accepted")
        .get(),
    );
    expect(snap.docs.map((d: { id: string }) => d.id)).toEqual(["bob_dave"]);
  });

  it("pendingReceivedFor: followeeUid == uid && status == pending", async () => {
    await seedEdge("erin", "bob", "pending");
    await seedEdge("alice", "bob", "accepted");

    const snap = await assertSucceeds(
      asUser("bob")
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .where("status", "==", "pending")
        .get(),
    );
    expect(snap.docs.map((d: { id: string }) => d.id)).toEqual(["erin_bob"]);
  });

  // La contracara del arreglo: que `followeeUid == uid` sea probable NO le da
  // a nadie las solicitudes de OTRO. La disyunción se prueba contra
  // `request.auth.uid`, no contra el valor del filtro.
  it("nadie lista las solicitudes pendientes de otro", async () => {
    await seedEdge("erin", "bob", "pending");

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followeeUid", "==", "bob")
        .where("status", "==", "pending")
        .get(),
    );
  });

  it("nadie lista las solicitudes que OTRO envió", async () => {
    await seedEdge("bob", "erin", "pending");

    await assertFails(
      asUser("mallory")
        .collection(COL_FOLLOWS)
        .where("followerUid", "==", "bob")
        .where("status", "==", "pending")
        .get(),
    );
  });
});
