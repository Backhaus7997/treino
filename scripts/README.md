# scripts/

Admin SDK utilities operated by the team against `treino-dev`.

> ## 🚨 `treino-dev` IS PRODUCTION
>
> It is TREINO's **only** Firebase project. There is no `treino-prod` — a
> previous version of this line claimed there was, and that was wrong
> (`firebase projects:list` returns exactly one TREINO project; `.firebaserc`,
> `lib/firebase_options.dart`, `android/app/google-services.json` and
> `ios/Runner/GoogleService-Info.plist` all point at `treino-dev`).
>
> **39 of the 43 scripts** here write through the Admin SDK, which **bypasses
> the Firestore security rules**. A mis-pointed `backfill_*` / `seed_*` /
> `cleanup_*` / `migrate_*` run destroys real user data.
>
> Firestore has a daily backup schedule with 28-day retention
> (`firebase firestore:backups:schedules:list --project prod`), so a Firestore
> mistake is recoverable — at the cost of a restore and whatever was written in
> between. **The schedule does not cover Cloud Storage or Auth users**: anything
> a script does there is irreversible.
>
> The four that do **not** write are `audit_trainer_profiles.mjs`,
> `audit_ranking_optin.js`, `build_catalog_proposal.js` and
> `match_drive_videos_to_catalog.js` (the last two write only local files under
> `docs/`). Assume "writes" for anything not on that list — but do not assume
> a script is dangerous just because it is here, either: a doc that cries wolf
> stops being read, which is the failure mode this whole banner exists to fix.
>
> **Default to the emulator** (see below). A run against `treino-dev` needs
> explicit maintainer sign-off, and `--dry-run` first where the script supports
> it. → [AGENTS.md → Entornos](../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando) · issue #826.

## Prerequisites

- Service-account JSON at **`scripts/sa-key.json`** (gitignored). That is the
  name the code actually uses: 19 scripts `require('./sa-key.json')` directly
  and another ~15 document it as the `GOOGLE_APPLICATION_CREDENTIALS` target.
  Save the key from the Firebase Console under exactly that name or those
  scripts fail with a "sa-key.json not found" error.
  > A handful of older script headers still say
  > `treino-dev-service-account.json` (the pre-`sa-key` name — also gitignored,
  > via `.gitignore:52`). It is the same key; only the filename differs, and
  > only the scripts that read `GOOGLE_APPLICATION_CREDENTIALS` accept it.
  > Nothing `require`s it. (#826)
- `GOOGLE_APPLICATION_CREDENTIALS` env var pointing at that file, for the
  scripts that read it instead of `require`-ing the key:
  ```sh
  export GOOGLE_APPLICATION_CREDENTIALS="scripts/sa-key.json"
  # Windows PowerShell:
  $env:GOOGLE_APPLICATION_CREDENTIALS = "scripts\sa-key.json"
  ```
- `firebase-admin` installed in `scripts/`:
  ```sh
  cd scripts && npm install
  ```

### Running against the emulator (no service-account key)

**21 of the 43 scripts** here branch on `FIRESTORE_EMULATOR_HOST` **before**
loading `sa-key.json`. For those, setting the variable initializes against the
local emulator (`projectId: 'treino-dev'`, which here is just the emulator's
namespace) with no credentials at all:

```sh
FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/<script>.js
```

Without that env var the key is required, and a missing `sa-key.json` fails
with an actionable message instead of a raw `MODULE_NOT_FOUND`.

> ⚠️ **The other 22 have no such branch** — they call `admin.initializeApp()`
> straight away and go to production with whatever the service account points
> at. (#826)
>
> **Do not settle this with grep.** A previous version of this file said "23
> check" and told you to `grep -n FIRESTORE_EMULATOR_HOST scripts/<script>.js`
> before running one. Both halves were wrong in the reassuring direction:
> `seed_posts.js` and `seed_sessions.js` name the variable **only in their
> usage docstring** and then call `admin.initializeApp()` bare. A grep hit
> there looks exactly like a grep hit on a script that really branches. Read
> the `initializeApp` call, not the file.
>
> (Setting the variable still routes *Firestore* to the emulator in those two —
> the Admin SDK reads it on its own. What is missing is the credential branch:
> they demand a real `sa-key.json` anyway, and anything they touch outside
> Firestore is not redirected at all.)

### 🚨 The npm scripts — the shortest path to production in this repo

`scripts/package.json` exposes six one-liners that write to production, and
**none of them names the project on screen**: the Admin SDK resolves it from
`GOOGLE_APPLICATION_CREDENTIALS`.

| `npm run …` | Runs | Blast radius |
|---|---|---|
| `seed:exercises` / `seed:routines` / `seed:all` | `seed_workout_catalog.js` | `set()` over the whole `exercises` + `routines` stock catalogue |
| `seed:trainers` | `seed_trainer_profiles.js` | upserts 5 `users/{uid}` + `trainerPublicProfiles/{uid}` |
| **`seed:trainers:clear`** | `seed_trainer_profiles.js --clear` | **`batch.delete()`** on those same 10 docs |
| `promote:trainer` | `promote_user_to_trainer.js` | flips `users/{uid}.role`, bypassing the role-immutability rule |

That `seed:emulator` and `seed:emulator:clear` carry
`FIREBASE_AUTH_EMULATOR_HOST` + `FIRESTORE_EMULATOR_HOST` **inline** while the
six above carry nothing reads like the bare ones are the safe default. It is
the other way round: **the safe one is the exception.** To point any of the six
at the emulator you have to add the variables by hand.

All six now print the production banner before their first write. The banner is
visibility, not a gate — exit codes are unchanged, and it stays quiet against
the emulator and against any non-production project id.

> `deploy_rules.js` is a **44th** write path that this "43" does not even
> count: it never loads `firebase-admin`. See its own entry below.

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
| `deploy_rules.js` | 🚨 Deploys Firestore security rules. **Ignores `.firebaserc`, `firebase use` and `--project`** — see below. |

For scripts not listed here, read their inline header comment for usage.

---

## 🚨 deploy_rules.js — el camino que ningún default frena

```sh
cd scripts && node deploy_rules.js
```

Publica `firestore.rules` **en producción**, y no por el CLI de Firebase: arma
el ruleset y mueve el release contra la REST API de Firebase Rules
(`firebaserules.googleapis.com`) autenticándose con `sa-key.json`.

De ahí que sea su propia sección y no una fila más de la tabla:

- **No lee `.firebaserc`.** El proyecto sale del `project_id` del service
  account (`deploy_rules.js:~30`). Cambiar el default del `.firebaserc`, correr
  `firebase use`, o pasar `--project`: ninguna de las tres lo desvía.
- **`FIRESTORE_EMULATOR_HOST` tampoco lo desvía.** No hay modo emulador acá.
- **Pega al instante en las apps ya instaladas.** Unas rules más duras cortan
  lecturas y escrituras de usuarios reales en el próximo request, sin release
  de por medio y sin vuelta atrás salvo re-deployando las anteriores.

Imprime el banner de producción antes del primer request (`lib/firebase_projects.js`),
y a diferencia del resto lo imprime **siempre** que el destino sea producción:
apagarlo con la variable del emulador sería mentir. (#826)

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

# 1. Ids first — dry run, then real run. ⚠️ the second line WRITES TO PRODUCTION:
node scripts/backfill_gym_ids.js --dry-run
node scripts/backfill_gym_ids.js

# 2. Names second — same deal, the second line WRITES TO PRODUCTION:
node scripts/backfill_gym_names.js --dry-run
node scripts/backfill_gym_names.js
```

⚠️ Prefer the emulator for both:
`FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/backfill_gym_ids.js`.

Both scripts:
- Print the target `project_id` (from `sa-key.json`, or `treino-dev` when
  `FIRESTORE_EMULATOR_HOST` is set) before doing anything, and **refuse to run**
  unless the project id contains "dev" — pass `--allow-prod` to override.
  ⚠️ **That name check does NOT protect you here**: `treino-dev` contains "dev",
  so the guard passes and the script writes to production without `--allow-prod`.
  It only ever guarded against a *different*, unexpected project. Since #826 the
  scripts print an explicit PRODUCTION banner when the target is a known
  production project id (`scripts/lib/firebase_projects.js`) — read it, don't
  scroll past it.
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

A run without `FIRESTORE_EMULATOR_HOST` **is** the prod run — there is no
separate dev project to verify against first (#826). Verify on the emulator,
then `--dry-run` against `treino-dev`, then the real run with maintainer
sign-off — silent, no user notice (per the locked gyms-foundation decision).

## Scripts que escriben en Firebase Storage (#838)

Cuatro scripts suben archivos al bucket y después escriben la URL resultante en
Firestore:

| Script | Qué sube | Qué escribe en Firestore |
| --- | --- | --- |
| `extract_exercise_thumbnails.js --upload` | `exercises/thumbs/{id}.jpg` | `exercises/{id}.thumbnailUrl` |
| `apply_catalog_video_fill.js --apply` | `exerciseVideos/{id}.mp4` | `exercises/{id}.videoUrl` (+ `equipment` con `--fill-empty`) |
| `upload_enriched_videos.js` | `exerciseVideos/{id}.mp4` | nada (patchea el JSON del catálogo) |
| `upload_drive_exercise_videos.js` | `exerciseVideos/{id}.mp4` | `exercises/{id}.videoUrl` |

Los cuatro pasan por `lib/storage_target.js` antes de la primera escritura.

**El bucket ya no está hardcodeado.** Se resuelve en este orden:
`--bucket=<bucket>` → `FIREBASE_STORAGE_BUCKET` → derivado del proyecto activo
(`--project=` → `GOOGLE_CLOUD_PROJECT` → `project_id` del
`GOOGLE_APPLICATION_CREDENTIALS` → `.firebaserc`).

**Firestore y Storage tienen que apuntar al mismo lado, o el script aborta.**
Antes, `extract_exercise_thumbnails.js` miraba sólo `FIRESTORE_EMULATOR_HOST`,
imprimía `destino: EMULADOR` y subía los `.jpg` a producción igual, porque
`initializeApp` traía el bucket real fijo (#838). Hoy esa combinación no corre.

Para correr entero contra el emulador hay que levantarlo **con Storage** —
`scripts/emulator.sh` arranca `--only firestore,auth,functions`, así que el
emulador de Storage (puerto 9199, declarado en `firebase.json`) no está:

```bash
firebase emulators:start --only firestore,auth,storage
export FIRESTORE_EMULATOR_HOST=localhost:8080
export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199
```

Sin ninguna de las dos variables, el destino es **producción** (`treino-dev`, ver
#826) y sale el cartel antes de escribir.

**Producción se mide por proyecto Y por bucket.** El guard del #826 mira sólo el
project id, que para un backfill de Firestore ES el destino; para estos cuatro
no lo es. Un `--project` de prueba con un `--bucket` copiado del README es una
corrida contra producción que ninguna lista de proyectos ve:

```bash
node upload_drive_exercise_videos.js \
  --project=treino-scratch --bucket=treino-dev.firebasestorage.app
```

Ahí `treino-scratch` no es producción pero el bucket sí, y los `.mp4` aterrizan
en el bucket real. `esBucketDeProduccion` reconoce las tres formas de escribir
el mismo bucket (`treino-dev.firebasestorage.app`, el legacy
`treino-dev.appspot.com`, y el id pelado) y saca su propio cartel, que nombra al
bucket y no al proyecto. El backup diario de Firestore **no cubre Cloud
Storage**: lo que estos scripts escriben ahí no se recupera.

Los tests del cableado —que cada script llame al guard, y que lo llame antes de
tocar Storage— están en `test/storage_scripts_destination.test.js`. Corren con
`firebase-admin` stubbeado, cero red y sin `node_modules`:
`npm --prefix scripts test`. Los corre el job **`Scripts Test (scripts/test)`**
de `.github/workflows/ci.yml`, así que borrar una línea de cableado pone el PR
en rojo — antes de ese job la suite entera dependía de que alguien se acordara.

El stub (`test/fixtures/stub_firebase_admin.js`) tapa los **dos** caminos de
carga, porque los scripts de `migrations/` son `.mjs` y su `import` no pasa por
`Module._load`: `Module._load` para CJS y `module.register()` —con los hooks de
`test/fixtures/esm_stub_hooks.mjs`— para ESM. `register()` y no
`registerHooks()` a propósito: la segunda existe recién en Node 22.15 y el job
corre **Node 20**, donde el subproceso pasaba a cargar el `firebase-admin` de
verdad. Ese modo es peor que un rojo, porque los tests que prueban la
**ausencia** de un marcador quedan verdes midiendo nada. Por eso la intercepción
ahora se **anuncia** (`STUB_ESM_INTERCEPTED`), los tests la exigen en cada
corrida y `test/esm_stub_interception.test.js` la custodia con control negativo.
Si tocás el stub, corré la suite en Node 20 —no sólo en el tuyo—:
`npx -y node@20 --test test/*.test.js` desde `scripts/`.
