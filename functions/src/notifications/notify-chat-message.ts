/**
 * notifyOnChatMessage — Cloud Function for TREINO.
 *
 * Fires on new messages in `chats/{chatId}/messages/{messageId}`.
 * Notifies all chat members except the sender via sendFcm.
 *
 * Design:
 *   - ADR-PN-005: members ≠ senderId are recipients.
 *   - SenderName from userPublicProfiles/{senderId}.displayName ?? 'Alguien'.
 *   - Body: "${senderName}: ${displayText}" where displayText is:
 *       · caption (truncated 100) if text non-empty
 *       · '📷 Foto' if mediaType === 'image'
 *       · '🎥 Video' if mediaType === 'video'
 *       · '' for unknown/missing mediaType with empty text (no crash)
 *   - deepLink: "/coach/chat/${chatId}?other=${senderId}".
 *   - All user-facing strings in es-AR.
 *
 * REQ-PN-CF-002, REQ-CHATMEDIA-012. Fase 6 Etapa 2.
 */

import * as admin from "firebase-admin";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { sendFcm } from "./send-fcm";

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

/**
 * Truncates text to maxLen chars, appending '…' if truncated.
 */
function truncate(text: string, maxLen: number): string {
  if (text.length <= maxLen) return text;
  return text.slice(0, maxLen) + "…";
}

/**
 * Pure handler extracted for jest testability (mirrors recomputeAggregate pattern).
 *
 * @param app         - Admin SDK app.
 * @param chatId      - Chat document ID.
 * @param messageData - Raw message document data.
 * @param messaging   - Optional messaging instance for test injection.
 */
export async function notifyOnChatMessageHandler(
  app: admin.app.App,
  chatId: string,
  messageData: Record<string, unknown>,
  messaging?: admin.messaging.Messaging,
): Promise<void> {
  const db = admin.firestore(app);

  const senderId = messageData.senderId as string | undefined;
  const text = (messageData.text as string | undefined) ?? "";
  const mediaType = (messageData.mediaType as string | undefined) ?? "";

  if (!senderId) {
    logger.warn("notifyOnChatMessage: senderId missing, skipping", { chatId });
    return;
  }

  // 1. Read chat members.
  const chatSnap = await db.collection("chats").doc(chatId).get();
  if (!chatSnap.exists) {
    logger.warn("notifyOnChatMessage: chat document not found", { chatId });
    return;
  }

  const members: string[] = (chatSnap.data()?.members as string[] | undefined) ?? [];
  const recipients = members.filter((m) => m !== senderId);

  if (recipients.length === 0) {
    logger.info("notifyOnChatMessage: no recipients (sender is only member)", {
      chatId,
      senderId,
    });
    return;
  }

  // 2. Read sender display name.
  const profileSnap = await db
    .collection("userPublicProfiles")
    .doc(senderId)
    .get();
  const senderName: string =
    (profileSnap.data()?.displayName as string | undefined) ?? "Alguien"; // i18n: Fase 6 Etapa 2

  // 3. Build body — caption (truncated at 100 chars) wins; for a media-only
  //    message fall back to a placeholder so the push body is never empty.
  const mediaFallback =
    mediaType === "image" ? "📷 Foto" : mediaType === "video" ? "🎥 Video" : "";
  const displayText = text.length > 0 ? truncate(text, 100) : mediaFallback;
  const body = `${senderName}: ${displayText}`;

  // 4. Build deepLink.
  const deepLink = `/coach/chat/${chatId}?other=${senderId}`;

  // 5. Dispatch via sendFcm.
  await sendFcm(
    app,
    {
      uids: recipients,
      notification: {
        title: "TREINO", // i18n: Fase 6 Etapa 2
        body,
      },
      data: { deepLink, senderId },
    },
    messaging,
  );
}

/**
 * Cloud Function trigger.
 * Deployed to southamerica-east1 per ADR-PN-005.
 */
export const notifyOnChatMessage = onDocumentCreated(
  {
    document: "chats/{chatId}/messages/{messageId}",
    region: "southamerica-east1",
  },
  async (event) => {
    const messageData = event.data?.data() as Record<string, unknown> | undefined;
    if (!messageData) {
      logger.warn("notifyOnChatMessage: no message data");
      return;
    }

    const { chatId } = event.params;
    await notifyOnChatMessageHandler(getApp(), chatId, messageData);
  },
);
