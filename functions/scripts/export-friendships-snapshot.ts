/**
 * export-friendships-snapshot.ts — cuenta y exporta la colección `friendships`
 * completa antes de migrarla a `follows`.
 *
 * Es la PRIMERA tarea del change `follow-model` (hitos M-00 y M-01), y corre
 * antes que cualquier otra cosa.
 *
 * ## Por qué
 *
 * La migración a follow asimétrico es irreversible en un sentido incómodo: si
 * se pierde el mapeo de quién seguía a quién, no hay forma de reconstruirlo —
 * no vive en ningún otro lado. Este archivo ES el mecanismo de reversibilidad:
 * aunque el script de migración tuviera un bug destructivo, el original queda
 * en disco, fuera de Firestore.
 *
 * Por eso el snapshot NO OPINA sobre el dato. No filtra documentos malformados
 * (la migración sí los excluye del `--apply`, pero acá perderlos sería
 * definitivo), no normaliza campos, no reordena. Copia lo que hay.
 *
 * Hace además el gate de volumen M-00: un `.count()` sobre la colección, cuyo
 * número se registra en el reporte de apply. El dueño ya confirmó (2026-08-04)
 * que los uids son del equipo y de testers conocidos —lo que fija la Rama A de
 * ADR-FOLLOW-010—, pero la confirmación fija la decisión de diseño y el conteo
 * es la evidencia que la sostiene: si alguna vez el número real contradijera la
 * confirmación, el plan pasa a Rama B y vuelve a `sdd-design`.
 *
 * ## Seguridad
 *
 * Solo lee. No escribe absolutamente nada en Firestore, ni con `--apply` ni sin
 * él: no existe tal flag acá.
 *
 * Correr con credenciales admin, desde functions/:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/export-friendships-snapshot.ts
 */

import * as fs from "fs";
import * as path from "path";

import * as admin from "firebase-admin";

/** Un documento crudo de `friendships`, tal como vino de Firestore. */
export interface RawDoc {
  id: string;
  data: Record<string, unknown>;
}

/** Lo que se escribe a disco. */
export interface SnapshotPayload {
  exportedAt: string;
  count: number;
  docs: RawDoc[];
}

/**
 * Arma el payload del snapshot. Función pura — se testea sin Firestore.
 *
 * `exportedAt` entra por parámetro en vez de tomarse de `Date.now()` adentro
 * para que el test pueda fijarlo; el default cubre el uso real.
 *
 * `count` se deriva de `docs.length` y NO se recibe de afuera a propósito: la
 * verificación de paridad de la migración (M-06 ①) compara contra este número,
 * así que no puede describir algo distinto de lo que el archivo realmente tiene.
 */
export function buildSnapshotPayload(
  docs: RawDoc[],
  exportedAt: string = new Date().toISOString(),
): SnapshotPayload {
  const copia = docs.map((d) => ({ id: d.id, data: { ...d.data } }));
  return {
    exportedAt,
    count: copia.length,
    docs: copia,
  };
}

async function main(): Promise<void> {
  admin.initializeApp();
  const db = admin.firestore();

  // M-00 — gate de volumen. Una sola read-unit, sin traerse la colección.
  const agg = await db.collection("friendships").count().get();
  const declarado = agg.data().count;
  console.log(`M-00 · friendships.count() = ${declarado}`);

  // M-01 — dump completo.
  const snap = await db.collection("friendships").get();
  const payload = buildSnapshotPayload(
    snap.docs.map((d) => ({ id: d.id, data: d.data() })),
  );

  if (payload.count !== declarado) {
    // No es fatal —alguien pudo escribir entre las dos lecturas—, pero tiene
    // que quedar registrado: el snapshot es la referencia de todo lo que sigue.
    console.warn(
      `⚠️  El .count() dio ${declarado} y el dump trajo ${payload.count}. ` +
        `Hubo escrituras entre ambas lecturas, o la colección se está moviendo. ` +
        `El número que vale para la paridad es el del dump (${payload.count}).`,
    );
  }

  const dir = path.join(__dirname, "migrations");
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(
    dir,
    `friendships-snapshot-${payload.exportedAt.replace(/[:.]/g, "-")}.json`,
  );
  fs.writeFileSync(file, `${JSON.stringify(payload, null, 2)}\n`, "utf8");

  console.log(`M-01 · ${payload.count} doc(s) exportado(s) a:\n  ${file}`);
  console.log(
    "\nRegistrar en el reporte de apply: el número de M-00 y esta ruta.",
  );
}

// Solo corre invocado directamente (ts-node scripts/...), NO cuando un test
// importa el builder puro.
if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
