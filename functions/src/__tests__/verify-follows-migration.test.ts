/**
 * Tests de la verificación de la migración `friendships → follows` (M-06).
 * Sin emulador: `verifyMigration` recibe las tres colecciones como estructuras
 * en memoria, que es lo que permite INYECTAR la falla y probar que la atrapa.
 *
 * Lo que estos tests custodian es la compuerta de cutover. Una verificación que
 * pasa cuando no debería es peor que no tenerla: autoriza un flip de rules con
 * el grafo social roto, y la falla se manifiesta como phantom access o como
 * feed en blanco, días después, en producción.
 *
 * Dos cosas que NO se pueden aflojar acá:
 *
 * 1. La cardinalidad es `2 × accepted BIEN FORMADAS + pending BIEN FORMADAS`.
 *    Los malformados se EXCLUYEN del universo, no se restan del resultado. La
 *    forma restada es aritméticamente falsa y —peor— falla en las dos
 *    direcciones a la vez, así que puede dar bien por casualidad. Lo ancla
 *    `V1 · excluir no es restar`.
 * 2. Se evalúan TODAS las invariantes del modo. Un reporte que corta en la
 *    primera obliga al operador a iterar a ciegas contra la base.
 *
 * Contrato: design §7.3 y §7.3.1. Escenarios: SCENARIO-818/821/824/826/827/846.
 */

import {
  planMigration,
  type ApplyManifest,
  type FriendshipDoc,
  type TimestampLike,
} from "../../scripts/migrate-friendships-to-follows";
import {
  reportExitCode,
  timestampMillis,
  verifyMigration,
  type FollowDoc,
  type InvariantId,
  type ProfileDoc,
  type VerifyReport,
} from "../../scripts/verify-follows-migration";

/** Timestamp mínimo: sólo hace falta poder compararlos. */
const at = (ms: number): TimestampLike => ({ toMillis: () => ms });

const T0 = at(1_700_000_000_000);
const T1 = at(1_800_000_000_000);

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

const followDoc = (
  f: string,
  t: string,
  status: string,
  createdAt: TimestampLike = T0,
): FollowDoc => ({
  id: `${f}_${t}`,
  data: {
    id: `${f}_${t}`,
    followerUid: f,
    followeeUid: t,
    status,
    members: [f, t],
    createdAt,
  },
});

/**
 * Aristas que la migración produce para estas friendships. Sale de
 * `planMigration` —el otro script, ya testeado— y NO del verificador: si el
 * mundo sano lo armara el propio código bajo prueba, el test sería tautológico.
 */
const followsDe = (friendships: FriendshipDoc[]): FollowDoc[] =>
  planMigration(friendships, new Map(), {}).toCreate.map((e) => ({
    id: e.id,
    data: {
      id: e.id,
      followerUid: e.followerUid,
      followeeUid: e.followeeUid,
      status: e.status,
      members: [...e.members],
      createdAt: e.createdAt,
    },
  }));

/** Contadores que resultan de esas aristas. Tally local, independiente del script. */
const perfilesDe = (follows: FollowDoc[]): ProfileDoc[] => {
  const t = new Map<string, { followers: number; following: number }>();
  const asegurar = (uid: string) => {
    if (!t.has(uid)) t.set(uid, { followers: 0, following: 0 });
    return t.get(uid) as { followers: number; following: number };
  };

  for (const f of follows) {
    const follower = f.data.followerUid as string;
    const followee = f.data.followeeUid as string;
    asegurar(follower);
    asegurar(followee);
    if (f.data.status !== "accepted") continue;
    asegurar(follower).following += 1;
    asegurar(followee).followers += 1;
  }

  return [...t].map(([id, v]) => ({
    id,
    followersCount: v.followers,
    followingCount: v.following,
  }));
};

/** Mundo consistente: migración completa y contadores ya recalculados (M-05). */
const mundoSano = (friendships: FriendshipDoc[]) => {
  const follows = followsDe(friendships);
  return { friendships, follows, profiles: perfilesDe(follows) };
};

const verificar = (input: {
  friendships: FriendshipDoc[];
  follows: FollowDoc[];
  profiles: ProfileDoc[];
}): VerifyReport => verifyMigration(input, { mode: "cutover" });

/** Invariantes violadas, sin repetir y ordenadas — la aserción más legible. */
const violadas = (r: VerifyReport): InvariantId[] =>
  [...new Set(r.violations.map((v) => v.invariant))].sort();

const ofensores = (r: VerifyReport, inv: InvariantId): string[] =>
  r.violations
    .filter((v) => v.invariant === inv)
    .flatMap((v) => v.offenders)
    .sort();

// ---------------------------------------------------------------------------
// 2.4 — V1 cardinalidad (SCENARIO-818) y V4 arista inventada (SCENARIO-824)
// ---------------------------------------------------------------------------

describe("V1 · cardinalidad", () => {
  /** 40 accepted + 10 pending bien formadas + 2 malformadas → 90 aristas. */
  const universoDeScenario818 = (): FriendshipDoc[] => {
    const out: FriendshipDoc[] = [];
    for (let i = 0; i < 40; i++) {
      out.push(friendship(`acc-${i}`, `a${i}`, [`a${i}`, `b${i}`], "accepted"));
    }
    for (let i = 0; i < 10; i++) {
      out.push(friendship(`pen-${i}`, `p${i}`, [`p${i}`, `q${i}`], "pending"));
    }
    out.push(friendship("mal-1", "zz", ["m1", "m2"], "accepted"));
    out.push({ id: "mal-2", data: { members: ["m3", "m4"], status: "pending" } });
    return out;
  };

  it("la fórmula es 2 × accepted bien formadas + pending bien formadas", () => {
    const { friendships, follows, profiles } = mundoSano(
      universoDeScenario818(),
    );

    const r = verificar({ friendships, follows, profiles });

    expect(r.stats.accepted).toBe(40);
    expect(r.stats.pending).toBe(10);
    expect(r.stats.malformed).toBe(2);
    expect(r.stats.expectedEdges).toBe(90); // 2×40 + 10
    expect(r.stats.follows).toBe(90);
    expect(reportExitCode(r)).toBe(0);
  });

  it("una arista de menos hace fallar la verificación (SCENARIO-818)", () => {
    const { friendships, follows, profiles } = mundoSano(
      universoDeScenario818(),
    );
    // Se saca una `pending`: no mueve contadores, así que aísla la
    // cardinalidad y la cobertura direccional de todo lo demás.
    const rotas = follows.filter((f) => f.id !== "p0_q0");

    const r = verificar({ friendships, follows: rotas, profiles });

    expect(violadas(r)).toEqual(["V1", "V3"]);
    expect(r.stats.expectedEdges).toBe(90);
    expect(r.stats.follows).toBe(89);
    // El reporte tiene que decir los DOS números: "no cierra" no es accionable.
    const v1 = r.violations.find((v) => v.invariant === "V1");
    expect(v1?.message).toContain("90");
    expect(v1?.message).toContain("89");
    expect(reportExitCode(r)).toBe(1);
  });

  it("una arista inventada, sin friendship de origen, falla por V4 (SCENARIO-824)", () => {
    const { friendships, follows, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);

    const r = verificar({
      friendships,
      follows: [...follows, followDoc("u9", "u8", "accepted")],
      profiles,
    });

    expect(violadas(r)).toEqual(["V1", "V4"]);
    expect(ofensores(r, "V4")).toEqual(["u9_u8"]);
    // u8/u9 tienen aristas pero no tienen perfil: es WARNING, no error — misma
    // política que la CF y el backfill (no se resucita el perfil de una cuenta
    // borrada). Lo que hace fallar es V4, no la falta de perfil.
    expect(r.warnings.filter((w) => w.kind === "missing-profile")).toHaveLength(
      2,
    );
    expect(reportExitCode(r)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// 2.4b — excluir NO es restar
// ---------------------------------------------------------------------------

describe("V1 · excluir no es restar", () => {
  // La fórmula falsa `2×accepted + pending − malformados` falla en las DOS
  // direcciones y por eso puede dar bien por casualidad. Cada caso de acá
  // aísla una de las dos.

  it("una accepted malformada NO se resta: se excluye del universo (sobre-cuenta)", () => {
    // Con la fórmula restada: 2×4 + 1 − 1 = 8 ≠ 7. Sobra una arista por cada
    // `accepted` malformada, porque restarle 1 no alcanza para sacarle las DOS
    // aristas que nunca se planificaron.
    const friendships = [
      friendship("ok-1", "a1", ["a1", "b1"], "accepted"),
      friendship("ok-2", "a2", ["a2", "b2"], "accepted"),
      friendship("ok-3", "a3", ["a3", "b3"], "accepted"),
      friendship("ok-p", "c1", ["c1", "d1"], "pending"),
      friendship("mal-acc", "zz", ["m1", "m2"], "accepted"), // requesterId ∉ members
    ];
    const { follows, profiles } = mundoSano(friendships);

    const r = verificar({ friendships, follows, profiles });

    expect(r.stats.accepted).toBe(3); // bien formadas, la malformada no entra
    expect(r.stats.expectedEdges).toBe(7); // 2×3 + 1
    expect(follows).toHaveLength(7);
    expect(violadas(r)).toEqual([]);
    expect(reportExitCode(r)).toBe(0);
  });

  it("una malformada por status inválido tampoco se resta (sub-cuenta)", () => {
    // No está en `count(accepted)` ni en `count(pending)`, así que la fórmula
    // restada le sacaría una arista que nunca sumó: 2×3 + 1 − 1 = 6 ≠ 7.
    const friendships = [
      friendship("ok-1", "a1", ["a1", "b1"], "accepted"),
      friendship("ok-2", "a2", ["a2", "b2"], "accepted"),
      friendship("ok-3", "a3", ["a3", "b3"], "accepted"),
      friendship("ok-p", "c1", ["c1", "d1"], "pending"),
      friendship("mal-status", "m1", ["m1", "m2"], "blocked"),
    ];
    const { follows, profiles } = mundoSano(friendships);

    const r = verificar({ friendships, follows, profiles });

    expect(r.stats.expectedEdges).toBe(7);
    expect(reportExitCode(r)).toBe(0);
  });

  it("los malformados se enumeran nominalmente como warning, con su motivo", () => {
    const friendships = [
      friendship("ok-1", "a1", ["a1", "b1"], "accepted"),
      friendship("mal-acc", "zz", ["m1", "m2"], "accepted"),
    ];
    const { follows, profiles } = mundoSano(friendships);

    const r = verificar({ friendships, follows, profiles });

    expect(r.warnings).toContainEqual({
      kind: "malformed-friendship",
      id: "mal-acc",
      detail: "requesterId-fuera-de-members",
    });
    expect(reportExitCode(r)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// 2.5 — falta una de las dos direcciones de un accepted (SCENARIO-821)
// ---------------------------------------------------------------------------

describe("V2 / V6a · cobertura de accepted", () => {
  it("falta una dirección: lo atrapan V2 y V6a por separado", () => {
    const { friendships, follows, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);
    const rotas = follows.filter((f) => f.id !== "u2_u1");

    const r = verificar({ friendships, follows: rotas, profiles });

    // Cuatro invariantes independientes marcan la MISMA arista faltante. Esa
    // redundancia es deliberada: ninguna clase de falla depende de un solo
    // chequeo (design §7.3, tabla de cobertura).
    expect(violadas(r)).toEqual(["V1", "V2", "V6a", "V6b"]);
    expect(ofensores(r, "V2")).toEqual(["u2_u1"]);
    // followingRecalc(u2)=0 pero deg(u2)=1, y followersRecalc(u1)=0 con
    // deg(u1)=1: una arista faltante produce DOS violaciones de V6a.
    expect(ofensores(r, "V6a")).toEqual(["u1", "u2"]);
    expect(reportExitCode(r)).toBe(1);
  });

  it("faltan las dos direcciones: sigue siendo error, no un par ausente silencioso", () => {
    const { friendships, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);

    const r = verificar({ friendships, follows: [], profiles });

    expect(violadas(r)).toEqual(["V1", "V2", "V6a", "V6b"]);
    expect(ofensores(r, "V2")).toEqual(["u1_u2", "u2_u1"]);
    expect(reportExitCode(r)).toBe(1);
  });

  it("status alterado en una de las dos aristas: V2 lo marca", () => {
    const { friendships, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);
    const follows = [
      followDoc("u1", "u2", "accepted"),
      followDoc("u2", "u1", "pending"), // se degradó
    ];

    const r = verificar({ friendships, follows, profiles });

    expect(violadas(r)).toContain("V2");
    expect(ofensores(r, "V2")).toContain("u2_u1");
    expect(reportExitCode(r)).toBe(1);
  });

  it("createdAt reemplazado por el reloj del script: V2 lo marca", () => {
    // Rompe la reproducibilidad de una re-migración (ADR-FOLLOW-014): borrar
    // `follows` y volver a correr ya no produce el mismo estado.
    const { friendships, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);
    const follows = [
      followDoc("u1", "u2", "accepted", T1), // el origen es T0
      followDoc("u2", "u1", "accepted", T0),
    ];

    const r = verificar({ friendships, follows, profiles });

    expect(violadas(r)).toEqual(["V2"]);
    expect(ofensores(r, "V2")).toEqual(["u1_u2"]);
  });
});

// ---------------------------------------------------------------------------
// 2.5b — pending con la dirección invertida (SCENARIO-826)
// ---------------------------------------------------------------------------

describe("V3 / V4 · dirección de las pending", () => {
  it("una pending invertida se atrapa AUNQUE los contadores no se muevan", () => {
    // Es el caso que prueba que la verificación no se apoya en los contadores:
    // las pending no suman ni restan, así que V6 no la ve. Si el chequeo
    // direccional no existiera, una solicitud invertida —X le pidió a Y y
    // queda como si Y le hubiera pedido a X— pasaría la compuerta entera.
    const friendships = [friendship("u1_u2", "u1", ["u1", "u2"], "pending")];
    const follows = [followDoc("u2", "u1", "pending")];

    const r = verificar({
      friendships,
      follows,
      profiles: perfilesDe(follows),
    });

    expect(violadas(r)).toEqual(["V3", "V4"]);
    // V3 por partida doble: falta la arista legal y sobra la inversa.
    expect(ofensores(r, "V3")).toEqual(["u1_u2", "u2_u1"]);
    // V4 porque `u2_u1` no es una dirección legal para un origen pending cuyo
    // requester es u1.
    expect(ofensores(r, "V4")).toEqual(["u2_u1"]);
    expect(reportExitCode(r)).toBe(1);
  });

  it("una pending correcta no dispara nada, y la inversa sigue ausente", () => {
    const { friendships, follows, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "pending"),
    ]);

    const r = verificar({ friendships, follows, profiles });

    expect(follows.map((f) => f.id)).toEqual(["u1_u2"]);
    expect(violadas(r)).toEqual([]);
    expect(reportExitCode(r)).toBe(0);
  });

  it("una pending migrada como accepted rompe V2/V3 y V4 a la vez", () => {
    const friendships = [friendship("u1_u2", "u1", ["u1", "u2"], "pending")];
    const follows = [followDoc("u1", "u2", "accepted")];

    const r = verificar({
      friendships,
      follows,
      profiles: perfilesDe(follows),
    });

    expect(violadas(r)).toContain("V3");
    expect(violadas(r)).toContain("V4");
    expect(reportExitCode(r)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// 2.5c — contadores sin recalcular (SCENARIO-827)
// ---------------------------------------------------------------------------

describe("V6b · contadores almacenados contra recalculados", () => {
  it("contadores pre-migración hacen fallar la verificación", () => {
    // Los valores viejos salían del split por `requesterId`: el requester
    // contaba como "siguiendo" y el otro como "seguidor", nunca los dos. Con
    // follow mutuo los DOS suben, y ése es el único cambio visible de la
    // migración (§7.4) — pero sólo si M-05 corrió.
    const { friendships, follows } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);
    const perfilesViejos: ProfileDoc[] = [
      { id: "u1", followersCount: 0, followingCount: 1 },
      { id: "u2", followersCount: 1, followingCount: 0 },
    ];

    const r = verificar({ friendships, follows, profiles: perfilesViejos });

    // Sólo V6b: la migración está perfecta, lo que falta es correr M-05. El
    // reporte tiene que decir exactamente eso y no ensuciar con nada más.
    expect(violadas(r)).toEqual(["V6b"]);
    expect(ofensores(r, "V6b")).toEqual(["u1", "u2"]);
    expect(reportExitCode(r)).toBe(1);
  });

  it("un contador almacenado de más, sin aristas que lo respalden, también falla", () => {
    // Residuo típico del cascade de borrado de cuenta (§7.1.2): la CF vieja
    // recomputó sobre `friendships` y dejó el par desincronizado.
    const { friendships, follows, profiles } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);
    const inflados = profiles.map((p) =>
      p.id === "u1" ? { ...p, followersCount: 7 } : p,
    );

    const r = verificar({ friendships, follows, profiles: inflados });

    expect(violadas(r)).toEqual(["V6b"]);
    expect(ofensores(r, "V6b")).toEqual(["u1"]);
  });

  it("un uid con aristas pero sin perfil es warning, no error", () => {
    const { friendships, follows } = mundoSano([
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
    ]);

    const r = verificar({ friendships, follows, profiles: [] });

    expect(violadas(r)).toEqual([]);
    expect(r.warnings.map((w) => w.id).sort()).toEqual(["u1", "u2"]);
    expect(r.warnings.every((w) => w.kind === "missing-profile")).toBe(true);
    expect(reportExitCode(r)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// V5 — forma del doc. Es gratis en la misma pasada y atrapa lo que ninguna
// otra invariante ve: un `members` mal derivado no mueve contadores, no rompe
// cardinalidad y tiene origen legítimo.
// ---------------------------------------------------------------------------

describe("V5 · forma del doc", () => {
  const conUnaArista = (data: Record<string, unknown>, docId = "u1_u2") => {
    const friendships = [friendship("u1_u2", "u1", ["u1", "u2"], "pending")];
    return verificar({
      friendships,
      follows: [{ id: docId, data }],
      profiles: [
        { id: "u1", followersCount: 0, followingCount: 0 },
        { id: "u2", followersCount: 0, followingCount: 0 },
      ],
    });
  };

  const base = {
    id: "u1_u2",
    followerUid: "u1",
    followeeUid: "u2",
    status: "pending",
    members: ["u1", "u2"],
    createdAt: T0,
  };

  it("el doc bien formado no dispara V5", () => {
    expect(violadas(conUnaArista({ ...base }))).toEqual([]);
  });

  it("members con el orden invertido es V5", () => {
    // `members` es derivado y NO ordenado (ADR-FOLLOW-002): su orden ES la
    // dirección. Invertirlo con `followerUid` intacto no lo ve nadie más.
    const r = conUnaArista({ ...base, members: ["u2", "u1"] });

    expect(violadas(r)).toEqual(["V5"]);
    expect(ofensores(r, "V5")).toEqual(["u1_u2"]);
  });

  it("el campo `id` que no coincide con el doc id es V5", () => {
    expect(violadas(conUnaArista({ ...base, id: "otro" }))).toEqual(["V5"]);
  });

  it("una key de más rompe la allowlist de 6", () => {
    // La allowlist está cerrada en rules; un campo extra sólo puede venir de
    // un bypass de Admin SDK o de un script que no es éste.
    expect(violadas(conUnaArista({ ...base, extra: 1 }))).toEqual(["V5"]);
  });

  it("una key de menos también es V5", () => {
    const sinMembers: Record<string, unknown> = { ...base };
    delete sinMembers.members;

    expect(violadas(conUnaArista(sinMembers))).toContain("V5");
  });

  it("una self-arista es V5 (el self-accept es invariante estructural)", () => {
    const r = verificar({
      friendships: [],
      follows: [
        {
          id: "u1_u1",
          data: {
            id: "u1_u1",
            followerUid: "u1",
            followeeUid: "u1",
            status: "accepted",
            members: ["u1", "u1"],
            createdAt: T0,
          },
        },
      ],
      profiles: [{ id: "u1", followersCount: 1, followingCount: 1 }],
    });

    expect(violadas(r)).toContain("V5");
    expect(ofensores(r, "V5")).toEqual(["u1_u1"]);
  });

  it("un status fuera de {pending, accepted} es V5", () => {
    expect(violadas(conUnaArista({ ...base, status: "blocked" }))).toContain(
      "V5",
    );
  });
});

// ---------------------------------------------------------------------------
// Evalúa TODAS las invariantes, no corta en la primera
// ---------------------------------------------------------------------------

describe("verifyMigration · reporte completo", () => {
  it("con varias fallas independientes las reporta todas juntas", () => {
    // Un reporte que corta en la primera obliga a re-correr contra la base
    // después de cada arreglo, a ciegas. A volumen de equipo la corrida entera
    // son segundos: no hay ninguna razón para cortar.
    const friendships = [
      friendship("u1_u2", "u1", ["u1", "u2"], "accepted"),
      friendship("u3_u4", "u3", ["u3", "u4"], "pending"),
    ];
    const follows = [
      followDoc("u1", "u2", "accepted"), // falta u2_u1 → V1, V2, V6a
      followDoc("u4", "u3", "pending"), // invertida → V3, V4
      { id: "u5_u6", data: { id: "mal", followerUid: "u5" } }, // → V4, V5
    ];

    const r = verificar({
      friendships,
      follows,
      profiles: [
        { id: "u1", followersCount: 1, followingCount: 1 },
        { id: "u2", followersCount: 1, followingCount: 1 },
        { id: "u3", followersCount: 0, followingCount: 0 },
        { id: "u4", followersCount: 0, followingCount: 0 },
      ],
    });

    expect(violadas(r)).toEqual(["V1", "V2", "V3", "V4", "V5", "V6a", "V6b"]);
    expect(reportExitCode(r)).toBe(1);
  });

  it("cada violación trae su conteo y hasta 20 ofensores", () => {
    // 30 aristas inventadas: el reporte lo lee un humano en una terminal, así
    // que la lista se trunca pero el CONTEO no.
    const inventadas = Array.from({ length: 30 }, (_, i) =>
      followDoc(`x${i}`, `y${i}`, "pending"),
    );

    const r = verificar({ friendships: [], follows: inventadas, profiles: [] });

    const v4 = r.violations.find((v) => v.invariant === "V4");
    expect(v4?.count).toBe(30);
    expect(v4?.offenders).toHaveLength(20);
  });

  it("la corrida real de treino-dev: 4 accepted + 2 pending → 10 aristas, exit 0", () => {
    // M-00 midió esto contra `treino-dev`: 6 friendships entre 8 uids, 0
    // malformadas. `2×4 + 2 == 10` es el número que M-06 tiene que confirmar.
    const { friendships, follows, profiles } = mundoSano([
      friendship("a_b", "a", ["a", "b"], "accepted"),
      friendship("c_d", "c", ["c", "d"], "accepted"),
      friendship("e_f", "f", ["e", "f"], "accepted"),
      friendship("g_h", "g", ["g", "h"], "accepted"),
      friendship("a_c", "a", ["a", "c"], "pending"),
      friendship("b_h", "h", ["b", "h"], "pending"),
    ]);

    const r = verificar({ friendships, follows, profiles });

    expect(r.stats).toEqual({
      friendships: 6,
      accepted: 4,
      pending: 2,
      malformed: 0,
      expectedEdges: 10,
      follows: 10,
      manifestEdges: null,
    });
    expect(r.violations).toEqual([]);
    expect(reportExitCode(r)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// timestampMillis — el manifiesto llega desde JSON, no desde Firestore
// ---------------------------------------------------------------------------

describe("timestampMillis", () => {
  it("normaliza las formas en las que un Timestamp puede llegar", () => {
    // Ésta es la trampa real del modo --delta: el manifiesto se lee de un
    // .json, donde un `Timestamp` de Admin quedó serializado como
    // `{_seconds,_nanoseconds}` y ya NO tiene `toMillis()`. Comparar por
    // identidad de objeto o por `toMillis` a secas daría "createdAt distinto"
    // para TODAS las aristas del manifiesto.
    expect(timestampMillis(T0)).toBe(1_700_000_000_000);
    expect(timestampMillis({ _seconds: 1_700_000_000, _nanoseconds: 0 })).toBe(
      1_700_000_000_000,
    );
    expect(timestampMillis({ seconds: 1_700_000_000, nanoseconds: 0 })).toBe(
      1_700_000_000_000,
    );
    expect(timestampMillis("2023-11-14T22:13:20.000Z")).toBe(
      1_700_000_000_000,
    );
    expect(timestampMillis(1_700_000_000_000)).toBe(1_700_000_000_000);
  });

  it("devuelve null para lo que no es un instante", () => {
    expect(timestampMillis(undefined)).toBeNull();
    expect(timestampMillis(null)).toBeNull();
    expect(timestampMillis({})).toBeNull();
    expect(timestampMillis("no es una fecha")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// 2.5d — modo `--delta --manifest` (design §7.3.1, SCENARIO-846)
//
// Este bloque cubre lo que hasta ahora era código sin ejercitar, y de eso
// depende la compuerta de re-verificación previa al flip (3a.19c). Sin él, la
// compuerta descansaba en una rama que nadie había corrido.
//
// La idea del modo: entre que se distribuye la build a los testers y que se
// flipea el gate, la gente USA la app. Eso genera aristas nuevas legítimas y
// muta algunas del manifiesto. Una verificación que marque eso como error
// enseña a ignorar el reporte — que es peor que no tenerla.
// ---------------------------------------------------------------------------
describe("modo --delta --manifest", () => {
  /** Manifiesto de lo que escribió `--apply`, a partir de las friendships. */
  const manifiestoDe = (friendships: FriendshipDoc[]): ApplyManifest => ({
    appliedAt: "2026-08-04T18:00:00.000Z",
    since: null,
    created: planMigration(friendships, new Map(), {}).toCreate,
    skippedPair: [],
    partialPair: [],
    divergent: [],
    conflicts: [],
    malformed: [],
  });

  const enDelta = (
    input: {
      friendships: FriendshipDoc[];
      follows: FollowDoc[];
      profiles: ProfileDoc[];
    },
    manifest: ApplyManifest,
  ): VerifyReport => verifyMigration(input, { mode: "delta", manifest });

  const base = (): FriendshipDoc[] => [
    friendship("f1", "u1", ["u1", "u2"], "accepted"),
    friendship("f2", "u3", ["u3", "u4"], "pending"),
  ];

  it("aristas nuevas sin origen NO son error: son follows post-flip", () => {
    // En `--cutover` esto sería V4 (arista inventada). Acá es la actividad
    // esperada de un tester con la build nueva.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows, profiles } = mundoSano(fs);
    const conNuevas = [...follows, followDoc("u9", "u8", "accepted", T1)];

    const r = enDelta(
      { friendships: fs, follows: conNuevas, profiles },
      manifest,
    );

    expect(violadas(r)).toEqual([]);
    expect(reportExitCode(r)).toBe(0);
  });

  it("V1 NO se evalúa en delta", () => {
    // La cardinalidad global deja de ser función del origen apenas hay un
    // cliente escribiendo. Una invariante que falla por actividad legítima
    // es ruido, no señal.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows, profiles } = mundoSano(fs);
    const conNuevas = [
      ...follows,
      followDoc("u9", "u8", "accepted", T1),
      followDoc("u7", "u6", "accepted", T1),
    ];

    const r = enDelta(
      { friendships: fs, follows: conNuevas, profiles },
      manifest,
    );

    expect(violadas(r)).not.toContain("V1");
  });

  it("un UNFOLLOW de una arista del manifiesto es warning, no error", () => {
    // Mutación legítima 1 de 2: alguien dejó de seguir en la ventana.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows, profiles } = mundoSano(fs);
    const sinUna = follows.filter((f) => f.id !== "u2_u1");

    const r = enDelta({ friendships: fs, follows: sinUna, profiles }, manifest);

    expect(reportExitCode(r)).toBe(0);
    expect(r.warnings.map((w) => w.kind)).toContain("manifest-edge-deleted");
  });

  it("un ACCEPT de una pending del manifiesto es warning, no error", () => {
    // Mutación legítima 2 de 2: el destinatario aceptó en la ventana.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows } = mundoSano(fs);
    const aceptada = follows.map((f) =>
      f.id === "u3_u4"
        ? followDoc("u3", "u4", "accepted", f.data.createdAt as TimestampLike)
        : f,
    );

    const r = enDelta(
      { friendships: fs, follows: aceptada, profiles: perfilesDe(aceptada) },
      manifest,
    );

    expect(reportExitCode(r)).toBe(0);
    expect(r.warnings.map((w) => w.kind)).toContain("manifest-edge-accepted");
  });

  it("las dos mutaciones legítimas juntas siguen dando exit 0", () => {
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows } = mundoSano(fs);
    const mutadas = follows
      .filter((f) => f.id !== "u2_u1")
      .map((f) =>
        f.id === "u3_u4"
          ? followDoc("u3", "u4", "accepted", f.data.createdAt as TimestampLike)
          : f,
      )
      .concat(followDoc("u9", "u8", "accepted", T1));

    const r = enDelta(
      { friendships: fs, follows: mutadas, profiles: perfilesDe(mutadas) },
      manifest,
    );

    expect(reportExitCode(r)).toBe(0);
  });

  it("un createdAt movido SÍ es error — no es una mutación legítima", () => {
    // Ninguna escritura que las rules permiten puede mover `createdAt`: está
    // pineado en el update. Si se movió, alguien escribió por fuera.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows, profiles } = mundoSano(fs);
    const corrida = follows.map((f) =>
      f.id === "u1_u2" ? followDoc("u1", "u2", "accepted", T1) : f,
    );

    const r = enDelta(
      { friendships: fs, follows: corrida, profiles },
      manifest,
    );

    expect(reportExitCode(r)).toBe(1);
  });

  it("una accepted que dejó de ser accepted SÍ es error", () => {
    // El único cambio de status que las rules permiten es pending → accepted.
    // Al revés es imposible por vía legítima.
    const fs = base();
    const manifest = manifiestoDe(fs);
    const { follows, profiles } = mundoSano(fs);
    const degradada = follows.map((f) =>
      f.id === "u1_u2" ? followDoc("u1", "u2", "pending") : f,
    );

    const r = enDelta(
      { friendships: fs, follows: degradada, profiles },
      manifest,
    );

    expect(reportExitCode(r)).toBe(1);
  });

  it("--delta sin manifiesto no verifica nada: falla ruidoso", () => {
    // Se mapea a exit 2. Adivinar qué arista es legítima sin manifiesto es
    // exactamente lo que el resto del plan prohíbe.
    const fs = base();
    const { follows, profiles } = mundoSano(fs);

    expect(() =>
      verifyMigration(
        { friendships: fs, follows, profiles },
        { mode: "delta", manifest: null },
      ),
    ).toThrow(/manifest/i);
  });
});
