# FCM Setup — APNs Auth Key + Cloud Function IAM

This document describes the manual steps required to make FCM push notifications deliver end-to-end in TREINO. There are TWO independent setup items, both **out-of-band prerequisites for smoke testing** — neither is required for code review or merge.

1. **APNs Auth Key** (iOS only) — blocks real FCM delivery to iOS devices.
2. **Cloud Function IAM** (both platforms) — blocks the CF triggers from dispatching FCM messages.

Both were discovered during the Fase 6 Etapa 2 smoke and are required for any environment that runs the notification CFs (`treino-dev`, future `treino-prod`).

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

## Step 4: Add iOS Push Notifications capability in Xcode

The `aps-environment` entitlement is required so iOS will provision an APNs token for the app. Without it, `FirebaseMessaging.getToken()` throws `apns-token-not-set` indefinitely.

1. Open `ios/Runner.xcworkspace` in Xcode (the workspace, not the `.xcodeproj`).
2. Click the **Runner** project root → select the **Runner** target.
3. Tab **Signing & Capabilities**.
4. Click **+ Capability** (top-left of the panel) → search and add **Push Notifications**.
5. Verify `ios/Runner/Runner.entitlements` now includes:
   ```xml
   <key>aps-environment</key>
   <string>development</string>
   ```
   (For TestFlight/App Store release builds Xcode automatically swaps to `production` based on the signing profile — do not edit manually.)
6. Verify the App ID in Apple Developer Console → Identifiers → `com.backhaus.treino` has the **Push Notifications** capability checked. Adding the capability in Xcode with Automatic Signing usually updates this; if not, check it manually and Save.
7. Close Xcode. Build via `flutter run` from terminal (do NOT build from Xcode — the Prepare Flutter Framework script fails with status 127 because `flutter` is not on Xcode's PATH).

---

## Step 5: Grant the Cloud Function service account `roles/cloudmessaging.editor`

Cloud Functions deployed via `firebase deploy --only functions` run as the project's **Compute Engine default service account** (`{PROJECT_NUMBER}-compute@developer.gserviceaccount.com`). By default this SA does NOT have permission to send FCM messages. Without this role every `sendFcm` call fails with:

```
messaging/mismatched-credential — Permission 'cloudmessaging.messages.create'
denied on resource '//cloudresourcemanager.googleapis.com/projects/<project>'
```

The CF itself returns 200 OK and shows no internal error in its logs unless the explicit observability lines added by `notifications/send-fcm.ts` are present.

### Option A — Console

1. Open IAM → https://console.cloud.google.com/iam-admin/iam?project=treino-dev
2. Find the row `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com` (for `treino-dev` the project number is `1079774251763`).
3. Click the pencil (Edit principal) → **+ ADD ANOTHER ROLE**.
4. Search and add **Firebase Cloud Messaging API Admin** (`roles/firebasenotifications.admin`) OR **Cloud Messaging Editor** (`roles/cloudmessaging.editor`). Either works; the Cloud Messaging Editor role is the minimum required.
5. Save. Allow ~30 seconds for IAM propagation.

### Option B — gcloud CLI

```bash
gcloud projects add-iam-policy-binding treino-dev \
  --member="serviceAccount:1079774251763-compute@developer.gserviceaccount.com" \
  --role="roles/cloudmessaging.editor"
```

### Verification

Trigger any of the four notification CFs (e.g. send a chat message between two accounts) and check the Logs Explorer for the function. You should see:

```
sendFcm: dispatching to 1 tokens for 1 uids
sendFcm: result success=1 failure=0
```

If you still see `non-stale error … code=messaging/mismatched-credential`, the IAM binding has not propagated yet or it was added to a different SA than the one running the CF.

### Long-term follow-up

The cleaner long-term fix is to run the four notification CFs under a dedicated `firebase-adminsdk-fbsvc@<project>.iam.gserviceaccount.com` service account that has all Firebase roles by default. That refactor is tracked as a follow-up issue against the `push-notifications-fcm` SDD; until it lands, the Compute SA + role grant above is the supported configuration.

---

## Step 6: Smoke Test (after PR#2b merges)

Once PR#2b is merged, APNs is configured, and the IAM role is granted, validate end-to-end delivery on a real iOS device:

- **Foreground**: send a chat message from another account → SnackBar appears within 2s.
- **Background tap**: receive a notification while app is backgrounded → tap navigates to correct deep-link screen.
- **Cold-start tap**: force-quit app, receive notification, tap → app opens and navigates.

Test each notification type: chat, appointment (requested/confirmed/cancelled), trainer_link (pending/active/terminated), and review.

---

## Notes

- The `.p8` key file is NOT stored in the repository. Keep it in the team's secure vault.
- APNs auth keys do not expire (unlike APNs certificates). Rotate only if compromised.
- Android FCM does not require APNs keys and works independently — `aps-environment` is iOS-only.
- The Compute SA IAM grant in Step 5 applies to BOTH iOS and Android because it affects the CF dispatch path, not the device delivery.
- Firebase Emulator does not support real FCM delivery. All CF trigger logic is tested via injected mock `messaging` instances.
- The iOS Simulator cannot obtain APNs tokens (Apple limitation). Smoke tests MUST run on a real device.

REQ-PN-CX-011. ADR-PN-013. Fase 6 Etapa 2.
