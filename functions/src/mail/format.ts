/**
 * Shared formatting helpers for TREINO transactional email.
 *
 * Design:
 *   - Dates are rendered in America/Argentina/Buenos_Aires. Cloud Functions run
 *     in UTC, so a session at 19:00 ART would otherwise print as 22:00 — the
 *     kind of error a reader blames on the product, not the timezone.
 *   - Names resolve from `userPublicProfiles/{uid}.displayName`, the same source
 *     `notifyOverduePayments` reads, with the same fallback copy.
 */

import * as admin from "firebase-admin";

/** IANA zone for Argentina. No DST since 2009, but let Intl own that. */
const AR_TIME_ZONE = "America/Argentina/Buenos_Aires";
const AR_LOCALE = "es-AR";

/** Fallback when a profile has no display name, matching the FCM copy. */
const TRAINER_FALLBACK = "tu entrenador";
const ATHLETE_FALLBACK = "un atleta";

/** Accepts the several shapes a Firestore date arrives in across triggers. */
export type DateLike =
  | admin.firestore.Timestamp
  | Date
  | number
  | { _seconds: number }
  | undefined;

/** Normalises a Firestore date field to a JS Date, or null when unusable. */
export function toDate(value: DateLike): Date | null {
  if (value == null) return null;
  if (value instanceof Date) return value;
  if (typeof value === "number") return new Date(value);
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  // Plain object shape — how a Timestamp looks after a JSON round-trip.
  if (typeof value === "object" && "_seconds" in value) {
    return new Date(value._seconds * 1000);
  }
  return null;
}

/** "martes 26 de agosto" — weekday and month in es-AR, ART. */
export function formatDateAR(value: DateLike): string {
  const date = toDate(value);
  if (!date) return "";
  return new Intl.DateTimeFormat(AR_LOCALE, {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: AR_TIME_ZONE,
  }).format(date);
}

/** "19:00" — 24-hour clock, ART. */
export function formatTimeAR(value: DateLike): string {
  const date = toDate(value);
  if (!date) return "";
  return new Intl.DateTimeFormat(AR_LOCALE, {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone: AR_TIME_ZONE,
  }).format(date);
}

/** "26/08/2026" — short numeric date, ART. */
export function formatShortDateAR(value: DateLike): string {
  const date = toDate(value);
  if (!date) return "";
  return new Intl.DateTimeFormat(AR_LOCALE, {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    timeZone: AR_TIME_ZONE,
  }).format(date);
}

/** "2026-08-26" in ART — used to scope a daily-recurring dedupe key. */
export function artDateKey(value: DateLike): string {
  const date = toDate(value) ?? new Date();
  // en-CA yields ISO-ordered yyyy-mm-dd, which sorts correctly as a string.
  return new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    timeZone: AR_TIME_ZONE,
  }).format(date);
}

/**
 * "$ 25.000" — whole pesos, es-AR grouping.
 *
 * `Payment.amountArs` is an int of whole pesos, so fraction digits are pinned
 * to zero; the default two would render "$ 25.000,00" for an amount that has
 * no centavos to begin with.
 */
export function formatArs(amountArs: number | undefined): string {
  if (typeof amountArs !== "number" || !Number.isFinite(amountArs)) return "";
  return new Intl.NumberFormat(AR_LOCALE, {
    style: "currency",
    currency: "ARS",
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amountArs);
}

/**
 * Reads a display name from the public profile.
 *
 * @param app      - Admin SDK app.
 * @param uid      - Whose name to read.
 * @param fallback - Copy used when the profile or the field is missing.
 */
export async function resolveDisplayName(
  app: admin.app.App,
  uid: string,
  fallback: string,
): Promise<string> {
  try {
    const snap = await admin
      .firestore(app)
      .collection("userPublicProfiles")
      .doc(uid)
      .get();
    return (snap.data()?.displayName as string | undefined) ?? fallback;
  } catch {
    return fallback;
  }
}

/** `resolveDisplayName` with the trainer-facing fallback. */
export function resolveTrainerName(
  app: admin.app.App,
  uid: string,
): Promise<string> {
  return resolveDisplayName(app, uid, TRAINER_FALLBACK);
}

/** `resolveDisplayName` with the athlete-facing fallback. */
export function resolveAthleteName(
  app: admin.app.App,
  uid: string,
): Promise<string> {
  return resolveDisplayName(app, uid, ATHLETE_FALLBACK);
}
