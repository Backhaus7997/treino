/**
 * sendFcm — shared FCM dispatch helper for TREINO Cloud Functions.
 *
 * Reads `fcmTokens` per uid from Firestore, fans out to FCM via
 * `sendEachForMulticast`, and cleans up stale tokens per-token on error.
 *
 * Design:
 *   - Pure function shape with optional `messaging` injection for tests (ADR-PN-004).
 *   - Stale token cleanup on `messaging/registration-token-not-registered` and
 *     `messaging/invalid-registration-token` per BatchResponse inspection.
 *   - Empty or absent `fcmTokens` arrays are skipped silently with a log line.
 *   - Body length enforcement lives in the per-trigger CFs, NOT here.
 *
 * REQ-PN-CF-001. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

const STALE_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/** Input shape accepted by sendFcm. */
export interface SendFcmInput {
  /** Recipient user IDs. fcmTokens are read from users/{uid} per uid. */
  uids: string[];
  /** FCM notification payload (title + body). */
  notification: {
    title: string;
    body: string;
  };
  /** Arbitrary string key-value pairs forwarded as the FCM data payload. */
  data: Record<string, string>;
}

/** Aggregated send result returned by sendFcm. */
export interface SendFcmResult {
  successCount: number;
  failureCount: number;
}

/**
 * Sends an FCM notification to all tokens belonging to the given uids.
 *
 * @param app       - Admin SDK app (injected for testability, mirrors recomputeAggregate).
 * @param input     - Recipient uids, notification payload, and data payload.
 * @param messaging - Optional messaging instance; defaults to admin.messaging(app).
 *                    Inject a mock in tests to avoid real FCM calls.
 */
export async function sendFcm(
  app: admin.app.App,
  input: SendFcmInput,
  messaging?: admin.messaging.Messaging,
): Promise<SendFcmResult> {
  const { uids, notification, data } = input;

  // Short-circuit: no recipients.
  if (uids.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  const db = admin.firestore(app);
  const msg = messaging ?? admin.messaging(app);

  // 1. Read fcmTokens per uid in parallel.
  //    Build a flat list of { token, ownerUid } preserving the mapping for stale cleanup.
  type TokenEntry = { token: string; ownerUid: string };

  const perUidTokens = await Promise.all(
    uids.map(async (uid): Promise<TokenEntry[]> => {
      const snap = await db.collection("users").doc(uid).get();
      const tokens: string[] = snap.exists
        ? ((snap.data()?.fcmTokens as string[] | undefined) ?? [])
        : [];

      if (tokens.length === 0) {
        logger.info(`sendFcm: no tokens for uid=${uid}, skipping`);
        return [];
      }

      return tokens.map((token) => ({ token, ownerUid: uid }));
    }),
  );

  const entries: TokenEntry[] = perUidTokens.flat();

  // 2. If all uids had empty arrays, nothing to send.
  if (entries.length === 0) {
    return { successCount: 0, failureCount: 0 };
  }

  // 3. Dispatch a single multicast call with the flat token list.
  const tokens = entries.map((e) => e.token);
  logger.info(
    `sendFcm: dispatching to ${tokens.length} tokens for ${uids.length} uids`,
  );
  const batchResponse = await msg.sendEachForMulticast({
    tokens,
    notification,
    data,
  });

  // 4. Inspect per-token errors; remove stale tokens from Firestore.
  const staleCleanups: Promise<void>[] = [];

  batchResponse.responses.forEach((resp, idx) => {
    const errorCode = resp.error?.code;
    if (errorCode && STALE_TOKEN_CODES.has(errorCode)) {
      const { token, ownerUid } = entries[idx];
      logger.info(
        `sendFcm: removing stale token for uid=${ownerUid}, code=${errorCode}`,
      );
      staleCleanups.push(
        db
          .collection("users")
          .doc(ownerUid)
          .update({ fcmTokens: FieldValue.arrayRemove(token) })
          .then(() => undefined),
      );
    } else if (errorCode) {
      // Non-stale error: log as warn so we can see what FCM rejected.
      const { ownerUid } = entries[idx];
      const message = resp.error?.message ?? "<no message>";
      logger.warn(
        `sendFcm: non-stale error uid=${ownerUid} code=${errorCode} msg=${message}`,
      );
    }
  });

  if (staleCleanups.length > 0) {
    await Promise.all(staleCleanups);
  }

  // 5. Log aggregated result then return.
  logger.info(
    `sendFcm: result success=${batchResponse.successCount} failure=${batchResponse.failureCount}`,
  );
  return {
    successCount: batchResponse.successCount,
    failureCount: batchResponse.failureCount,
  };
}
