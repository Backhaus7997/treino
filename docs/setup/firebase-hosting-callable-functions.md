# Making Callable v2 Cloud Functions Publicly Reachable

How `treino-dev` exposes Firebase **callable v2** Cloud Functions, why the
obvious answer (`allUsers` → `roles/run.invoker`) does **not** work here, and
what to check when a freshly deployed callable returns **403**.

> **2026-08-14 — this document was rewritten.** The previous version diagnosed
> this as a browser-only CORS problem and recommended Firebase Hosting rewrites.
> That diagnosis was wrong. See [What the previous version got wrong](#what-the-previous-version-got-wrong).

---

## The symptom

A callable is listed by `firebase functions:list`, deploy reported success, and
yet every invocation fails. The client sees `[firebase_functions/internal]`.

Probe it directly — no browser, no SDK:

```bash
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" -X POST \
  "https://southamerica-east1-treino-dev.cloudfunctions.net/<name>" \
  -H "Content-Type: application/json" -d '{"data":{}}'
```

| response | meaning |
| --- | --- |
| **403** `text/html` | Blocked at the front door. **The function never ran.** |
| **401** `application/json` `UNAUTHENTICATED` | Reached the handler, which rejected the missing Auth token. **This is the healthy state.** |

A 401 from an unauthenticated probe is the *correct* result. Do not read it as a
failure.

---

## Why 403 happens

A callable v2 function is a **Cloud Run service** underneath. Two independent
layers guard it:

```
Internet → [Cloud Run front door: IAM invoker check] → [handler: App Check + Firebase Auth]
```

The front door knows nothing about your users — it only understands Google Cloud
identities. A Firebase Auth ID token is not one, so it does not get you past it.
Authentication of *users* happens inside the handler.

There are two ways to open the front door:

1. Bind `allUsers` to `roles/run.invoker`, **or**
2. Disable the invoker IAM check on the service.

**This project must use option 2.**

### Option 1 is impossible in this project

`treino-dev` enforces the org policy `constraints/iam.allowedPolicyMemberDomains`
(Domain Restricted Sharing):

```console
$ gcloud resource-manager org-policies describe \
    constraints/iam.allowedPolicyMemberDomains --project=treino-dev --effective
constraint: constraints/iam.allowedPolicyMemberDomains
listPolicy:
  allowedValues:
  - C03bxdsb7
```

Only principals inside the organization's customer ID are allowed. Adding
`allUsers` fails with `The 'Domain Restricted Sharing' organization policy is
enforced`. This is correct security posture — **do not ask an admin to relax it.**

Consequently **no callable in `treino-dev` has an `allUsers` binding.** Every
service returns an empty IAM policy:

```console
$ gcloud run services get-iam-policy deleteaccount \
    --region=southamerica-east1 --project=treino-dev --format=json
{ "etag": "ACAB" }
```

If you are debugging by looking for a missing `allUsers` binding, you are
looking at the wrong thing.

### Option 2 is the mechanism actually in use

Cloud Run can skip the invoker IAM check entirely. That is what makes the
working callables reachable:

```console
$ gcloud run services describe deleteaccount \
    --region=southamerica-east1 --project=treino-dev --format=json \
    | rg invoker
      "run.googleapis.com/invoker-iam-disabled": "true",
```

A broken service simply lacks that annotation. That single annotation is the
entire difference between 401 and 403.

---

## The fix

```bash
gcloud run services update <service-name> \
  --project=treino-dev \
  --region=southamerica-east1 \
  --no-invoker-iam-check
```

Reversible with `--invoker-iam-check`. Then re-probe: 403 must become 401.

### Footgun: Cloud Run service names are lowercase

The function is `addAlias`; the Cloud Run service is **`addalias`**. List the
real names before querying:

```bash
gcloud run services list --project=treino-dev --region=southamerica-east1
```

`gcloud run services get-iam-policy addAlias` does **not** 404 — it returns an
empty policy `{"etag":"ACAB"}`, which looks exactly like a real service with no
bindings. That silent success will send you down the wrong path.

### Where `gcloud` lives on this machine

Installed via Homebrew cask but **not on the default `PATH`**:

```
/opt/homebrew/share/google-cloud-sdk/bin/gcloud
```

Workspace enforces periodic re-authentication for mutating commands. When
`Reauthentication failed. cannot prompt during non-interactive execution`
appears, run `gcloud auth login` in an interactive terminal — reads may keep
working from a cached token for a while after writes start failing.

---

## Checklist for every new callable

Deploy does not reliably set the annotation. After deploying a **new** callable
that clients invoke directly:

1. Probe it with the `curl` above.
2. If 403 → apply `--no-invoker-iam-check` to the lowercase service name.
3. Re-probe and confirm 401 JSON.

Functions invoked only server-side (Firestore triggers, Eventarc, schedulers,
other functions) never need this — they are not called through the front door.

---

## Security posture

Disabling the invoker IAM check does **not** make the function unprotected. It
moves authentication from the front door into the handler, where it already
lives:

- `enforceAppCheck: true` on the `onCall` declaration
- Firebase Auth validation inside the handler

This is the same posture `deleteAccount` has had since it shipped.

---

## What the previous version got wrong

Recorded so the same detour is not repeated.

1. **"This affects only browser clients. Mobile clients bypass CORS preflight
   and work without `allUsers`."** False. The `curl` probe above sends no
   `Origin` header and triggers no preflight, and still receives 403. The
   invoker check runs before any function code, for every caller.
2. **The recommended fix — Firebase Hosting rewrites plus
   `httpsCallableFromUrl` — was never needed.** It addressed a CORS problem that
   was not the cause. It was never implemented, and `firebase.json` carries no
   such rewrite.
3. **The org policy was correctly identified but the conclusion did not
   follow.** `allUsers` is genuinely blocked; the document treated that as a
   dead end instead of finding the mechanism the project's own working functions
   already used.

Cost of the error: `addAlias` returned 403 for its entire deployed life. The
call site swallows failures by design (ADR-CXP-009), so nothing surfaced. Fixed
2026-08-14 — verified 403 → 401.

REQ-CXP-CF-007..017. ADR-CXP-005.
