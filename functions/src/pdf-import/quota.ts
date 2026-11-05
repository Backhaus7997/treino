/**
 * quota.ts — el cupo semanal y diario de imports de PDF del PF
 * (`TIER_PDF_IMPORT_LIMITS`), contado en `pdfImportUsage/{uid}`.
 *
 * ─── La forma del documento ─────────────────────────────────────────────────
 *
 *   { weekKey: "2026-10-19", weekCount: 3, dayKey: "2026-10-22", dayCount: 1,
 *     refundDayKey: "2026-10-22", refundDayCount: 1, updatedAt: Timestamp }
 *
 * `weekKey` es el LUNES de la semana y `dayKey` el dia, los dos en
 * `America/Argentina/Buenos_Aires`. No hay barrido que resetee nada: un
 * contador cuya clave ya no es la de hoy vale cero. Asi el reset es exacto al
 * minuto y no depende de que un cron haya corrido.
 *
 * ─── Por que se descuenta ANTES de llamar al LLM ────────────────────────────
 *
 * Si se descontara al final, N llamadas en paralelo pasarian todas el chequeo
 * con el mismo contador viejo y el cupo no cortaria la rafaga, que es
 * justamente lo caro. La transaccion serializa: la que llega con el cupo justo
 * gana, la siguiente rebota. Si el import falla por error nuestro, `refund`
 * devuelve la unidad.
 *
 * ─── Por que la devolucion tiene tope ───────────────────────────────────────
 *
 * Un fallo que llego DESPUES de que el modelo empezo a generar (salida
 * invalida, truncada, timeout) ya gasto tokens, y cuestan igual. Si el cupo
 * volviera siempre, un PDF que haga fallar al modelo se podria reintentar sin
 * limite: cada vuelta gasta hasta el tope de salida y no cuesta un import. Por
 * eso esas devoluciones ("facturables") se acotan a `MAX_BILLED_REFUNDS_PER_DAY`
 * por dia (`refundDayKey` / `refundDayCount`); pasado el tope el fallo se
 * queda con el cupo y el costo total por dia queda en `limite diario + 2`. Los
 * fallos donde el proveedor ni llego a responder (HTTP de error, red) no
 * gastan nada y se devuelven siempre.
 *
 * El doc lo escribe solo el Admin SDK: `firestore.rules` le niega toda
 * escritura al cliente (`pdfImportUsage/{uid}`).
 */
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { SubscriptionTier, TIER_PDF_IMPORT_LIMITS } from "../subscriptions/tier-config";

export const PDF_IMPORT_USAGE_COLLECTION = "pdfImportUsage";

/**
 * Cuantas veces por dia se devuelve el cupo de un fallo que ya gasto tokens.
 * Cubre el mal rato ocasional de un modelo (una salida invalida, un timeout)
 * sin que el reintento sea gratis para siempre.
 */
export const MAX_BILLED_REFUNDS_PER_DAY = 2;
const TIME_ZONE = "America/Argentina/Buenos_Aires";
/**
 * Argentina no tiene horario de verano desde 2009. El offset solo se usa para
 * convertir la medianoche local de `resetsAt` a un instante; las claves salen
 * de `Intl` con la zona, asi que un cambio de huso solo correria `resetsAt`.
 */
const ART_OFFSET = "-03:00";

export interface QuotaKeys {
  weekKey: string;
  dayKey: string;
}

export interface QuotaSnapshot {
  usedThisWeek: number;
  limitWeekly: number;
  usedToday: number;
  limitDaily: number;
}

/** El dia calendario en Buenos Aires, como `YYYY-MM-DD`. */
export function artDateKey(now: Date): string {
  // en-CA formatea como YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** Suma dias a una clave `YYYY-MM-DD` (aritmetica de calendario, en UTC). */
function addDays(key: string, days: number): string {
  const d = new Date(`${key}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Las claves de semana (lunes) y dia para un instante. */
export function quotaKeys(now: Date): QuotaKeys {
  const dayKey = artDateKey(now);
  // getUTCDay sobre la medianoche UTC de la fecha local: 0 = domingo.
  const weekday = new Date(`${dayKey}T00:00:00Z`).getUTCDay();
  const sinceMonday = (weekday + 6) % 7;
  return { weekKey: addDays(dayKey, -sinceMonday), dayKey };
}

/** Cuando se renueva cada cupo, como ISO (la medianoche de Buenos Aires). */
export function resetsAt(keys: QuotaKeys, scope: "week" | "day"): string {
  const next = scope === "week" ? addDays(keys.weekKey, 7) : addDays(keys.dayKey, 1);
  return new Date(`${next}T00:00:00${ART_OFFSET}`).toISOString();
}

interface UsageDoc {
  weekKey?: unknown;
  weekCount?: unknown;
  dayKey?: unknown;
  dayCount?: unknown;
  refundDayKey?: unknown;
  refundDayCount?: unknown;
}

function countFor(
  doc: UsageDoc | undefined,
  key: string,
  field: "week" | "day" | "refundDay",
): number {
  const docKey = field === "week" ? doc?.weekKey : field === "day" ? doc?.dayKey : doc?.refundDayKey;
  const count = field === "week" ? doc?.weekCount : field === "day" ? doc?.dayCount : doc?.refundDayCount;
  if (docKey !== key || typeof count !== "number" || !Number.isFinite(count)) return 0;
  return Math.max(0, Math.floor(count));
}

/**
 * Descuenta una unidad de los dos cupos en una transaccion, o tira
 * `resource-exhausted` con `{ scope, resetsAt }`. Si se agotaron los dos,
 * informa la SEMANA: es la que tarda mas en volver, y decirle "mañana" al PF
 * seria mentirle.
 */
export async function consumeQuota(
  db: Firestore,
  uid: string,
  tier: SubscriptionTier,
  now: Date,
): Promise<{ keys: QuotaKeys; snapshot: QuotaSnapshot }> {
  const limits = TIER_PDF_IMPORT_LIMITS[tier] ?? TIER_PDF_IMPORT_LIMITS.free;
  const keys = quotaKeys(now);
  const ref = db.collection(PDF_IMPORT_USAGE_COLLECTION).doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const doc = snap.data() as UsageDoc | undefined;
    const week = countFor(doc, keys.weekKey, "week");
    const day = countFor(doc, keys.dayKey, "day");

    if (week >= limits.weekly) {
      throw new HttpsError("resource-exhausted", "Weekly PDF import quota exhausted.", {
        scope: "week",
        resetsAt: resetsAt(keys, "week"),
      });
    }
    if (day >= limits.daily) {
      throw new HttpsError("resource-exhausted", "Daily PDF import quota exhausted.", {
        scope: "day",
        resetsAt: resetsAt(keys, "day"),
      });
    }

    // `merge`: el doc tambien lleva el contador de devoluciones facturables, y
    // pisarlo aca lo pondria en cero en cada import y dejaria el tope sin efecto.
    tx.set(ref, {
      weekKey: keys.weekKey,
      weekCount: week + 1,
      dayKey: keys.dayKey,
      dayCount: day + 1,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return {
      keys,
      snapshot: {
        usedThisWeek: week + 1,
        limitWeekly: limits.weekly,
        usedToday: day + 1,
        limitDaily: limits.daily,
      },
    };
  });
}

/**
 * Devuelve la unidad que `consumeQuota` desconto, si su semana o su dia
 * siguen vigentes. Si el import cruzo la medianoche, ese dia ya no cuenta y
 * no hay nada que devolver de ese lado (descontar del dia nuevo le regalaria
 * un import). Nunca deja un contador por debajo de cero.
 *
 * `billed`: el fallo llego despues de que el modelo empezo a generar, o sea
 * que ya costo. Esas devoluciones se acotan a `MAX_BILLED_REFUNDS_PER_DAY`
 * por dia (ver el encabezado); pasado el tope no se devuelve nada. Devuelve
 * `true` si devolvio la unidad.
 */
export async function refundQuota(
  db: Firestore,
  uid: string,
  keys: QuotaKeys,
  opts: { billed?: boolean } = {},
): Promise<boolean> {
  const ref = db.collection(PDF_IMPORT_USAGE_COLLECTION).doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const doc = snap.data() as UsageDoc;
    const update: Record<string, unknown> = {};
    if (opts.billed) {
      // Un fallo del dia anterior que termina pasada la medianoche, con el
      // contador del dia nuevo ya escrito: no se devuelve ni se pisa ese
      // contador (si no, el dia nuevo recuperaria un tope que ya gasto). Las
      // claves son `YYYY-MM-DD`, asi que comparar strings ordena por fecha.
      const recordedDay = typeof doc.refundDayKey === "string" ? doc.refundDayKey : "";
      if (recordedDay > keys.dayKey) return false;
      const refunded = countFor(doc, keys.dayKey, "refundDay");
      if (refunded >= MAX_BILLED_REFUNDS_PER_DAY) return false;
      update.refundDayKey = keys.dayKey;
      update.refundDayCount = refunded + 1;
    }
    const week = countFor(doc, keys.weekKey, "week");
    const day = countFor(doc, keys.dayKey, "day");
    if (week > 0) update.weekCount = week - 1;
    if (day > 0) update.dayCount = day - 1;
    if (week === 0 && day === 0) return false;
    update.updatedAt = FieldValue.serverTimestamp();
    tx.update(ref, update);
    return true;
  });
}
