# scripts/

Admin SDK utilities operated by the team against `treino-dev` and (rarely) `treino-prod`.

## Prerequisites

- Service-account JSON at `scripts/treino-dev-service-account.json` (gitignored).
- `GOOGLE_APPLICATION_CREDENTIALS` env var pointing at that file:
  ```sh
  export GOOGLE_APPLICATION_CREDENTIALS="scripts/treino-dev-service-account.json"
  # Windows PowerShell:
  $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\treino-dev-service-account.json"
  ```
- `firebase-admin` installed in `scripts/`:
  ```sh
  cd scripts && npm install
  ```

---

## promote_user_to_trainer.js

Flips `users/{uid}.role` to `'trainer'`. Trainer fields are NOT seeded — the
user must complete the in-app onboarding flow to populate them (`trainerBio`,
`trainerSpecialty`, `trainerMonthlyRate`, `trainerLocations` /
`trainerOffersOnline`).

### Usage

```sh
node scripts/promote_user_to_trainer.js <uid>
```

`<uid>` is the Firestore document ID under `users/{uid}` (same as the Firebase
Auth UID). Find it in the Firebase Console → Authentication → Users.

### Behavior

1. Validates that `users/{uid}` exists. Exits 1 with an error if not.
2. Logs the user's `email` and `displayName` for human verification.
3. In one batch, via Admin SDK (bypasses the client-side role-immutability rule):
   - sets `users/{uid}.role = 'trainer'`, and
   - backfills `displayName` + `displayNameLowercase` into
     `trainerPublicProfiles/{uid}` with `merge:true`. This is required because
     the trainer-edit onboarding form never writes the displayName, so without
     it the trainer appears with a BLANK name in discovery.
4. Exits 0 on success. Idempotent — re-running on an already-promoted user
   is a no-op that exits 0.

### Post-promotion flow

The user reopens the app → `authRedirect` detects
`role == trainer && !trainerProfileComplete` and routes them to
`/profile/edit-trainer?mode=onboarding`. Back navigation is blocked until the
form is submitted. On save the user lands on `/home` as a discoverable trainer.

---

## seed_emulator_full.js (Emulator seed)

EMULATOR-ONLY full-stack seed for manual testing. Refuses to run without
`FIREBASE_AUTH_EMULATOR_HOST` + `FIRESTORE_EMULATOR_HOST` set.

```sh
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
FIRESTORE_EMULATOR_HOST=localhost:8080 \
node scripts/seed_emulator_full.js          # seed (idempotent, re-run safe)
node scripts/seed_emulator_full.js --clear  # remove everything it created
```

Populates: Auth users (3 coaches + 5 athletes, throwaway passwords printed at
the end), `gyms`, `users` + `userPublicProfiles` + `trainerPublicProfiles`,
`trainer_links`, `friendships`, the **`exercises` stock catalogue** (reused
from `seed_workout_catalog.js` — same data prod uses), `routines`
(trainer-assigned plans + a public template), historical sessions under
`users/{uid}/sessions` **with realistic `setLogs` subcollections**
(deterministic progressive weights ramping onto each slot's `targetWeightKg`;
`totalVolumeKg` = Σ reps×kg of the generated sets; partial sessions stop
mid-workout), `posts` (all privacy levels), `appointments`, and
`coach_availability_rules`.

Dates are relative to the run instant; pin `SEED_NOW=<ISO date>` for
reproducible data. Session `muscleGroup` values use the canonical English keys
(`chest`, `back`, …) exactly like app-written data — Insights' muscle pipeline
(radar, Músculos del día, Volumen por grupo) depends on them.

---

## Other scripts

| Script | Purpose |
|---|---|
| `seed_trainer_profiles.js` | Seeds fake trainer docs in `treino-dev` for Coach Discovery smoke tests. |
| `seed_gyms.js` | Seeds the `gyms` catalog collection (two-level brand→sucursal model). |
| `backfill_user_public_profiles.js` | One-time backfill of `userPublicProfiles` for pre-existing users. |
| `backfill_gym_ids.js` | gyms-foundation Phase 4 (1/2). Verifies/corrects legacy `gymId` values against real `gyms/` docs. **Run first.** |
| `backfill_gym_names.js` | gyms-foundation Phase 4 (2/2). Fills `userPublicProfiles.gymName` from the resolved `gyms/` doc. **Run after `backfill_gym_ids.js`.** |
| `accept_pending_link.js` | Accepts a pending trainer-athlete link for smoke testing. |
| `migrate_trainer_locations.js` | One-time migration from singular `trainerLatitude/Longitude/Geohash` fields to the `trainerLocations` array model. |
| `deploy_rules.js` | Deploys Firestore security rules to the active Firebase project. |

For scripts not listed here, read their inline header comment for usage.

---

## backfill_gym_ids.js / backfill_gym_names.js (gyms-foundation Phase 4)

Two idempotent, dev-first Admin SDK scripts that close out the gyms-foundation
migration (two-level brand→sucursal catalog, `gymName` denormalization).
**Order matters**: run `backfill_gym_ids.js` before `backfill_gym_names.js` —
the name backfill resolves display names against the ids the first script
corrects.

### Usage

Run every command below from the **repo root** (the paths are repo-root-relative):

```sh
(cd scripts && npm install)   # once — subshell keeps cwd at the repo root

# 1. Ids first — dry run, then real run against treino-dev:
node scripts/backfill_gym_ids.js --dry-run
node scripts/backfill_gym_ids.js

# 2. Names second — dry run, then real run against treino-dev:
node scripts/backfill_gym_names.js --dry-run
node scripts/backfill_gym_names.js
```

Both scripts:
- Print the target `project_id` (from `sa-key.json`) before doing anything,
  and **refuse to run** unless the project id looks like a dev project
  (contains "dev"). Pass `--allow-prod` to override, only after dev
  verification + maintainer sign-off.
- Support `--dry-run`, which reports every change that WOULD be made without
  writing anything.
- Print a final VERIFIED COUNT / summary of docs checked, corrected, and
  skipped.
- Are safe to re-run at any time (idempotent — already-correct docs are
  left untouched).

### What each script does

- **`backfill_gym_ids.js`** — the 3 legacy hardcoded ids
  (`smart-fit-palermo`, `sportclub-belgrano`, `megatlon-recoleta`) now exist
  as real `gyms/` docs (Phase 1 seed rewrite), so this is largely a
  verification pass. It reconciles **per uid**: `users/{uid}` is the canonical
  source for `gymId`, and the corrected value is written to BOTH `users/` and
  `userPublicProfiles/` in one atomic batch, so the two can never disagree
  after the migration. Any `gymId` that doesn't resolve to a real `gyms/` doc
  is mapped to `kNoGymId` (`'no-gym'`) rather than guessing a replacement.
- **`backfill_gym_names.js`** — for `userPublicProfiles` docs that have a
  `gymId` but no `gymName`, resolves the composed display name
  (`"{brandName} - {branchName}"`, or just `brandName` for independent
  gyms) from the matching `gyms/` doc and writes it. `gymId == null` or
  `kNoGymId` → `gymName: null`. Unknown/unresolved ids are skipped and
  logged, not guessed.

Prod runs are a separate, maintainer-approved gate after dev counts are
verified — silent, no user notice (per the locked gyms-foundation decision).
