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
3. Calls `users/{uid}.update({ role: 'trainer' })` via Admin SDK (bypasses
   the client-side role-immutability rule).
4. Exits 0 on success. Idempotent — re-running on an already-promoted user
   is a no-op that exits 0.

### Post-promotion flow

The user reopens the app → `authRedirect` detects
`role == trainer && !trainerProfileComplete` and routes them to
`/profile/edit-trainer?mode=onboarding`. Back navigation is blocked until the
form is submitted. On save the user lands on `/home` as a discoverable trainer.

---

## Other scripts

| Script | Purpose |
|---|---|
| `seed_trainer_profiles.js` | Seeds fake trainer docs in `treino-dev` for Coach Discovery smoke tests. |
| `seed_gyms.js` | Seeds the `gyms` catalog collection. |
| `backfill_user_public_profiles.js` | One-time backfill of `userPublicProfiles` for pre-existing users. |
| `accept_pending_link.js` | Accepts a pending trainer-athlete link for smoke testing. |
| `migrate_trainer_locations.js` | One-time migration from singular `trainerLatitude/Longitude/Geohash` fields to the `trainerLocations` array model. |
| `deploy_rules.js` | Deploys Firestore security rules to the active Firebase project. |

For scripts not listed here, read their inline header comment for usage.
