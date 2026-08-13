/**
 * migrate-friendships-to-follows.ts — migra `friendships` (un doc por par, no
 * dirigido) a `follows/{followerUid}_{followeeUid}` (un doc por arista
 * dirigida). Hitos M-02 (`--dry-run`) y M-04 (`--apply`) del change
 * `follow-model`. Contrato completo: design §7.2.
 *
 * ## Qué hace, y por qué así
 *
 * `requesterId` deja de ser un campo adentro de un doc simétrico y pasa a ser
 * el prefijo del doc id. La dirección deja de calcularse en runtime: está en la
 * clave. Eso es todo el cambio; lo demás es consecuencia.
 *
 *   accepted {A,B}  →  DOS aristas: {A}_{B} y {B}_{A}, ambas accepted
 *   pending  R→O    →  UNA arista:  {R}_{O}, pending
 *
 * Las DOS aristas por `accepted` (ADR-FOLLOW-013) no son un detalle: con una
 * sola, la mitad de las relaciones existentes perdía acceso a los posts del
 * otro el día del flip. La migración no reescribe el pasado — la asimetría
 * rige desde el flip en adelante.
 *
 * ## Lo más sutil del script: G1 es ASIMÉTRICA POR MODO
 *
 * El mismo estado observado —"al par le falta una de sus aristas esperadas"—
 * significa cosas OPUESTAS según el modo, así que una guarda única tiene que
 * estar mal en uno de los dos:
 *
 *   CON  --since (delta sweep post-flip): falta una dirección ⇒ alguien DEJÓ DE
 *        SEGUIR. Recrearla revertiría una decisión de privacidad (LD-04). El par
 *        entero se saltea y no se escribe nada.
 *   SIN  --since (corrida inicial, o reintento tras un batch de 400 que murió a
 *        la mitad): falta una dirección ⇒ MIGRACIÓN INCOMPLETA. Acá `follows` es
 *        100% producto de la migración y el cliente que produce unfollows (PR3c)
 *        ni siquiera está publicado, así que un unfollow es IMPOSIBLE. Se
 *        completa la faltante y el par se grita en `partialPair`.
 *
 * Sin esta asimetría, reintentar un batch interrumpido reporta "ya migrado" y
 * sale exit 0 dejando la migración a medias.
 *
 * ## Seguridad
 *
 * - `--dry-run` es el DEFAULT. Sólo `--apply` escribe.
 * - Escribe con `batch.create()`, NUNCA `set()` (ADR-FOLLOW-014): si la arista
 *   apareció entre el read y el write, falla ruidoso en vez de pisar.
 * - No toca `friendships` ni un campo: la colección origen queda byte-idéntica,
 *   que es la precondición 1 del rollback (ADR-FOLLOW-012).
 * - Nunca borra ni actualiza aristas. Sólo crea.
 * - Nunca adivina una dirección: los docs malformados se enumeran nominalmente
 *   y se excluyen del `--apply`.
 *
 * ## Regla de la ventana muda (design §7.2)
 *
 * Ningún `--apply` corre mientras `maintainFollowCounters` y `notifyOnFollow`
 * estén repuntadas a `follows`: las dos son `onDocumentWritten` sobre el path
 * de la colección, así que cada arista escrita sería un evento — y un push
 * "empezó a seguirte" a testers reales por relaciones de hace meses.
 *
 * Correr con credenciales admin, desde functions/:
 *   # dry run (default, no escribe nada):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/migrate-friendships-to-follows.ts
 *   # apply:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/migrate-friendships-to-follows.ts --apply
 *   # delta sweep (M-09), con la marca temporal del run de M-04:
 *   ... scripts/migrate-friendships-to-follows.ts --since 2026-08-04T18:00:00Z
 */

import * as fs from "fs";
import * as path from "path";

import * as admin from "firebase-admin";

export type FollowStatus = "pending" | "accepted";

/**
 * Lo mínimo que este script necesita de un `Timestamp` de Firestore. Se tipa
 * estructuralmente en vez de importar `admin.firestore.Timestamp` para que
 * `planMigration` sea testeable con fixtures triviales y sin Firestore.
 */
export interface TimestampLike {
  toMillis(): number;
}

/** Body crudo de un doc de `friendships`, tal como viene de Firestore. */
export interface FriendshipData {
  requesterId?: string;
  members?: string[];
  status?: string;
  createdAt?: TimestampLike;
}

export interface FriendshipDoc {
  id: string;
  data: FriendshipData;
}

/** Arista esperada — la forma exacta que se escribe en `follows` (design §1.1). */
export interface Edge {
  id: string;
  followerUid: string;
  followeeUid: string;
  status: FollowStatus;
  members: [string, string];
  createdAt: TimestampLike;
}

/**
 * Arista OBSERVADA en `follows`. Todo opcional a propósito: es dato que ya
 * está en la base y el script no puede asumir que esté bien formado — de hecho
 * detectar que no lo está es media G2.
 */
export interface EdgeData {
  id?: string;
  followerUid?: string;
  followeeUid?: string;
  status?: string;
  members?: string[];
  createdAt?: TimestampLike;
}

export type Classification =
  | {
      wellFormed: true;
      requesterId: string;
      otherUid: string;
      status: FollowStatus;
      createdAt: TimestampLike;
    }
  | { wellFormed: false; reason: string };

export interface Plan {
  toCreate: Edge[];
  skippedPair: { pairId: string; reason: "already-migrated" }[];
  /**
   * SOLO en corrida inicial (sin `--since`): par con algunas pero no todas sus
   * aristas esperadas → se COMPLETA (las faltantes van a `toCreate`) y se
   * reporta acá como warning ruidoso. El operador tiene que enterarse de que
   * hubo una corrida interrumpida aunque el script la resuelva.
   */
  partialPair: { pairId: string; present: string[]; created: string[] }[];
  divergent: {
    edgeId: string;
    expected: Partial<Edge>;
    actual: Partial<EdgeData>;
  }[];
  conflicts: { pairId: string; reason: "no-edges-and-older-than-since" }[];
  malformed: { docId: string; reason: string }[];
  stats: {
    friendships: number;
    accepted: number;
    pending: number;
    expectedEdges: number;
  };
}

export interface ApplyManifest {
  appliedAt: string;
  since: string | null;
  /**
   * Aristas EFECTIVAMENTE escritas, completas (no ids sueltos): la
   * verificación en modo `--delta --manifest` compara status/createdAt/
   * dirección contra esto sin volver a leer `friendships`.
   */
  created: Edge[];
  skippedPair: Plan["skippedPair"];
  partialPair: Plan["partialPair"];
  divergent: Plan["divergent"];
  conflicts: Plan["conflicts"];
  malformed: Plan["malformed"];
}

// ---------------------------------------------------------------------------
// Predicado de "bien formado" — LO IMPORTA verify-follows-migration.ts
// ---------------------------------------------------------------------------

/**
 * Clasifica un doc de `friendships`. Si está bien formado devuelve además la
 * dirección resuelta, así el que lo consume no vuelve a derivarla.
 *
 * **Este predicado es fuente única.** `verify-follows-migration.ts` lo importa
 * en vez de reimplementarlo: si los dos criterios divergen, la verificación
 * deja de verificar (design §7.3).
 *
 * Sobre `createdAt`: design §7.2 no lo lista entre los motivos de malformado,
 * pero un friendship sin `createdAt` utilizable no es migrable — la arista se
 * escribiría con `undefined` (que Firestore rechaza) o con el reloj del script
 * (que rompe la reproducibilidad de una re-migración, ADR-FOLLOW-014). Las dos
 * salidas son peores que excluirlo del universo y enumerarlo.
 */
export function classifyFriendship(data: FriendshipData): Classification {
  const requesterId = data.requesterId;
  const members = data.members ?? [];

  if (!requesterId) return { wellFormed: false, reason: "sin-requesterId" };
  if (members.length !== 2) {
    return { wellFormed: false, reason: "members-no-es-par" };
  }
  if (!members.includes(requesterId)) {
    return { wellFormed: false, reason: "requesterId-fuera-de-members" };
  }
  if (data.status !== "pending" && data.status !== "accepted") {
    return { wellFormed: false, reason: "status-invalido" };
  }

  const otherUid = members.find((m) => m !== requesterId);
  if (!otherUid) return { wellFormed: false, reason: "self-pair" };

  if (!isTimestampLike(data.createdAt)) {
    return { wellFormed: false, reason: "createdAt-ausente-o-invalido" };
  }

  return {
    wellFormed: true,
    requesterId,
    otherUid,
    status: data.status,
    createdAt: data.createdAt,
  };
}

export function isWellFormed(data: FriendshipData): boolean {
  return classifyFriendship(data).wellFormed;
}

// ---------------------------------------------------------------------------
// Expansión
// ---------------------------------------------------------------------------

export function makeEdge(
  followerUid: string,
  followeeUid: string,
  status: FollowStatus,
  createdAt: TimestampLike,
): Edge {
  return {
    id: `${followerUid}_${followeeUid}`,
    followerUid,
    followeeUid,
    status,
    members: [followerUid, followeeUid],
    createdAt,
  };
}

/**
 * Aristas esperadas de una amistad bien formada. Es la regla de ADR-FOLLOW-013
 * y el único lugar donde vive.
 */
export function expandToEdges(c: Classification): Edge[] {
  if (!c.wellFormed) return [];
  const { requesterId: r, otherUid: o, status, createdAt } = c;
  return status === "accepted"
    ? [
        makeEdge(r, o, "accepted", createdAt),
        makeEdge(o, r, "accepted", createdAt),
      ]
    : [makeEdge(r, o, "pending", createdAt)];
}

/** Id del PAR (no dirigido), para reportar. Ordenado, a diferencia del edge id. */
export function pairIdOf(a: string, b: string): string {
  return [a, b].sort().join("_");
}

/**
 * Doc ids de `follows` que hay que leer para planificar. Se leen POR DOC ID con
 * `getAll()`, no con queries: lectura directa, sin índices y sin depender de
 * que la colección esté quieta.
 */
export function expectedEdgeIds(friendships: FriendshipDoc[]): string[] {
  const out: string[] = [];
  for (const f of friendships) {
    for (const e of expandToEdges(classifyFriendship(f.data))) out.push(e.id);
  }
  return out;
}

// ---------------------------------------------------------------------------
// planMigration
// ---------------------------------------------------------------------------

/**
 * Planifica la migración. Función pura: no toca Firestore, no lee el reloj, no
 * escribe nada. Todo lo que decide sale de sus tres argumentos.
 *
 * @param friendships colección origen completa (incluidos los malformados)
 * @param existing aristas ya presentes en `follows`, indexadas por doc id
 * @param opts `since` presente ⇒ modo delta sweep (post-flip); ver G1
 */
export function planMigration(
  friendships: FriendshipDoc[],
  existing: Map<string, EdgeData>,
  opts: { since?: Date },
): Plan {
  const plan: Plan = {
    toCreate: [],
    skippedPair: [],
    partialPair: [],
    divergent: [],
    conflicts: [],
    malformed: [],
    stats: {
      friendships: friendships.length,
      accepted: 0,
      pending: 0,
      expectedEdges: 0,
    },
  };
  const since = opts.since;

  for (const doc of friendships) {
    const c = classifyFriendship(doc.data);
    if (!c.wellFormed) {
      // G4 — nunca se escribe, se enumera nominalmente.
      plan.malformed.push({ docId: doc.id, reason: c.reason });
      continue;
    }

    if (c.status === "accepted") plan.stats.accepted++;
    else plan.stats.pending++;

    const expected = expandToEdges(c);
    plan.stats.expectedEdges += expected.length;

    const pairId = pairIdOf(c.requesterId, c.otherUid);
    const present = expected.filter((e) => existing.has(e.id));
    const missing = expected.filter((e) => !existing.has(e.id));

    // G2 — observación pura sobre lo que YA está. Nunca pisa nada; sólo dice
    // en qué difiere lo observado de lo esperado. Corre sobre cualquier par
    // con aristas presentes, incluidos los parciales: una arista corrupta no
    // debería escaparse del reporte nada más que porque su hermana todavía no
    // se escribió — que es exactamente el estado de un batch interrumpido.
    for (const e of present) {
      const d = diffEdge(e, existing.get(e.id) as EdgeData);
      if (d) plan.divergent.push(d);
    }

    // G1 — asimétrica por modo. Se evalúa primero y decide la escritura.
    if (since) {
      if (present.length > 0) {
        // Post-flip: que falte una dirección significa que alguien dejó de
        // seguir. El par entero se saltea y NO se recrea la faltante.
        plan.skippedPair.push({ pairId, reason: "already-migrated" });
        continue;
      }
      // G3 — cero aristas y origen anterior al corte: los dos se dejaron de
      // seguir después del flip. Necesita ojo humano, no una escritura ciega.
      if (c.createdAt.toMillis() < since.getTime()) {
        plan.conflicts.push({
          pairId,
          reason: "no-edges-and-older-than-since",
        });
        continue;
      }
      plan.toCreate.push(...expected);
      continue;
    }

    // Corrida inicial.
    if (missing.length === 0) {
      plan.skippedPair.push({ pairId, reason: "already-migrated" });
      continue;
    }
    if (present.length > 0) {
      plan.partialPair.push({
        pairId,
        present: present.map((e) => e.id),
        created: missing.map((e) => e.id),
      });
    }
    plan.toCreate.push(...missing);
  }

  return plan;
}

/**
 * Compara una arista esperada contra la observada. Devuelve sólo los campos
 * que difieren — el reporte lo lee un humano y "todo el doc" no dice nada.
 */
function diffEdge(
  expected: Edge,
  actual: EdgeData,
): {
  edgeId: string;
  expected: Partial<Edge>;
  actual: Partial<EdgeData>;
} | null {
  const e: Partial<Edge> = {};
  const a: Partial<EdgeData> = {};

  if (actual.status !== expected.status) {
    e.status = expected.status;
    a.status = actual.status;
  }
  if (!sameTimestamp(expected.createdAt, actual.createdAt)) {
    e.createdAt = expected.createdAt;
    a.createdAt = actual.createdAt;
  }
  if (!sameMembers(expected.members, actual.members)) {
    e.members = expected.members;
    a.members = actual.members;
  }

  return Object.keys(e).length === 0
    ? null
    : { edgeId: expected.id, expected: e, actual: a };
}

function isTimestampLike(v: unknown): v is TimestampLike {
  return (
    typeof v === "object" &&
    v !== null &&
    typeof (v as TimestampLike).toMillis === "function"
  );
}

function sameTimestamp(
  a: TimestampLike,
  b: TimestampLike | undefined,
): boolean {
  return isTimestampLike(b) && a.toMillis() === b.toMillis();
}

function sameMembers(a: [string, string], b: string[] | undefined): boolean {
  return (
    Array.isArray(b) &&
    b.length === a.length &&
    a.every((uid, i) => uid === b[i])
  );
}

/**
 * Exit code del plan (design §7.2). `malformed`, `skippedPair`, `partialPair`
 * y —sólo con `--since`— `divergent` son WARNINGS, no error.
 *
 * Una divergencia SIN `--since` es corrida anterior interrumpida o corrupta:
 * nadie tocó `follows` todavía. Con `--since` es actividad legítima del
 * usuario sobre una colección que ya es más nueva que la `friendships`
 * congelada.
 */
export function planExitCode(plan: Plan, opts: { since?: Date }): 0 | 1 {
  if (plan.conflicts.length > 0) return 1;
  if (!opts.since && plan.divergent.length > 0) return 1;
  return 0;
}

// ---------------------------------------------------------------------------
// Manifiesto
// ---------------------------------------------------------------------------

/**
 * Arma el manifiesto de lo efectivamente escrito. Función pura — `appliedAt`
 * entra por parámetro para que el test lo pueda fijar.
 *
 * `created` sale de `writtenEdges`, NO de `plan.toCreate`: ante `ALREADY_EXISTS`
 * el batch se re-planifica doc a doc y lo escrito puede ser un subconjunto de
 * lo planificado. El manifiesto es evidencia, no plan.
 */
export function buildApplyManifest(
  writtenEdges: Edge[],
  plan: Plan,
  opts: { since?: Date; appliedAt?: string },
): ApplyManifest {
  return {
    appliedAt: opts.appliedAt ?? new Date().toISOString(),
    since: opts.since ? opts.since.toISOString() : null,
    created: writtenEdges.map((e) => ({
      ...e,
      members: [...e.members] as [string, string],
    })),
    skippedPair: [...plan.skippedPair],
    partialPair: [...plan.partialPair],
    divergent: [...plan.divergent],
    conflicts: [...plan.conflicts],
    malformed: [...plan.malformed],
  };
}

// ---------------------------------------------------------------------------
// Utilidades
// ---------------------------------------------------------------------------

/** Parte un array en tandas. Sostiene el `getAll()` de a 300 y el batch de 400. */
export function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

const READ_CHUNK = 300; // getAll() por doc id
const WRITE_BATCH = 400; // bajo el cap de 500 de Firestore

function parseSince(argv: string[]): Date | undefined {
  const i = argv.indexOf("--since");
  if (i === -1) return undefined;
  const raw = argv[i + 1];
  const d = raw ? new Date(raw) : new Date(NaN);
  if (Number.isNaN(d.getTime())) {
    throw new Error(`--since requiere un ISO 8601 válido, vino: ${raw}`);
  }
  return d;
}

async function main(): Promise<void> {
  const apply = process.argv.includes("--apply");
  const since = parseSince(process.argv);

  admin.initializeApp();
  const db = admin.firestore();

  console.log(
    `\n=== migrate-friendships-to-follows (${apply ? "APPLY" : "DRY RUN"}` +
      `${since ? `, --since ${since.toISOString()}` : ""}) ===\n`,
  );

  const snap = await db.collection("friendships").get();
  const friendships: FriendshipDoc[] = snap.docs.map((d) => ({
    id: d.id,
    data: d.data() as FriendshipData,
  }));
  console.log(`Leídas ${friendships.length} friendship(s).`);

  // Lectura POR DOC ID, en tandas. Sin queries: no depende de índices ni de
  // que la colección esté quieta.
  const existing = new Map<string, EdgeData>();
  const wanted = [...new Set(expectedEdgeIds(friendships))];
  for (const tanda of chunk(wanted, READ_CHUNK)) {
    const refs = tanda.map((id) => db.collection("follows").doc(id));
    const docs = await db.getAll(...refs);
    for (const d of docs) {
      if (d.exists) existing.set(d.id, d.data() as EdgeData);
    }
  }
  console.log(
    `De ${wanted.length} arista(s) esperada(s), ya existen ${existing.size}.\n`,
  );

  const plan = planMigration(friendships, existing, { since });
  printPlan(plan);

  if (!apply) {
    console.log("\nDRY RUN — no se escribió nada. Re-correr con --apply.");
    process.exit(planExitCode(plan, { since }));
  }

  const exitAntesDeEscribir = planExitCode(plan, { since });
  if (exitAntesDeEscribir !== 0) {
    console.error(
      "\n❌ El plan requiere decisión humana (conflictos o divergencias). " +
        "No se escribe nada.",
    );
    process.exit(exitAntesDeEscribir);
  }

  const written = await writeEdges(db, plan);
  console.log(`\n✅ ${written.length} arista(s) creada(s).`);

  const manifest = buildApplyManifest(written, plan, { since });
  const file = dumpManifest(manifest, since);
  console.log(`Manifiesto: ${file}`);
  console.log(
    "Es el insumo obligatorio de `verify-follows-migration.ts --delta`.",
  );

  process.exit(planExitCode(plan, { since }));
}

/**
 * Escribe `plan.toCreate` en batches, con `create()` y nunca `set()`: si la
 * arista apareció entre el read y el write, falla ruidoso en vez de pisar.
 * Ante `ALREADY_EXISTS` el batch se re-planifica doc a doc y las ya presentes
 * pasan a `skippedPair`.
 */
async function writeEdges(
  db: admin.firestore.Firestore,
  plan: Plan,
): Promise<Edge[]> {
  const written: Edge[] = [];
  const yaSalteados = new Set(plan.skippedPair.map((s) => s.pairId));

  const marcarSalteado = (e: Edge) => {
    const pairId = pairIdOf(e.followerUid, e.followeeUid);
    if (yaSalteados.has(pairId)) return;
    yaSalteados.add(pairId);
    plan.skippedPair.push({ pairId, reason: "already-migrated" });
  };

  for (const tanda of chunk(plan.toCreate, WRITE_BATCH)) {
    const batch = db.batch();
    for (const e of tanda) {
      batch.create(db.collection("follows").doc(e.id), toFirestore(e));
    }
    try {
      await batch.commit();
      written.push(...tanda);
    } catch (err) {
      if (!esAlreadyExists(err)) throw err;
      console.warn(
        `\n⚠️  Un batch de ${tanda.length} falló por ALREADY_EXISTS. ` +
          "Re-planificando doc a doc.",
      );
      for (const e of tanda) {
        try {
          await db.collection("follows").doc(e.id).create(toFirestore(e));
          written.push(e);
        } catch (err2) {
          if (!esAlreadyExists(err2)) throw err2;
          marcarSalteado(e);
        }
      }
    }
  }

  return written;
}

/** El doc tal como va a Firestore: exactamente las 6 keys de design §1.1. */
function toFirestore(e: Edge): Record<string, unknown> {
  return {
    id: e.id,
    followerUid: e.followerUid,
    followeeUid: e.followeeUid,
    status: e.status,
    members: e.members,
    createdAt: e.createdAt,
  };
}

function esAlreadyExists(err: unknown): boolean {
  const code = (err as { code?: unknown } | null)?.code;
  return code === 6 || code === "already-exists";
}

function dumpManifest(manifest: ApplyManifest, since?: Date): string {
  const dir = path.join(__dirname, "migrations");
  fs.mkdirSync(dir, { recursive: true });
  const stamp = manifest.appliedAt.replace(/[:.]/g, "-");
  const file = path.join(dir, `${since ? "delta" : "apply"}-${stamp}.json`);
  fs.writeFileSync(file, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return file;
}

function printPlan(plan: Plan): void {
  const { friendships, accepted, pending, expectedEdges } = plan.stats;
  console.log(
    `${friendships} friendship(s): ${accepted} accepted + ${pending} pending ` +
      `bien formadas (+ ${plan.malformed.length} malformada/s).`,
  );
  console.log(
    `Aristas esperadas = 2 × ${accepted} + ${pending} = ${expectedEdges}.`,
  );
  console.log(`A crear ahora: ${plan.toCreate.length}.\n`);

  if (plan.malformed.length > 0) {
    console.warn(`⚠️  ${plan.malformed.length} malformada(s) — EXCLUIDAS:`);
    for (const m of plan.malformed) console.warn(`   ${m.docId}: ${m.reason}`);
  }
  if (plan.partialPair.length > 0) {
    console.warn(
      `\n⚠️  ${plan.partialPair.length} par(es) A MEDIAS — hubo una corrida ` +
        "interrumpida. Se completan las aristas faltantes:",
    );
    for (const p of plan.partialPair) {
      console.warn(
        `   ${p.pairId}: presente [${p.present}] → se crea [${p.created}]`,
      );
    }
  }
  if (plan.skippedPair.length > 0) {
    console.log(`\n${plan.skippedPair.length} par(es) ya migrado(s).`);
  }
  if (plan.divergent.length > 0) {
    console.warn(`\n⚠️  ${plan.divergent.length} arista(s) DIVERGENTE(S):`);
    for (const d of plan.divergent) {
      console.warn(
        `   ${d.edgeId}: esperado ${JSON.stringify(d.expected)} ` +
          `≠ actual ${JSON.stringify(d.actual)}`,
      );
    }
  }
  if (plan.conflicts.length > 0) {
    console.error(`\n❌ ${plan.conflicts.length} CONFLICTO(S):`);
    for (const c of plan.conflicts)
      console.error(`   ${c.pairId}: ${c.reason}`);
  }
}

// Sólo corre invocado directamente (ts-node scripts/...), NO cuando un test
// importa las funciones puras.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(2);
  });
}
