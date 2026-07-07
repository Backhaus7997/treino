/**
 * audit-w1-mis-keyed-payments.ts — READ-ONLY audit for the W1 double-charge bug.
 *
 * Before the W1 fix (period keys were derived in UTC, not ART), a "marcar
 * pagado" done in the 21:00–23:59 ART window on a period's last day was stored
 * with the NEXT period's key — UTC had already rolled over. That orphans the
 * real period's pending charge (it stays unpaid forever) and leaves a phantom
 * "paid" one period ahead.
 *
 * Signature used here (precise, ~zero false positives): the client mark-paid
 * ALWAYS keys to "now", so a PAID payment whose stored periodKey differs from
 * the key recomputed in ART from its OWN paidAt means the boundary bug hit — it
 * is NOT a late payment (late payments still key to their own paidAt). For each
 * hit we also report whether the ART period's pending charge is orphaned.
 *
 * This script NEVER writes. Review the output by hand; money data is never
 * auto-fixed.
 *
 * Run with admin credentials, from the functions/ directory:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json \
 *     npx ts-node scripts/audit-w1-mis-keyed-payments.ts
 */

import * as admin from "firebase-admin";
import {
  argentinaNow,
  isoWeekPeriodKey,
} from "../src/payments/generate-due-payments";

/** ART period key for `instant`, in the same format (`YYYY-MM` / `YYYY-Www`) as
 * the stored key so the two are directly comparable. */
function artKeyLike(storedKey: string, instant: Date): string {
  const art = argentinaNow(instant);
  if (storedKey.includes("W")) {
    return isoWeekPeriodKey(art);
  }
  const y = art.getUTCFullYear();
  const m = (art.getUTCMonth() + 1).toString().padStart(2, "0");
  return `${y}-${m}`;
}

interface PaymentRow {
  id: string;
  trainerId?: string;
  athleteId?: string;
  amountArs?: number;
  status?: string;
  periodKey?: string;
  paidAt?: admin.firestore.Timestamp;
}

async function main(): Promise<void> {
  admin.initializeApp();
  const db = admin.firestore();

  const snap = await db.collection("payments").get();
  const all: PaymentRow[] = snap.docs.map(
    (d) => ({ id: d.id, ...(d.data() as Omit<PaymentRow, "id">) }),
  );

  // Index pending charges by trainer|athlete|periodKey for the orphan lookup.
  const pendingByKey = new Map<string, PaymentRow>();
  for (const p of all) {
    if (p.status === "pending" && p.trainerId && p.athleteId && p.periodKey) {
      pendingByKey.set(`${p.trainerId}|${p.athleteId}|${p.periodKey}`, p);
    }
  }

  const flagged: Array<{
    paid: PaymentRow;
    artKey: string;
    orphanPendingId?: string;
  }> = [];

  for (const p of all) {
    if (p.status !== "paid" || !p.periodKey || !p.paidAt) continue;
    const artKey = artKeyLike(p.periodKey, p.paidAt.toDate());
    if (artKey === p.periodKey) continue; // key is ART-consistent — not the bug

    const orphan = pendingByKey.get(`${p.trainerId}|${p.athleteId}|${artKey}`);
    flagged.push({ paid: p, artKey, orphanPendingId: orphan?.id });
  }

  console.log(`\nW1 audit — scanned ${all.length} payments`);
  if (flagged.length === 0) {
    console.log("✅ No mis-keyed paid payments found. Nothing to correct.\n");
    return;
  }

  console.log(
    `\n⚠️  ${flagged.length} PAID payment(s) whose periodKey != its ART key at paidAt:\n`,
  );
  for (const f of flagged) {
    const p = f.paid;
    console.log(
      [
        `  paymentId=${p.id}`,
        `trainer=${p.trainerId}`,
        `athlete=${p.athleteId}`,
        `amount=${p.amountArs}`,
        `stored=${p.periodKey}`,
        `art=${f.artKey}`,
        `paidAt=${p.paidAt?.toDate().toISOString()}`,
        f.orphanPendingId
          ? `orphanPending=${f.orphanPendingId} (the ART period is still unpaid)`
          : `orphanPending=none`,
      ].join("  "),
    );
  }
  console.log(
    "\nReview by hand. Likely correction: re-key the paid payment to its ART " +
      "key and settle/remove the orphaned pending. Do NOT auto-fix money.\n",
  );
}

main().catch((e) => {
  console.error("audit failed:", e);
  process.exitCode = 1;
});
