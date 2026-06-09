# Firebase Hosting Rewrites for Browser-Callable Cloud Functions

This document captures the **browser-CORS gap** discovered during the smoke of the
`coach-excel-polish` SDD (Fase 6 Etapa 5) and the recommended long-term solution
for invoking Firebase callable v2 Cloud Functions from a browser-based client
(Coach Hub web).

It is **out-of-band setup documentation**, not a code prerequisite for any merged
PR. The CFs themselves work; this file describes how to make them callable from
browsers without relaxing the org policy.

---

## Why this matters

Firebase callable v2 Cloud Functions run on Cloud Run under the hood. When a
**browser** invokes them via `httpsCallable('addAlias')`:

1. The Flutter `cloud_functions` plugin issues an HTTPS POST to the public
   Firebase Functions URL (`https://southamerica-east1-treino-dev.cloudfunctions.net/addAlias`).
2. The browser issues a **CORS preflight OPTIONS** request first.
3. Cloud Run rejects the OPTIONS preflight with **403** because the underlying
   Cloud Run service does NOT have `allUsers` as `roles/run.invoker`.
4. The 403 has **no `Access-Control-Allow-Origin` header**, so the browser
   blocks the request entirely at the network layer.
5. The Flutter callable swallows the underlying error as
   `[firebase_functions/internal]` and the call silently fails.

This affects **only browser clients**. Mobile clients (iOS/Android via the
Firebase Functions native SDK) bypass CORS preflight and work without `allUsers`
on the invoker — that is why `deleteAccount` works on iOS without any extra
configuration.

### The org policy that blocks `allUsers`

`treino-dev` has the GCP org policy
`constraints/iam.allowedPolicyMemberDomains` enforced (Domain Restricted
Sharing). Adding `allUsers` as `roles/run.invoker` on any new Cloud Run service
fails with:

```
IAM policy update failed
The 'Domain Restricted Sharing' organization policy is enforced.
Only principals in allowed domains can be added as principals in the policy.
```

This is **correct security posture** for the organization. The fix is NOT to
relax the org policy — the fix is to make browser clients call CFs via a path
that does not require `allUsers`.

---

## The fix: Firebase Hosting rewrites

When the Coach Hub web is served from **Firebase Hosting**, you can configure
rewrites in `firebase.json` that proxy requests on the same origin to a
callable function. From the browser's perspective the function lives at
`/api/addAlias` on the same origin as the web app — **no CORS preflight
required**.

### `firebase.json` snippet

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
    "rewrites": [
      {
        "source": "/api/addAlias",
        "function": "addAlias",
        "region": "southamerica-east1"
      }
    ]
  }
}
```

Add one rewrite block per browser-callable CF. Future Coach Hub CFs that are
invoked from the browser must each get their own rewrite.

### Client-side change

Instead of:

```dart
final fn = ref.read(cloudFunctionsProvider).httpsCallable('addAlias');
await fn.call({'exerciseId': id, 'alias': raw});
```

Use:

```dart
final fn = ref.read(cloudFunctionsProvider)
    .httpsCallableFromUrl(Uri.parse('/api/addAlias'));
await fn.call({'exerciseId': id, 'alias': raw});
```

`httpsCallableFromUrl` calls a same-origin URL. The browser does NOT issue a
CORS preflight because the request is same-origin from its perspective.

### When this matters

You need the rewrite for any callable CF that:

- Is invoked from a Flutter web client (Coach Hub web)
- Today: `addAlias` is the first such CF in this codebase
- Tomorrow: any new CF that adds a side effect on user interaction inside Coach
  Hub web (e.g., a future "submit feedback" CF, an "approve plan revision" CF, etc.)

CFs that are invoked **only from mobile** OR **server-side** (Firestore
triggers, Eventarc events, other CFs, schedulers) do **not** need this — they
already work without `allUsers` on the invoker.

---

## Local development

The rewrite path also works in local dev with the Firebase Hosting emulator:

```bash
firebase emulators:start --only hosting,functions
```

Then point the Flutter web app at the Hosting emulator URL (typically
`http://localhost:5000`) and the `/api/addAlias` rewrite resolves to the local
Functions emulator. No CORS issues.

---

## Verification of the smoke gap

The `addAlias` CF correctness is validated by:

- **Jest emulator tests** (14/14 SCENARIO-735..743) — full handler logic
  including auth, role gate, normalize, dedup, idempotency, accent parity with
  Dart `normalize()`.
- **Widget tests** (4/4 SCENARIO-744..747) — client wire, `cloudFunctionsProvider`
  injection, fire-and-forget order (R2), silent failure swallow.
- **Cloud Run deploy** — service deployed in `southamerica-east1`, Compute SA
  has `roles/run.invoker`, callable from server-to-server contexts.

What we could **not** validate end-to-end at smoke time is the browser →
cloudfunctions.net → Cloud Run path, because the org policy blocks the
`allUsers` invoker that the browser CORS preflight needs. Once Hosting rewrites
are in place (or when Coach Hub web is served from Firebase Hosting in
production), the end-to-end smoke becomes possible.

---

## Notes

- This is a **standard Firebase pattern** for browser-callable functions.
  Documented at:
  <https://firebase.google.com/docs/hosting/functions>
- Do **not** request the org admin to relax `Domain Restricted Sharing` — the
  policy is the correct posture. Use the rewrite pattern instead.
- The rewrite does NOT require any IAM changes. It works because the Hosting
  CDN is the caller of the Cloud Run service, and the CDN is an internal GCP
  principal that already has invoke permission.

REQ-CXP-CF-007..017. ADR-CXP-005. Fase 6 Etapa 5.
