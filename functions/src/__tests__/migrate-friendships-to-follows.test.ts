/**
 * Tests de las funciones puras detrás de la migración `friendships → follows`.
 * Sin emulador ni Firestore: `planMigration` y `buildApplyManifest` reciben la
 * colección de origen y las aristas ya presentes como estructuras en memoria,
 * que es justamente lo que las hace auditables.
 *
 * Lo que estos tests custodian no es "que ande": es que el script NO PUEDA
 * revertir una decisión del usuario ni dejar la migración a medias reportando
 * éxito. Las dos cosas dependen de la misma guarda (G1) y de que sea
 * ASIMÉTRICA POR MODO — ver el bloque de 2.2c / 2.2c-bis, que son el mismo
 * estado observado con conclusiones opuestas.
 *
 * Contrato: design §7.2. Escenarios: SCENARIO-819/820/825/828/829/830/838.
 */

import {
  buildApplyManifest,
  chunk,
  classifyFriendship,
  expectedEdgeIds,
  isWellFormed,
  planExitCode,
  planMigration,
  type Edge,
  type EdgeData,
  type FollowStatus,
  type FriendshipDoc,
  type TimestampLike,
} from "../../scripts/migrate-friendships-to-follows";

/** Timestamp mínimo: el script solo necesita poder compararlos. */
const at = (ms: number): TimestampLike => ({ toMillis: () => ms });

const T0 = at(1_700_000_000_000); // origen "viejo"
const T1 = at(1_800_000_000_000); // origen "nuevo"

const friendship = (
  id: string,
  requesterId: string,
  members: string[],
  status: string,
  createdAt: TimestampLike | undefined = T0,
): FriendshipDoc => ({
  id,
  data: { requesterId, members, status, createdAt },
});

/** Arista ya presente en `follows` — se usa como ENTRADA, nunca como aserción. */
const edge = (
  f: string,
  t: string,
  status: FollowStatus,
  createdAt: TimestampLike = T0,
): Edge => ({
  id: `${f}_${t}`,
  followerUid: f,
  followeeUid: t,
  status,
  members: [f, t],
  createdAt,
});

const existingFrom = (...edges: EdgeData[]): Map<string, EdgeData> =>
  new Map(edges.map((e) => [e.id as string, e]));

const ids = (edges: Edge[]) => edges.map((e) => e.id).sort();

// ---------------------------------------------------------------------------
// 2.1 — accepted migra a DOS aristas (ADR-FOLLOW-013, SCENARIO-819)
// ---------------------------------------------------------------------------

describe("planMigration · expansión de una amistad accepted", () => {
  it("una accepted migra a DOS aristas, ambas accepted y con el createdAt del origen", () => {
    // Es la decisión que revierte LD-06: con una sola arista, la mitad de las
    // relaciones existentes perdía acceso a los posts del otro el día del flip.
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted")],
      new Map(),
      {},
    );

    expect(plan.toCreate).toEqual([
      {
        id: "u1_u2",
        followerUid: "u1",
        followeeUid: "u2",
        status: "accepted",
        members: ["u1", "u2"],
        createdAt: T0,
      },
      {
        id: "u2_u1",
        followerUid: "u2",
        followeeUid: "u1",
        status: "accepted",
        members: ["u2", "u1"],
        createdAt: T0,
      },
    ]);
    expect(plan.stats).toEqual({
      friendships: 1,
      accepted: 1,
      pending: 0,
      expectedEdges: 2,
    });
  });

  it("la dirección del par accepted no depende de quién fue el requester", () => {
    // Con dos aristas el requester deja de decidir quién ve a quién; sólo
    // sobrevive como orden de emisión. Si esto se rompiera, un accepted
    // migraría asimétrico y alguien perdería acceso en silencio.
    const desdeU1 = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted")],
      new Map(),
      {},
    );
    const desdeU2 = planMigration(
      [friendship("u1_u2", "u2", ["u1", "u2"], "accepted")],
      new Map(),
      {},
    );

    expect(ids(desdeU1.toCreate)).toEqual(["u1_u2", "u2_u1"]);
    expect(ids(desdeU2.toCreate)).toEqual(["u1_u2", "u2_u1"]);
  });
});

// ---------------------------------------------------------------------------
// 2.1b — pending migra a UNA sola arista (SCENARIO-825)
// ---------------------------------------------------------------------------

describe("planMigration · expansión de una amistad pending", () => {
  it("una pending migra a UNA sola arista requester → otro, y la inversa NO se crea", () => {
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "pending")],
      new Map(),
      {},
    );

    expect(plan.toCreate).toEqual([
      {
        id: "u1_u2",
        followerUid: "u1",
        followeeUid: "u2",
        status: "pending",
        members: ["u1", "u2"],
        createdAt: T0,
      },
    ]);
    expect(plan.toCreate.some((e) => e.id === "u2_u1")).toBe(false);
    expect(plan.stats.expectedEdges).toBe(1);
  });

  it("la dirección de la pending sale de requesterId, no del orden de members", () => {
    // `friendships/{min}_{max}` está ordenado alfabéticamente, así que el orden
    // de `members` NO dice quién pidió. Inferirlo de ahí invierte solicitudes.
    const plan = planMigration(
      [friendship("u1_u2", "u2", ["u1", "u2"], "pending")],
      new Map(),
      {},
    );

    expect(ids(plan.toCreate)).toEqual(["u2_u1"]);
  });
});

// ---------------------------------------------------------------------------
// 2.2 — malformados: se enumeran y se excluyen (SCENARIO-820)
// ---------------------------------------------------------------------------

describe("planMigration · documentos malformados", () => {
  it("enumera nominalmente cada clase de malformado y no planifica ni una arista", () => {
    // NUNCA se adivina la dirección: sin requesterId confiable no hay arista
    // posible, y una arista mal dirigida es peor que una relación no migrada.
    const plan = planMigration(
      [
        {
          id: "sin-requester",
          data: { members: ["a", "b"], status: "accepted", createdAt: T0 },
        },
        friendship("un-solo-miembro", "a", ["a"], "accepted"),
        friendship("tres-miembros", "a", ["a", "b", "c"], "accepted"),
        friendship("requester-afuera", "z", ["a", "b"], "accepted"),
        friendship("status-raro", "a", ["a", "b"], "blocked"),
        friendship("self-pair", "a", ["a", "a"], "accepted"),
        // Sin `createdAt` no hay arista migrable: escribirla con `undefined`
        // lo rechaza Firestore, y escribirla con el reloj del script rompe la
        // reproducibilidad de una re-migración (ADR-FOLLOW-014).
        {
          id: "sin-createdAt",
          data: { requesterId: "a", members: ["a", "b"], status: "accepted" },
        },
      ],
      new Map(),
      {},
    );

    expect(plan.toCreate).toEqual([]);
    expect(plan.malformed.map((m) => m.docId)).toEqual([
      "sin-requester",
      "un-solo-miembro",
      "tres-miembros",
      "requester-afuera",
      "status-raro",
      "self-pair",
      "sin-createdAt",
    ]);
    // El motivo se imprime en el reporte y lo lee un humano: tiene que decir
    // QUÉ está mal, no "malformado".
    expect(plan.malformed.map((m) => m.reason)).toEqual([
      "sin-requesterId",
      "members-no-es-par",
      "members-no-es-par",
      "requesterId-fuera-de-members",
      "status-invalido",
      "self-pair",
      "createdAt-ausente-o-invalido",
    ]);
  });

  it("un malformado no contamina las stats ni bloquea a los bien formados", () => {
    // La cardinalidad de la verificación (V1) se cuenta SOLO sobre bien
    // formadas: los malformados quedan fuera del universo, no se restan.
    const plan = planMigration(
      [
        friendship("ok-acc", "a", ["a", "b"], "accepted"),
        friendship("ok-pend", "c", ["c", "d"], "pending"),
        friendship("roto", "z", ["e", "f"], "accepted"),
      ],
      new Map(),
      {},
    );

    expect(ids(plan.toCreate)).toEqual(["a_b", "b_a", "c_d"]);
    expect(plan.stats).toEqual({
      friendships: 3,
      accepted: 1,
      pending: 1,
      expectedEdges: 3,
    });
    expect(plan.malformed).toEqual([
      { docId: "roto", reason: "requesterId-fuera-de-members" },
    ]);
  });

  it("`expectedEdgeIds` sólo devuelve ids de bien formadas — es lo que se lee con getAll()", () => {
    const docIds = expectedEdgeIds([
      friendship("ok-acc", "a", ["a", "b"], "accepted"),
      friendship("roto", "z", ["e", "f"], "accepted"),
      friendship("ok-pend", "c", ["c", "d"], "pending"),
    ]);

    expect(docIds).toEqual(["a_b", "b_a", "c_d"]);
  });

  it("`isWellFormed` y `classifyFriendship` son el predicado que importa la verificación", () => {
    // El script de verificación IMPORTA esto en vez de reimplementarlo: si los
    // dos criterios divergen, la verificación deja de verificar.
    expect(
      isWellFormed({
        requesterId: "a",
        members: ["a", "b"],
        status: "accepted",
        createdAt: T0,
      }),
    ).toBe(true);
    expect(isWellFormed({ members: ["a", "b"], status: "accepted" })).toBe(
      false,
    );

    expect(
      classifyFriendship({
        requesterId: "b",
        members: ["a", "b"],
        status: "pending",
        createdAt: T0,
      }),
    ).toEqual({
      wellFormed: true,
      requesterId: "b",
      otherUid: "a",
      status: "pending",
      createdAt: T0,
    });
  });
});

// ---------------------------------------------------------------------------
// 2.2b — idempotencia sobre un estado COMPLETO (SCENARIO-828)
// ---------------------------------------------------------------------------

describe("planMigration · idempotencia sobre un estado completo", () => {
  it("segunda corrida sobre un estado completo: 0 aristas a crear, 0 writes, exit 0", () => {
    const friendships = [
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
      friendship("u3_u4", "u3", ["u3", "u4"], "pending"),
    ];
    const existing = existingFrom(
      edge("u1", "u2", "accepted"),
      edge("u2", "u1", "accepted"),
      edge("u3", "u4", "pending"),
    );

    const plan = planMigration(friendships, existing, {});

    expect(plan.toCreate).toEqual([]);
    expect(plan.partialPair).toEqual([]);
    expect(plan.divergent).toEqual([]);
    expect(plan.skippedPair).toEqual([
      { pairId: "u1_u2", reason: "already-migrated" },
      { pairId: "u3_u4", reason: "already-migrated" },
    ]);
    expect(planExitCode(plan, {})).toBe(0);
  });

  it("también es no-op con --since, que es el caso normal del delta sweep", () => {
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted")],
      existingFrom(edge("u1", "u2", "accepted"), edge("u2", "u1", "accepted")),
      { since: new Date(T1.toMillis()) },
    );

    expect(plan.toCreate).toEqual([]);
    expect(planExitCode(plan, { since: new Date(T1.toMillis()) })).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2.2c / 2.2c-bis — G1 ASIMÉTRICA POR MODO
//
// Misma fixture exacta, conclusión opuesta. NO consolidar estos dos tests:
// son el contrapunto que documenta que "falta una dirección" significa cosas
// distintas a los dos lados del flip. Ver design §7.2 G1.
// ---------------------------------------------------------------------------

/** `accepted {u1,u2}` con SOLO la arista u1→u2 presente. */
const parAMedias = () => ({
  friendships: [friendship("u1_u2", "u1", ["u1", "u2"], "accepted")],
  existing: existingFrom(edge("u1", "u2", "accepted")),
});

describe("planMigration · G1 con --since (delta sweep post-flip)", () => {
  it("no resucita la dirección faltante: el par entero va a skippedPair", () => {
    // SCENARIO-829. Después del flip, que falte `u2_u1` significa que u2 dejó
    // de seguir a u1. Recrearla revertiría una decisión de privacidad — la
    // peor falla posible según LD-04.
    const { friendships, existing } = parAMedias();
    const since = new Date(T1.toMillis());

    const plan = planMigration(friendships, existing, { since });

    expect(plan.toCreate).toEqual([]);
    expect(plan.skippedPair).toEqual([
      { pairId: "u1_u2", reason: "already-migrated" },
    ]);
    expect(plan.partialPair).toEqual([]);
    expect(planExitCode(plan, { since })).toBe(0);
  });
});

describe("planMigration · G1 sin --since (corrida inicial / reintento)", () => {
  it("completa la dirección faltante y grita por partialPair, con exit 0", () => {
    // SCENARIO-838. Un batch de 400 que muere después de commitear `u1_u2`.
    // Acá `follows` es 100% producto de la migración y el cliente que produce
    // unfollows (PR3c) ni siquiera está publicado: una dirección faltante NO
    // PUEDE ser un unfollow, es una escritura que no llegó a ocurrir.
    //
    // Sin esta asimetría el reintento reportaría "ya migrado" y saldría exit 0
    // con la migración a medias.
    const { friendships, existing } = parAMedias();

    const plan = planMigration(friendships, existing, {});

    expect(ids(plan.toCreate)).toEqual(["u2_u1"]);
    expect(plan.toCreate[0]).toEqual({
      id: "u2_u1",
      followerUid: "u2",
      followeeUid: "u1",
      status: "accepted",
      members: ["u2", "u1"],
      createdAt: T0,
    });
    expect(plan.partialPair).toEqual([
      { pairId: "u1_u2", present: ["u1_u2"], created: ["u2_u1"] },
    ]);
    expect(plan.skippedPair).toEqual([]);
    expect(planExitCode(plan, {})).toBe(0);
  });

  it("la arista ya presente NO se toca: sólo se planifica la faltante", () => {
    const { friendships, existing } = parAMedias();

    const plan = planMigration(friendships, existing, {});

    expect(plan.toCreate.some((e) => e.id === "u1_u2")).toBe(false);
    expect(plan.divergent).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// G3 — conflicto: par sin aristas y anterior a --since
// ---------------------------------------------------------------------------

describe("planMigration · G3 conflictos (solo con --since)", () => {
  it("par con CERO aristas cuyo origen es anterior a --since → conflicto, exit 1", () => {
    // Los dos se dejaron de seguir después del flip. Escribir a ciegas acá
    // resucitaría el par entero; necesita ojo humano.
    const since = new Date(T1.toMillis());
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted", T0)],
      new Map(),
      { since },
    );

    expect(plan.toCreate).toEqual([]);
    expect(plan.conflicts).toEqual([
      { pairId: "u1_u2", reason: "no-edges-and-older-than-since" },
    ]);
    expect(planExitCode(plan, { since })).toBe(1);
  });

  it("par con CERO aristas cuyo origen es posterior a --since sí se migra", () => {
    // Amistad escrita durante la ventana: es lo único que el sweep existe para
    // absorber.
    const since = new Date(T0.toMillis());
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted", T1)],
      new Map(),
      { since },
    );

    expect(ids(plan.toCreate)).toEqual(["u1_u2", "u2_u1"]);
    expect(plan.conflicts).toEqual([]);
  });

  it("sin --since, cero aristas es lo normal: no hay conflicto posible", () => {
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted", T0)],
      new Map(),
      {},
    );

    expect(plan.conflicts).toEqual([]);
    expect(ids(plan.toCreate)).toEqual(["u1_u2", "u2_u1"]);
  });
});

// ---------------------------------------------------------------------------
// 2.2d — G2 divergencia: se reporta, nunca se pisa (SCENARIO-830)
// ---------------------------------------------------------------------------

describe("planMigration · G2 divergencia", () => {
  it("status distinto del esperado: se reporta, no se pisa, exit 1 SIN --since", () => {
    // `follows/u1_u2` accepted contra un origen pending. Sin --since nadie
    // tocó `follows` todavía, así que esto es corrida anterior corrupta.
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "pending")],
      existingFrom(edge("u1", "u2", "accepted")),
      {},
    );

    expect(plan.toCreate).toEqual([]);
    expect(plan.divergent).toEqual([
      {
        edgeId: "u1_u2",
        expected: { status: "pending" },
        actual: { status: "accepted" },
      },
    ]);
    expect(planExitCode(plan, {})).toBe(1);
  });

  it("la MISMA divergencia con --since es warning, exit 0", () => {
    // Post-flip es actividad legítima: el followee aceptó la solicitud
    // migrada. `follows` es más nueva que la `friendships` congelada.
    const since = new Date(T1.toMillis());
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "pending")],
      existingFrom(edge("u1", "u2", "accepted")),
      { since },
    );

    expect(plan.divergent).toHaveLength(1);
    expect(plan.toCreate).toEqual([]);
    expect(planExitCode(plan, { since })).toBe(0);
  });

  it("createdAt reemplazado por el reloj del script se reporta como divergencia", () => {
    // Es la falla que rompe la reproducibilidad de una re-migración: si
    // `createdAt` sale de `now()`, borrar `follows` y volver a correr NO
    // produce el mismo estado.
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted", T0)],
      existingFrom(
        edge("u1", "u2", "accepted", T1),
        edge("u2", "u1", "accepted", T0),
      ),
      {},
    );

    expect(plan.divergent).toEqual([
      {
        edgeId: "u1_u2",
        expected: { createdAt: T0 },
        actual: { createdAt: T1 },
      },
    ]);
    expect(plan.toCreate).toEqual([]);
  });

  it("members mal derivado (orden invertido) se reporta como divergencia", () => {
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "pending")],
      existingFrom({
        id: "u1_u2",
        followerUid: "u1",
        followeeUid: "u2",
        status: "pending",
        members: ["u2", "u1"],
        createdAt: T0,
      }),
      {},
    );

    expect(plan.divergent).toEqual([
      {
        edgeId: "u1_u2",
        expected: { members: ["u1", "u2"] },
        actual: { members: ["u2", "u1"] },
      },
    ]);
  });

  it("una divergencia en un par PARCIAL también se reporta, y no frena a la faltante", () => {
    // Si sólo se mirara la divergencia de los pares completos, una arista
    // corrupta se escaparía nada más que porque su hermana no llegó a
    // escribirse — que es exactamente el estado de un batch interrumpido.
    const plan = planMigration(
      [friendship("u1_u2", "u1", ["u1", "u2"], "accepted", T0)],
      existingFrom(edge("u1", "u2", "accepted", T1)),
      {},
    );

    expect(ids(plan.toCreate)).toEqual(["u2_u1"]);
    expect(plan.divergent.map((d) => d.edgeId)).toEqual(["u1_u2"]);
    expect(planExitCode(plan, {})).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Corrida realista — la aserción concreta que fijó M-00
// ---------------------------------------------------------------------------

describe("planMigration · forma de la corrida real de treino-dev", () => {
  it("4 accepted + 2 pending + 0 malformados producen exactamente 10 aristas", () => {
    // M-00 midió esto contra `treino-dev`: 6 friendships entre 8 uids.
    // 2×4 + 2 == 10 es el número que después tiene que dar V1.
    const friendships = [
      friendship("a_b", "a", ["a", "b"], "accepted"),
      friendship("c_d", "c", ["c", "d"], "accepted"),
      friendship("e_f", "f", ["e", "f"], "accepted"),
      friendship("g_h", "g", ["g", "h"], "accepted"),
      friendship("a_c", "a", ["a", "c"], "pending"),
      friendship("b_h", "h", ["b", "h"], "pending"),
    ];

    const plan = planMigration(friendships, new Map(), {});

    expect(plan.stats).toEqual({
      friendships: 6,
      accepted: 4,
      pending: 2,
      expectedEdges: 10,
    });
    expect(plan.toCreate).toHaveLength(10);
    expect(plan.malformed).toEqual([]);
    expect(new Set(ids(plan.toCreate)).size).toBe(10); // sin ids repetidos
    expect(planExitCode(plan, {})).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2.3a — buildApplyManifest
// ---------------------------------------------------------------------------

describe("buildApplyManifest", () => {
  const APPLIED_AT = "2026-08-04T18:00:00.000Z";

  const planDeEjemplo = () =>
    planMigration(
      [
        friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
        friendship("u3_u4", "u3", ["u3", "u4"], "pending"),
      ],
      new Map(),
      {},
    );

  it("los Edge de `created` van COMPLETOS, no como lista de ids", () => {
    // `verify --delta --manifest` compara status/createdAt/dirección contra
    // esto SIN volver a leer `friendships`. Con solo ids no puede.
    const plan = planDeEjemplo();

    const manifest = buildApplyManifest(plan.toCreate, plan, {
      appliedAt: APPLIED_AT,
    });

    expect(manifest.created).toEqual([
      {
        id: "u1_u2",
        followerUid: "u1",
        followeeUid: "u2",
        status: "accepted",
        members: ["u1", "u2"],
        createdAt: T0,
      },
      {
        id: "u2_u1",
        followerUid: "u2",
        followeeUid: "u1",
        status: "accepted",
        members: ["u2", "u1"],
        createdAt: T0,
      },
      {
        id: "u3_u4",
        followerUid: "u3",
        followeeUid: "u4",
        status: "pending",
        members: ["u3", "u4"],
        createdAt: T0,
      },
    ]);
  });

  it("`created` refleja lo EFECTIVAMENTE escrito, no lo planificado", () => {
    // Ante ALREADY_EXISTS el batch se re-planifica doc a doc: lo escrito puede
    // ser un subconjunto de `toCreate`. El manifiesto es evidencia, no plan.
    const plan = planDeEjemplo();
    const escritas = plan.toCreate.filter((e) => e.id !== "u3_u4");

    const manifest = buildApplyManifest(escritas, plan, {
      appliedAt: APPLIED_AT,
    });

    expect(manifest.created.map((e) => e.id)).toEqual(["u1_u2", "u2_u1"]);
  });

  it("arrastra skippedPair, partialPair, divergent, conflicts y malformed del plan", () => {
    const plan = planMigration(
      [
        friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
        friendship("u5_u6", "u5", ["u5", "u6"], "pending"),
        friendship("roto", "z", ["u7", "u8"], "accepted"),
      ],
      existingFrom(
        edge("u1", "u2", "accepted"),
        edge("u5", "u6", "accepted"), // divergente contra un origen pending
      ),
      {},
    );

    const manifest = buildApplyManifest(plan.toCreate, plan, {
      appliedAt: APPLIED_AT,
    });

    expect(manifest.partialPair).toEqual([
      { pairId: "u1_u2", present: ["u1_u2"], created: ["u2_u1"] },
    ]);
    expect(manifest.skippedPair).toEqual([
      { pairId: "u5_u6", reason: "already-migrated" },
    ]);
    expect(manifest.divergent).toEqual([
      {
        edgeId: "u5_u6",
        expected: { status: "pending" },
        actual: { status: "accepted" },
      },
    ]);
    expect(manifest.conflicts).toEqual([]);
    expect(manifest.malformed).toEqual([
      { docId: "roto", reason: "requesterId-fuera-de-members" },
    ]);
  });

  it("`since` es null en la corrida inicial y el ISO exacto en el delta sweep", () => {
    // Es lo que distingue `apply-{ISO}.json` de `delta-{ISO}.json` cuando
    // alguien mira el archivo seis meses después.
    const plan = planDeEjemplo();
    const since = new Date("2026-08-04T15:13:08.855Z");

    expect(buildApplyManifest([], plan, { appliedAt: APPLIED_AT }).since).toBe(
      null,
    );
    expect(
      buildApplyManifest([], plan, { appliedAt: APPLIED_AT, since }).since,
    ).toBe("2026-08-04T15:13:08.855Z");
  });

  it("`appliedAt` por defecto es ahora, en ISO", () => {
    const manifest = buildApplyManifest([], planDeEjemplo(), {});

    expect(manifest.appliedAt).toMatch(/^\d{4}-\d{2}-\d{2}T[\d:.]+Z$/);
  });

  it("no muta el plan que recibe", () => {
    const plan = planDeEjemplo();
    const antes = JSON.stringify(plan.toCreate.map((e) => e.id));

    buildApplyManifest(plan.toCreate, plan, { appliedAt: APPLIED_AT });

    expect(JSON.stringify(plan.toCreate.map((e) => e.id))).toBe(antes);
  });
});

// ---------------------------------------------------------------------------
// chunk() — sostiene la lectura por doc id con getAll() en tandas de 300
// ---------------------------------------------------------------------------

describe("chunk", () => {
  it("parte en tandas del tamaño pedido sin perder ni repetir elementos", () => {
    const arr = Array.from({ length: 7 }, (_, i) => i);

    expect(chunk(arr, 3)).toEqual([[0, 1, 2], [3, 4, 5], [6]]);
    expect(chunk([], 300)).toEqual([]);
    expect(chunk(arr, 300)).toEqual([arr]);
  });
});
