/**
 * Enforces that each FCM registration token belongs to at most one user.
 *
 * A newly registered token is authoritative for the user who added it. The
 * handler removes that token from every other user document. Removals never
 * trigger more work, which makes the function safe when its own writes fire
 * this trigger again.
 */
import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

type UserData = Record<string, unknown>;

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

function tokensOf(data: UserData | undefined): Set<string> {
  const raw = data?.fcmTokens;
  if (!Array.isArray(raw)) return new Set();
  return new Set(raw.filter((token): token is string => typeof token === "string"));
}

/**
 * Returns only tokens added by this write. An unchanged array or a
 * removal-only write returns an empty list, which is the trigger's anti-loop
 * guard.
 */
export function addedFcmTokens(
  before: UserData | undefined,
  after: UserData | undefined,
): string[] {
  const beforeTokens = tokensOf(before);
  const afterTokens = tokensOf(after);
  return [...afterTokens].filter((token) => !beforeTokens.has(token));
}

/** Purely-invokable handler, extracted from the Firestore event wrapper. */
export async function reassignFcmTokenHandler(
  app: admin.app.App,
  uid: string,
  before: UserData | undefined,
  after: UserData | undefined,
): Promise<void> {
  // Mandatory fast path: users/{uid} is written for many unrelated features.
  // An empty result also covers removal-only writes caused by this function,
  // preventing a recursively billed trigger loop.
  const addedTokens = addedFcmTokens(before, after);
  if (addedTokens.length === 0) return;

  const db = admin.firestore(app);
  const removalsByUser = new Map<string, Set<string>>();

  for (const token of addedTokens) {
    const owners = await db
      .collection("users")
      .where("fcmTokens", "array-contains", token)
      .get();

    for (const owner of owners.docs) {
      if (owner.id === uid) continue;
      const tokens = removalsByUser.get(owner.id) ?? new Set<string>();
      tokens.add(token);
      removalsByUser.set(owner.id, tokens);
    }
  }

  if (removalsByUser.size > 0) {
    const batch = db.batch();
    for (const [sourceUid, tokens] of removalsByUser) {
      batch.update(
        db.collection("users").doc(sourceUid),
        { fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens) },
      );
    }
    await batch.commit();
  }

  logger.info("reassignFcmToken: completed", {
    destinationUid: uid,
    reassignedTokenCount: new Set(
      [...removalsByUser.values()].flatMap((tokens) => [...tokens]),
    ).size,
    sourceUids: [...removalsByUser.keys()],
  });

  // No one-off migration is needed: active devices reclaim their token on the
  // next registration, while sendFcm already removes tokens FCM reports as
  // stale/unregistered. Tokens that never register again age out that way.
}

export const reassignFcmToken = onDocumentWritten(
  {
    document: "users/{uid}",
    region: "southamerica-east1",
  },
  async (event) => {
    const before = event.data?.before?.data() as UserData | undefined;
    const after = event.data?.after?.data() as UserData | undefined;
    await reassignFcmTokenHandler(
      getApp(),
      event.params.uid as string,
      before,
      after,
    );
  },
);
