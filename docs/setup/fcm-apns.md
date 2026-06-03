# FCM APNs Auth Key Setup

This document describes the manual steps required to configure Apple Push Notification service (APNs) authentication for TREINO on iOS.

This is an **out-of-band prerequisite for iOS smoke testing only** — it is NOT required for code review or merge of any PR. Real FCM delivery to iOS devices is blocked until this is done; all other functionality (emulator tests, Android FCM, CF trigger logic) is independent.

---

## Prerequisites

- Access to the Apple Developer Program account for TREINO.
- Access to the Firebase Console project for TREINO (Firebase Project ID: `treino-dev` or production equivalent).

---

## Step 1: Create an APNs Auth Key in Apple Developer Console

1. Open [Apple Developer Console](https://developer.apple.com) → **Certificates, Identifiers & Profiles**.
2. In the left sidebar, select **Keys**.
3. Click the **+** button to create a new key.
4. Give the key a descriptive name (e.g. `TREINO FCM APNs Key`).
5. Check **Apple Push Notifications service (APNs)**.
6. Click **Continue**, then **Register**.
7. **Download the `.p8` file immediately** — Apple only allows one download. Store it securely (e.g. 1Password team vault).
8. Note the **Key ID** displayed (10-character alphanumeric string).

---

## Step 2: Find Your Apple Team ID

1. In Apple Developer Console, click your account name in the top-right corner → **Membership details**.
2. Note the **Team ID** (10-character alphanumeric string).

---

## Step 3: Upload the APNs Auth Key to Firebase

1. Open the [Firebase Console](https://console.firebase.google.com) → select the TREINO project.
2. Go to **Project Settings** (gear icon) → **Cloud Messaging** tab.
3. Under **Apple app configuration**, find the iOS app entry.
4. In the **APNs Authentication Key** section, click **Upload**.
5. Select the `.p8` file downloaded in Step 1.
6. Enter the **Key ID** from Step 1.
7. Enter the **Team ID** from Step 2.
8. Click **Upload**.

---

## Step 4: Smoke Test (after PR#2b merges)

Once PR#2b is merged and APNs is configured, validate end-to-end delivery on a real iOS device:

- **Foreground**: send a chat message from another account → SnackBar appears within 2s.
- **Background tap**: receive a notification while app is backgrounded → tap navigates to correct deep-link screen.
- **Cold-start tap**: force-quit app, receive notification, tap → app opens and navigates.

Test each notification type: chat, appointment (requested/confirmed/cancelled), trainer_link (pending/active/terminated), and review.

---

## Notes

- The `.p8` key file is NOT stored in the repository. Keep it in the team's secure vault.
- APNs auth keys do not expire (unlike APNs certificates). Rotate only if compromised.
- Android FCM does not require APNs keys and works independently.
- Firebase Emulator does not support real FCM delivery. All CF trigger logic is tested via injected mock `messaging` instances.

REQ-PN-CX-011. ADR-PN-013. Fase 6 Etapa 2.
