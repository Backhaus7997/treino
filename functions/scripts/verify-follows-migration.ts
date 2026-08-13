/**
 * verify-follows-migration.ts — compuerta de cutover de la migración
 * `friendships → follows`. Hito M-06 (`--cutover`) y re-verificación de 3a.19c /
 * M-09 (`--delta --manifest`). Contrato completo: design §7.3 y §7.3.1.
 *
 * ## SOLO LECTURA. No hay flag de escritura, ni siquiera de reparación
 *
 * Si esto falla, se borra `follows` y se vuelve a M-02. Parchear a mano una
 * migración es exactamente cómo se pierde la trazabilidad: el estado final deja
 * de ser función del origen y ya nadie puede reproducirlo.
 *
 * ## Las 6 invariantes (design §7.3)
 *
 *   V1  cardinalidad — `follows` es la imagen exacta de las friendships bien formadas
 *   V2  cobertura de accepted — las DOS direcciones, con el `createdAt` de origen
 *   V3  cobertura y unicidad de pending — la del requester, y la inversa ausente
 *   V4  sin invención — toda arista tiene origen bien formado, status y dirección legales
 *   V5  forma del doc — id, no-self, members derivado, allowlist de 6 keys, status válido
 *   V6a contadores recalculados == grado de amistades (following == followers == deg)
 *   V6b contadores ALMACENADOS == recalculados (o sea: M-05 corrió)
 *
 * Cada clase de falla la atrapan al menos dos invariantes (tabla de cobertura de
 * §7.3). Esa redundancia es deliberada y es la razón de que se evalúen TODAS y
 * no se corte en la primera: un reporte que muestra un solo problema obliga al
 * operador a re-correr contra la base después de cada arreglo, a ciegas. A
 * volumen de equipo la corrida entera son segundos.
 *
 * ## Lo más fácil de arruinar: EXCLUIR NO ES RESTAR
 *
 * La cardinalidad es `2 × accepted BIEN FORMADAS + pending BIEN FORMADAS`. Los
 * malformados se EXCLUYEN del universo; NO se restan del resultado. La forma
 * `2·A + P − MF` es aritméticamente falsa: desarrollando con `A = A_wf + A_mf`
 * queda `2·A_wf + P_wf + A_mf` — sobra `A_mf`, una arista por cada `accepted`
 * malformada. Y una malformada por `status` inválido no está ni en
 * `count(accepted)` ni en `count(pending)` pero igual se restaría: sub-cuenta.
 * Los dos errores existen a la vez y se cancelan parcialmente, así que la
 * fórmula falsa PUEDE DAR BIEN POR CASUALIDAD. Por eso acá `A` y `P` se cuentan
 * sobre las bien formadas y `MF` no entra nunca en la ecuación.
 *
 * ## El predicado de "bien formado" se IMPORTA, no se reimplementa
 *
 * `classifyFriendship` y `expandToEdges` vienen de
 * `migrate-friendships-to-follows.ts`. Si el verificador tuviera su propia copia
 * del criterio, alcanzaría con que una de las dos se actualizara para que la
 * verificación dejara de verificar — validaría un universo que no es el que se
 * migró, en silencio y con exit 0.
 *
 * Correr con credenciales admin, desde functions/:
 *   # cutover (default, estricto — M-06):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/verify-follows-migration.ts
 *   # relativo a un manifiesto (re-verificación 3a.19c, o M-09):
 *   ... scripts/verify-follows-migration.ts --delta \
 *       --manifest scripts/migrations/apply-2026-08-04T18-00-00-000Z.json
 *
 * Exit codes: 0 verde (warnings permitidos) · 1 ≥1 invariante violada ·
 * 2 error de ejecución (incluye `--delta` sin `--manifest`).
 */

import * as fs from "fs";

import * as admin from "firebase-admin";

import {
  classifyFriendship,
  expandToEdges,
  pairIdOf,
  type ApplyManifest,
  type Edge,
  type FollowStatus,
  type FriendshipData,
  type FriendshipDoc,
} from "./migrate-friendships-to-follows";

// ---------------------------------------------------------------------------
// Tipos del reporte
// ---------------------------------------------------------------------------

export type InvariantId = "V1" | "V2" | "V3" | "V4" | "V5" | "V6a" | "V6b";

export type VerifyMode = "cutover" | "delta";

/**
 * Doc OBSERVADO de `follows`. `data` es `Record<string, unknown>` a propósito y
 * no un tipo con campos opcionales: es dato que ya está en la base y detectar
 * que NO tiene la forma esperada es media V5. Tiparlo lindo sería asumir lo que
 * hay que verificar.
 */
export interface FollowDoc {
  id: string;
  data: Record<string, unknown>;
}

/** Lo único que se lee de `userPublicProfiles` (design §7.3, "Fuentes"). */
export interface ProfileDoc {
  id: string;
  followersCount?: number;
  followingCount?: number;
}

export interface Violation {
  invariant: InvariantId;
  /** Legible por un humano en una terminal, con los NÚMEROS adentro. */
  message: string;
  /** Total de ofensores. NO se trunca: `offenders` sí. */
  count: number;
  /** Hasta `MAX_OFFENDERS` ids. El reporte lo lee una persona. */
  offenders: string[];
}

export type WarningKind =
  | "malformed-friendship"
  | "missing-profile"
  | "manifest-edge-deleted"
  | "manifest-edge-accepted";

export interface VerifyWarning {
  kind: WarningKind;
  id: string;
  detail?: string;
}

export interface VerifyStats {
  friendships: number;
  /** Bien formadas con status `accepted`. Las malformadas NO entran. */
  accepted: number;
  /** Bien formadas con status `pending`. Idem. */
  pending: number;
  malformed: number;
  /** `2 × accepted + pending`, ambas sobre bien formadas. */
  expectedEdges: number;
  follows: number;
  /** Aristas del manifiesto en modo `--delta`; `null` en `--cutover`. */
  manifestEdges: number | null;
}

export interface VerifyReport {
  mode: VerifyMode;
  stats: VerifyStats;
  violations: Violation[];
  warnings: VerifyWarning[];
}

export interface VerifyInput {
  friendships: FriendshipDoc[];
  follows: FollowDoc[];
  profiles: ProfileDoc[];
}

export interface VerifyOptions {
  mode: VerifyMode;
  /** Obligatorio en `--delta`. Ver §7.3.1. */
  manifest?: ApplyManifest | null;
}

/** Cuántos ofensores se imprimen por clase. El CONTEO nunca se trunca. */
const MAX_OFFENDERS = 20;

/** Allowlist cerrada de design §1.1 — la misma que rules. */
const EDGE_KEYS = [
  "id",
  "followerUid",
  "followeeUid",
  "status",
  "members",
  "createdAt",
] as const;

/** Orden canónico del reporte. No es cosmética: se lee de arriba hacia abajo. */
const INVARIANT_ORDER: InvariantId[] = [
  "V1",
  "V2",
  "V3",
  "V4",
  "V5",
  "V6a",
  "V6b",
];

// ---------------------------------------------------------------------------
// timestampMillis — la trampa real del modo --delta
// ---------------------------------------------------------------------------

/**
 * Normaliza a milisegundos las formas en las que puede llegar un instante.
 *
 * Parece defensivo de más hasta que se mira de dónde viene cada fuente: los
 * `createdAt` de `friendships`/`follows` llegan como `Timestamp` de Admin (con
 * `toMillis()`), pero los del MANIFIESTO llegan de un `.json` — donde ese mismo
 * `Timestamp` quedó serializado como `{_seconds,_nanoseconds}` y ya NO tiene
 * `toMillis()`. Comparar por identidad de objeto, o por `toMillis` a secas,
 * daría "createdAt distinto" para TODAS las aristas del manifiesto: la
 * verificación fallaría entera por un detalle de serialización.
 *
 * Devuelve `null` para lo que no es un instante, y ese `null` propaga como
 * "no comparable" → violación, que es lo correcto: un `createdAt` ilegible no
 * es un `createdAt` válido.
 */
export function timestampMillis(value: unknown): number | null {
  if (value === null || value === undefined) return null;

  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === "string") {
    const ms = Date.parse(value);
    return Number.isNaN(ms) ? null : ms;
  }
  if (value instanceof Date) {
    const ms = value.getTime();
    return Number.isNaN(ms) ? null : ms;
  }
  if (typeof value !== "object") return null;

  const o = value as Record<string, unknown>;

  if (typeof o.toMillis === "function") {
    const ms = (o as { toMillis: () => unknown }).toMillis();
    return typeof ms === "number" && Number.isFinite(ms) ? ms : null;
  }

  // `{_seconds,_nanoseconds}` es la forma serializada por JSON.stringify de un
  // Timestamp de Admin; `{seconds,nanoseconds}` la del SDK web y la de un
  // export de gcloud. Las dos son el mismo instante.
  const seconds =
    typeof o._seconds === "number"
      ? o._seconds
      : typeof o.seconds === "number"
        ? o.seconds
        : null;
  if (seconds === null) return null;

  const nanos =
    typeof o._nanoseconds === "number"
      ? o._nanoseconds
      : typeof o.nanoseconds === "number"
        ? o.nanoseconds
        : 0;

  return seconds * 1000 + Math.floor(nanos / 1e6);
}

// ---------------------------------------------------------------------------
// verifyMigration
// ---------------------------------------------------------------------------

/** Una friendship bien formada, ya con su dirección resuelta y sus aristas. */
interface WellFormed {
  docId: string;
  requesterId: string;
  otherUid: string;
  status: FollowStatus;
  createdAtMs: number;
  pairId: string;
  /** Las aristas LEGALES de este origen: 2 si accepted, 1 si pending. */
  edges: Edge[];
}

function asString(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function bump(m: Map<string, number>, uid: string): void {
  m.set(uid, (m.get(uid) ?? 0) + 1);
}

/**
 * Verifica la migración. **Función pura**: no toca Firestore, no lee el reloj,
 * no escribe nada. Todo lo que decide sale de sus dos argumentos — que es lo
 * que permite INYECTAR cada clase de falla en un test y probar que la atrapa.
 * Una compuerta que solo se puede ejercitar contra la base real no es una
 * compuerta: es una esperanza.
 */
export function verifyMigration(
  input: VerifyInput,
  opts: VerifyOptions,
): VerifyReport {
  const mode = opts.mode;
  const manifest = opts.manifest ?? null;

  if (mode === "delta" && manifest === null) {
    // Sin manifiesto no hay forma de distinguir una arista nueva legítima
    // (follow post-flip) de una inventada, y adivinarlo es exactamente lo que
    // el resto del plan prohíbe. `main` lo mapea a exit 2 (design §7.3.1).
    throw new Error(
      "--delta exige --manifest: sin manifiesto no se puede separar una " +
        "arista nueva legítima de una inventada (design §7.3.1).",
    );
  }

  const warnings: VerifyWarning[] = [];

  // Ofensores por invariante, deduplicados y en orden de detección. TODAS las
  // invariantes se evalúan: nada de acá corta el flujo.
  const offenders = new Map<InvariantId, Set<string>>();
  const flag = (inv: InvariantId, offender: string): void => {
    const set = offenders.get(inv) ?? new Set<string>();
    set.add(offender);
    offenders.set(inv, set);
  };

  // -------------------------------------------------------------------------
  // 1. Universo de origen: qué esperaba producir la migración
  // -------------------------------------------------------------------------

  const byPair = new Map<string, WellFormed>();
  /** deg(uid) = # de friendships ACCEPTED bien formadas que contienen a uid. */
  const deg = new Map<string, number>();
  /** Todo uid que aparece en alguna bien formada (accepted o pending). */
  const uidsEnWF = new Set<string>();
  const wellFormed: WellFormed[] = [];

  let accepted = 0;
  let pending = 0;
  let malformed = 0;
  let expectedEdges = 0;

  for (const doc of input.friendships) {
    const c = classifyFriendship(doc.data as FriendshipData);
    if (!c.wellFormed) {
      // EXCLUIDA del universo — no se resta de nada. Se enumera nominalmente
      // como warning porque el operador tiene que poder auditarla a mano.
      malformed++;
      warnings.push({
        kind: "malformed-friendship",
        id: doc.id,
        detail: c.reason,
      });
      continue;
    }

    if (c.status === "accepted") accepted++;
    else pending++;

    const edges = expandToEdges(c);
    expectedEdges += edges.length;

    const wf: WellFormed = {
      docId: doc.id,
      requesterId: c.requesterId,
      otherUid: c.otherUid,
      status: c.status,
      createdAtMs: timestampMillis(c.createdAt) ?? Number.NaN,
      pairId: pairIdOf(c.requesterId, c.otherUid),
      edges,
    };
    wellFormed.push(wf);
    byPair.set(wf.pairId, wf);

    uidsEnWF.add(c.requesterId);
    uidsEnWF.add(c.otherUid);
    if (c.status === "accepted") {
      bump(deg, c.requesterId);
      bump(deg, c.otherUid);
    }
  }

  // -------------------------------------------------------------------------
  // 2. Universo observado: qué hay realmente en `follows`
  // -------------------------------------------------------------------------

  const observed = new Map<string, FollowDoc>();
  for (const doc of input.follows) observed.set(doc.id, doc);

  // Las DOS queries de la CF y del backfill (ADR-FOLLOW-007). Que las tres
  // implementaciones cuenten igual es lo que hace chequeable a V6a.
  const followingRecalc = new Map<string, number>();
  const followersRecalc = new Map<string, number>();
  const uidsEnFollows = new Set<string>();

  /** Doc ids observados agrupados por PAR (no dirigido). Insumo de V1. */
  const observadasPorPar = new Map<string, string[]>();
  /** Docs a los que no se les puede atribuir un par: no tienen dirección legible. */
  const sinParAtribuible: string[] = [];

  for (const doc of input.follows) {
    const follower = asString(doc.data.followerUid);
    const followee = asString(doc.data.followeeUid);
    if (follower) uidsEnFollows.add(follower);
    if (followee) uidsEnFollows.add(followee);

    if (follower && followee) {
      const pair = pairIdOf(follower, followee);
      const ids = observadasPorPar.get(pair) ?? [];
      ids.push(doc.id);
      observadasPorPar.set(pair, ids);
    } else {
      sinParAtribuible.push(doc.id);
    }

    if (doc.data.status !== "accepted") continue;
    if (follower) bump(followingRecalc, follower);
    if (followee) bump(followersRecalc, followee);
  }

  // -------------------------------------------------------------------------
  // V1 — cardinalidad (sólo `--cutover`)
  // -------------------------------------------------------------------------
  //
  // En `--delta` NO se evalúa: la cardinalidad global deja de ser función del
  // origen apenas hay un cliente escribiendo, y una invariante que puede fallar
  // por actividad legítima no es una invariante, es ruido que enseña a ignorar
  // el reporte (design §7.3.1).
  //
  // La cardinalidad se evalúa POR PAR, no sólo como el total global. Los dos
  // totales son la cabecera del mensaje —es lo que el operador necesita ver—
  // pero el chequeo es más fino, y tiene que serlo: un borrado tapado por una
  // inserción deja el total intacto. Es literalmente el caso del test de
  // reporte completo (falta `u2_u1`, sobra `u5_u6`): 3 == 3 global, y `follows`
  // igual dejó de ser la imagen de `friendships`. La cardinalidad por par
  // implica la global, así que no se pierde nada del contrato de §7.3.
  //
  // Y la contracara, que es lo que hace que esto NO sea "V1 = igualdad de
  // conjuntos": una `pending` con la dirección invertida tiene la cardinalidad
  // del par CORRECTA (1 arista esperada, 1 observada). No es una falla de
  // cardinalidad y V1 no la marca — la marcan V3 y V4, que es exactamente lo
  // que dice la tabla de cobertura de §7.3. Cada invariante tiene que fallar
  // por su motivo: si V1 se disparara con todo, dejaría de decir nada.
  if (mode === "cutover") {
    for (const wf of wellFormed) {
      const obs = observadasPorPar.get(wf.pairId) ?? [];
      if (obs.length === wf.edges.length) continue;
      for (const e of wf.edges) if (!observed.has(e.id)) flag("V1", e.id);
      for (const id of obs) {
        if (!wf.edges.some((e) => e.id === id)) flag("V1", id);
      }
    }
    // Aristas sobre un par que la migración nunca planificó: o son invención, o
    // se adivinó una dirección sobre un friendship malformado.
    for (const [pair, ids] of observadasPorPar) {
      if (byPair.has(pair)) continue;
      for (const id of ids) flag("V1", id);
    }
    for (const id of sinParAtribuible) flag("V1", id);
  }

  // -------------------------------------------------------------------------
  // V2 / V3 / V4 — cobertura, dirección y origen
  // -------------------------------------------------------------------------

  if (mode === "cutover") {
    // V2 — cada `accepted` tiene sus DOS aristas, ambas accepted y con el
    // `createdAt` del friendship de origen. El `createdAt` no es un detalle:
    // si se lo reemplaza por el reloj del script, una re-migración después de
    // un rollback ya no reproduce el mismo estado (ADR-FOLLOW-014).
    for (const wf of wellFormed) {
      if (wf.status !== "accepted") continue;
      for (const e of wf.edges) {
        const doc = observed.get(e.id);
        if (!doc) {
          flag("V2", e.id);
          continue;
        }
        if (doc.data.status !== "accepted") {
          flag("V2", e.id);
          continue;
        }
        if (timestampMillis(doc.data.createdAt) !== wf.createdAtMs) {
          flag("V2", e.id);
        }
      }
    }

    // V3 — cada `pending` tiene UNA arista, la del requester, y la inversa NO
    // existe. La unicidad direccional es lo único que atrapa una solicitud
    // invertida: las pending no mueven contadores, así que V6 no la ve.
    for (const wf of wellFormed) {
      if (wf.status !== "pending") continue;
      const legal = wf.edges[0];
      const doc = observed.get(legal.id);
      if (
        !doc ||
        doc.data.status !== "pending" ||
        timestampMillis(doc.data.createdAt) !== wf.createdAtMs
      ) {
        flag("V3", legal.id);
      }
      const inversa = `${wf.otherUid}_${wf.requesterId}`;
      if (observed.has(inversa)) flag("V3", inversa);
    }

    // V4 — ninguna arista inventada, sobre TODA la colección. En cutover
    // `follows` es 100% producto de la migración (§7.3.1), así que una arista
    // sin origen bien formado sólo puede ser invención o una dirección
    // adivinada sobre un doc malformado.
    for (const doc of input.follows) {
      const problema = originProblem(doc, byPair, { checkStatus: true });
      if (problema) flag("V4", doc.id);
    }
  } else {
    // --- modo --delta: verificación RELATIVA AL MANIFIESTO ---
    //
    // Qué puede tocarle un tester a una arista migrada NO es libre: lo fija el
    // bloque de rules de §3.1, la única vía de escritura legítima sobre el doc
    // (`delete` de cualquiera de los dos miembros, o `update` restringido a
    // `pending → accepted` con todo lo demás pineado). No hay tercera vía. Por
    // construcción, entonces, una arista del manifiesto sólo puede terminar en
    // uno de tres estados: intacta, ausente (unfollow/cancelación) o aceptada.
    // Cualquier otro estado es estructuralmente inalcanzable para un cliente
    // sujeto a rules: si aparece, es bypass de Admin SDK o bug, y sigue siendo
    // ERROR sin excepción (design §7.3.1).
    for (const m of (manifest as ApplyManifest).created) {
      const inv: InvariantId = m.status === "accepted" ? "V2" : "V3";
      const doc = observed.get(m.id);

      if (!doc) {
        // Estado 2 — la borraron. Unfollow si migró accepted; cancelar o
        // rechazar si migró pending. Warning, jamás error: recrear la arista
        // revertiría una decisión de privacidad (LD-04).
        warnings.push({
          kind: "manifest-edge-deleted",
          id: m.id,
          detail: `migró como ${m.status}`,
        });
        continue;
      }

      // Lo pineado por rules tiene que estar intacto. Si no lo está, no fue un
      // cliente.
      const intacta =
        asString(doc.data.followerUid) === m.followerUid &&
        asString(doc.data.followeeUid) === m.followeeUid &&
        sameMembers(doc.data.members, m.members) &&
        timestampMillis(doc.data.createdAt) ===
          timestampMillis(m.createdAt as unknown);

      if (!intacta) {
        flag(inv, m.id);
      } else if (doc.data.status === m.status) {
        // Estado 1 — nadie la tocó.
      } else if (m.status === "pending" && doc.data.status === "accepted") {
        // Estado 3 — el followee aceptó una solicitud migrada. Sólo aplica a
        // las que migraron `pending`: una `accepted` no tiene a dónde
        // transicionar, porque rules no permiten revertirla.
        warnings.push({
          kind: "manifest-edge-accepted",
          id: m.id,
          detail: "pending → accepted",
        });
      } else {
        flag(inv, m.id);
      }

      // V4 restringida al manifiesto: una arista NUEVA sin origen es un follow
      // legítimo post-flip, no una invención. Lo que sí se atrapa es una
      // arista DEL MANIFIESTO que perdió su origen. El status no se compara:
      // el accept de la ventana lo desacopla legítimamente del origen.
      const problema = originProblem(doc, byPair, { checkStatus: false });
      if (problema) flag("V4", doc.id);
    }
  }

  // -------------------------------------------------------------------------
  // V5 — forma del doc. SIEMPRE sobre toda la colección, en los dos modos
  // -------------------------------------------------------------------------
  //
  // Es la única invariante independiente del origen, y por eso es la que sigue
  // teniendo valor cuando las demás se relajan en `--delta`. Atrapa lo que
  // ninguna otra ve: un `members` mal derivado no mueve contadores, no rompe la
  // cardinalidad y tiene origen legítimo.
  for (const doc of input.follows) {
    if (shapeProblem(doc)) flag("V5", doc.id);
  }

  // -------------------------------------------------------------------------
  // V6a — recalculado == grado de amistades (sólo `--cutover`)
  // -------------------------------------------------------------------------
  //
  // Bajo follow mutuo, `followers` y `following` de cada usuario tienen que ser
  // iguales entre sí Y iguales al grado de amistades aceptadas. Si falta una
  // sola de las dos direcciones de un par, caen DOS: `following` del que quedó
  // sin seguir y `followers` del otro.
  //
  // En `--delta` se cae: los follows post-flip son asimétricos a propósito —
  // que es exactamente el punto del change.
  if (mode === "cutover") {
    for (const uid of uidsEnWF) {
      const following = followingRecalc.get(uid) ?? 0;
      const followers = followersRecalc.get(uid) ?? 0;
      const grado = deg.get(uid) ?? 0;
      if (following !== followers || following !== grado) flag("V6a", uid);
    }
  }

  // -------------------------------------------------------------------------
  // V6b — almacenado == recalculado. En los DOS modos
  // -------------------------------------------------------------------------
  //
  // Es la aserción "M-05 corrió". Los valores viejos salían del split por
  // `requesterId` —el requester contaba como "siguiendo" y el otro como
  // "seguidor", nunca los dos—, así que con follow mutuo los DOS suben. Ése es
  // el único cambio visible de la migración (§7.4), pero sólo si el backfill
  // efectivamente corrió.
  // En `--delta` hay que exceptuar a los uids tocados por una mutación
  // legítima de la ventana (unfollow o accept, ver arriba). Motivo concreto:
  // esa ventana va entre que se distribuye la build y que se flipea el gate, y
  // ahí `maintainFollowCounters` TODAVÍA escucha `friendships` (se repunta
  // recién en M-08). O sea que un unfollow real mueve el recalculado pero NO
  // puede mover el almacenado: nadie lo actualiza. Sin esta excepción, V6b
  // hace fallar la compuerta por actividad esperada — exactamente la misma
  // clase de falla que V2/V3 ya resolvieron un escalón antes, y que enseña al
  // operador a ignorar el reporte.
  //
  // No se debilita la garantía: M-08b vuelve a correr backfill + V6b DESPUÉS
  // de repuntar las CFs, y ahí sí es error. Acá sólo se corre el chequeo sobre
  // los uids cuyo contador nadie tenía motivo para mover.
  const eximidosV6b = new Set<string>();
  if (mode === "delta") {
    for (const w of warnings) {
      if (w.kind !== "manifest-edge-deleted" && w.kind !== "manifest-edge-accepted") {
        continue;
      }
      const [follower, followee] = w.id.split("_");
      if (follower) eximidosV6b.add(follower);
      if (followee) eximidosV6b.add(followee);
    }
  }

  const conPerfil = new Set(input.profiles.map((p) => p.id));
  for (const p of input.profiles) {
    if (eximidosV6b.has(p.id)) continue;
    const following = followingRecalc.get(p.id) ?? 0;
    const followers = followersRecalc.get(p.id) ?? 0;
    if ((p.followingCount ?? 0) !== following) {
      flag("V6b", p.id);
      continue;
    }
    if ((p.followersCount ?? 0) !== followers) flag("V6b", p.id);
  }

  // Uid con aristas (o con amistades) pero sin doc en `userPublicProfiles`:
  // WARNING, no error. Misma política que la CF y el backfill — no se resucita
  // el perfil de una cuenta borrada (design §7.3).
  for (const uid of [...uidsEnWF, ...uidsEnFollows]) {
    if (!conPerfil.has(uid)) {
      if (warnings.some((w) => w.kind === "missing-profile" && w.id === uid)) {
        continue;
      }
      warnings.push({ kind: "missing-profile", id: uid });
    }
  }

  // -------------------------------------------------------------------------
  // Reporte
  // -------------------------------------------------------------------------

  const followsCount = input.follows.length;
  const violations: Violation[] = [];
  for (const inv of INVARIANT_ORDER) {
    const set = offenders.get(inv);
    if (!set || set.size === 0) continue;
    const ids = [...set];
    violations.push({
      invariant: inv,
      message: messageFor(inv, {
        expectedEdges,
        followsCount,
        offenderCount: ids.length,
      }),
      count: ids.length,
      offenders: ids.slice(0, MAX_OFFENDERS),
    });
  }

  return {
    mode,
    stats: {
      friendships: input.friendships.length,
      accepted,
      pending,
      malformed,
      expectedEdges,
      follows: followsCount,
      manifestEdges: manifest ? manifest.created.length : null,
    },
    violations,
    warnings,
  };
}

/**
 * Exit code del reporte (design §7.3). Los warnings NO hacen fallar: un perfil
 * ausente y una friendship malformada son estados conocidos y auditables, no
 * corrupción del grafo.
 */
export function reportExitCode(report: VerifyReport): 0 | 1 {
  return report.violations.length > 0 ? 1 : 0;
}

// ---------------------------------------------------------------------------
// Chequeos por doc
// ---------------------------------------------------------------------------

/**
 * V4 para un doc: ¿tiene origen bien formado y es una dirección legal para ese
 * origen? Devuelve el motivo, o `null` si está bien.
 *
 * La dirección se deriva de `followerUid`/`followeeUid` y no del doc id: el id
 * lo chequea V5, y si los dos discrepan hay que enterarse por las DOS vías.
 */
function originProblem(
  doc: FollowDoc,
  byPair: Map<string, WellFormed>,
  opts: { checkStatus: boolean },
): string | null {
  const follower = asString(doc.data.followerUid);
  const followee = asString(doc.data.followeeUid);
  if (!follower || !followee) return "sin-direccion-legible";

  const wf = byPair.get(pairIdOf(follower, followee));
  if (!wf) return "sin-friendship-de-origen";

  if (opts.checkStatus && doc.data.status !== wf.status) {
    return "status-distinto-del-origen";
  }

  // accepted → las dos direcciones son legales; pending → sólo la del
  // requester. `wf.edges` ya es esa lista, y sale del mismo `expandToEdges` que
  // usó la migración.
  const derivado = `${follower}_${followee}`;
  if (!wf.edges.some((e) => e.id === derivado)) {
    return "direccion-ilegal-para-el-origen";
  }
  return null;
}

/** V5 para un doc: forma exacta de design §1.1. */
function shapeProblem(doc: FollowDoc): string | null {
  const data = doc.data;
  const keys = Object.keys(data);

  // Allowlist CERRADA de 6 keys. Está cerrada en rules, así que un campo de más
  // sólo puede venir de un bypass de Admin SDK o de un script que no es éste.
  if (keys.length !== EDGE_KEYS.length) return "key-set-distinto";
  for (const k of EDGE_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(data, k)) return "key-faltante";
  }

  if (data.id !== doc.id) return "id-distinto-del-docId";

  const follower = asString(data.followerUid);
  const followee = asString(data.followeeUid);
  if (!follower || !followee) return "uid-no-legible";
  // El self-accept es una invariante estructural: nadie se sigue a sí mismo.
  if (follower === followee) return "self-arista";

  // `members` es DERIVADO y NO ordenado (ADR-FOLLOW-002): su orden ES la
  // dirección. Invertirlo con `followerUid` intacto no lo ve ninguna otra
  // invariante.
  if (!sameMembers(data.members, [follower, followee])) {
    return "members-mal-derivado";
  }

  if (data.status !== "pending" && data.status !== "accepted") {
    return "status-invalido";
  }
  if (timestampMillis(data.createdAt) === null) return "createdAt-ilegible";

  return null;
}

function sameMembers(observed: unknown, expected: readonly string[]): boolean {
  return (
    Array.isArray(observed) &&
    observed.length === expected.length &&
    expected.every((uid, i) => observed[i] === uid)
  );
}

function messageFor(
  inv: InvariantId,
  ctx: { expectedEdges: number; followsCount: number; offenderCount: number },
): string {
  const n = ctx.offenderCount;
  switch (inv) {
    case "V1":
      // Los DOS números, siempre: "no cierra" no es accionable.
      return (
        `V1 cardinalidad: se esperaban ${ctx.expectedEdges} arista(s) ` +
        `(2 × accepted + pending, sobre BIEN FORMADAS) y hay ` +
        `${ctx.followsCount} en 'follows'; ${n} id(s) no coinciden`
      );
    case "V2":
      return `V2 cobertura de accepted: ${n} arista(s) ausente(s) o alterada(s)`;
    case "V3":
      return (
        `V3 cobertura/unicidad de pending: ${n} arista(s) ausente(s), ` +
        "alterada(s) o con la dirección inversa presente"
      );
    case "V4":
      return `V4 sin invención: ${n} arista(s) sin origen legal en 'friendships'`;
    case "V5":
      return `V5 forma del doc: ${n} arista(s) con la forma rota`;
    case "V6a":
      return (
        `V6a contadores recalculados: ${n} uid(s) donde ` +
        "following != followers != grado de amistades aceptadas"
      );
    case "V6b":
      return (
        `V6b contadores almacenados: ${n} perfil(es) fuera de sync con ` +
        "'follows' — ¿corrió M-05?"
      );
  }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

interface CliArgs {
  mode: VerifyMode;
  manifestPath: string | null;
}

/**
 * Parsea la CLI. Cualquier uso incorrecto TIRA, y `main` lo mapea a exit 2:
 * un modo mal invocado no puede degradar silenciosamente al otro. El default es
 * el ESTRICTO — relajar la compuerta tiene que ser una decisión explícita.
 */
export function parseArgs(argv: string[]): CliArgs {
  const delta = argv.includes("--delta");
  const cutover = argv.includes("--cutover");
  if (delta && cutover) {
    throw new Error("--cutover y --delta son excluyentes.");
  }

  const i = argv.indexOf("--manifest");
  const manifestPath = i === -1 ? null : (argv[i + 1] ?? null);

  if (delta && !manifestPath) {
    throw new Error(
      "--delta exige --manifest <archivo>: el manifiesto de un --apply " +
        "(apply-{ISO}.json de M-04 o delta-{ISO}.json de M-09) es lo único " +
        "que separa una arista nueva legítima de una inventada (§7.3.1).",
    );
  }
  if (!delta && manifestPath) {
    throw new Error("--manifest sólo tiene sentido con --delta.");
  }

  return { mode: delta ? "delta" : "cutover", manifestPath };
}

function loadManifest(file: string): ApplyManifest {
  const raw = fs.readFileSync(file, "utf8");
  const parsed = JSON.parse(raw) as ApplyManifest;
  if (!Array.isArray(parsed.created)) {
    throw new Error(`El manifiesto ${file} no tiene un array 'created'.`);
  }
  return parsed;
}

async function main(): Promise<void> {
  const { mode, manifestPath } = parseArgs(process.argv);
  const manifest = manifestPath ? loadManifest(manifestPath) : null;

  admin.initializeApp();
  const db = admin.firestore();

  console.log(
    `\n=== verify-follows-migration (${mode.toUpperCase()}` +
      `${manifestPath ? `, manifiesto ${manifestPath}` : ""}) ===\n`,
  );

  // 3 lecturas completas de colección. A volumen de equipo (M-00), segundos.
  // NO hay muestreo: es exhaustivo por diseño, igual que el chequeo que
  // reemplaza — una compuerta muestreada no es una compuerta.
  const [friendshipsSnap, followsSnap, profilesSnap] = await Promise.all([
    db.collection("friendships").get(),
    db.collection("follows").get(),
    db
      .collection("userPublicProfiles")
      .select("followersCount", "followingCount")
      .get(),
  ]);

  const report = verifyMigration(
    {
      friendships: friendshipsSnap.docs.map((d) => ({
        id: d.id,
        data: d.data() as FriendshipData,
      })),
      follows: followsSnap.docs.map((d) => ({
        id: d.id,
        data: d.data() as Record<string, unknown>,
      })),
      profiles: profilesSnap.docs.map((d) => {
        const data = d.data() as Record<string, unknown>;
        return {
          id: d.id,
          followersCount:
            typeof data.followersCount === "number"
              ? data.followersCount
              : undefined,
          followingCount:
            typeof data.followingCount === "number"
              ? data.followingCount
              : undefined,
        };
      }),
    },
    { mode, manifest },
  );

  printReport(report);
  process.exit(reportExitCode(report));
}

function printReport(report: VerifyReport): void {
  const s = report.stats;
  console.log(
    `${s.friendships} friendship(s): ${s.accepted} accepted + ${s.pending} ` +
      `pending bien formadas (+ ${s.malformed} malformada/s EXCLUIDA/S).`,
  );
  console.log(
    `Aristas esperadas = 2 × ${s.accepted} + ${s.pending} = ${s.expectedEdges}.`,
  );
  console.log(`Aristas en 'follows': ${s.follows}.`);
  if (s.manifestEdges !== null) {
    console.log(`Aristas en el manifiesto: ${s.manifestEdges}.`);
  }

  if (report.warnings.length > 0) {
    console.warn(`\n⚠️  ${report.warnings.length} warning(s) — NO hacen fallar:`);
    for (const w of report.warnings.slice(0, MAX_OFFENDERS * 5)) {
      console.warn(`   [${w.kind}] ${w.id}${w.detail ? `: ${w.detail}` : ""}`);
    }
  }

  if (report.violations.length === 0) {
    console.log("\n✅ Todas las invariantes del modo, verdes.");
    return;
  }

  // Se imprimen TODAS. Cortar en la primera obliga a re-correr contra la base
  // después de cada arreglo, a ciegas.
  console.error(`\n❌ ${report.violations.length} invariante(s) violada(s):`);
  for (const v of report.violations) {
    console.error(`\n   ${v.message}`);
    console.error(
      `   ${v.count} ofensor(es)` +
        `${v.count > v.offenders.length ? ` (se listan ${v.offenders.length})` : ""}:`,
    );
    for (const id of v.offenders) console.error(`     ${id}`);
  }
  console.error(
    "\nNO se parchea a mano: si esto falla, se borra 'follows' y se vuelve " +
      "a M-02 (design §7.3).",
  );
}

// Sólo corre invocado directamente (ts-node scripts/...), NO cuando un test
// importa las funciones puras.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(2);
  });
}
