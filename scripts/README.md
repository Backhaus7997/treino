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

## Credenciales — la frontera (#834)

> **La clave del Admin SDK no vive adentro del repo.** Ni en el repo raíz, ni en
> un worktree, ni en ningún árbol de git.

Los headers viejos que todavía nombran `treino-dev-service-account.json` (el
nombre pre-`sa-key`) hablan de la MISMA clave; sólo cambia el nombre del
archivo, y ahora tampoco puede vivir adentro del repo. (#826)

La clave que usaban estos scripts es la de
`firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com`: permisos amplios
sobre el proyecto donde viven los usuarios REALES (`treino-dev` **es**
producción, #826). Estaba en `scripts/sa-key.json` con permisos `644` —
legible por cualquier proceso del usuario y alcanzable con
`../../../scripts/sa-key.json` desde cualquiera de los ~27 worktrees de agente
que corren en paralelo.

**Los 44 scripts de `scripts/` pasan por dos archivos, y sólo por esos dos.**
Antes eran 21 de 43 los que ramificaban en `FIRESTORE_EMULATOR_HOST` antes de
cargar la clave; ahora ramifican **todos**, en un solo lugar (#834).


| | |
|---|---|
| `lib/credenciales.js` | **decide**: de dónde puede salir una credencial y si esa credencial es producción. Sin dependencias, testeado entero con stubs. |
| `lib/admin.js` | **aplica**: es el único que llama a `initializeApp`. Los scripts hacen `inicializarAdmin()` y nada más. |

Las reglas:

- La ruta sale de `$TREINO_SA_KEY` o de `$GOOGLE_APPLICATION_CREDENTIALS`.
  **No hay default.** Sin ninguna de las dos se falla ruidosamente, con la
  migración completa en el mensaje.
- `GOOGLE_APPLICATION_CREDENTIALS` está aceptada porque el ADC de Google **la
  lee por su cuenta**, adentro de la librería. Ignorarla habría dejado la
  frontera decorativa: `GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json`
  seguiría cargando la clave desde adentro del repo. Se valida con las **mismas
  reglas** y antes de inicializar nada. Si las dos están y apuntan a archivos
  distintos, se frena: son dos identidades en el mismo proceso.
- Cualquier ruta adentro de un árbol de git se **rechaza**, exista o no el
  archivo. (`.git` se detecta como entrada, no como directorio: en un worktree
  es un archivo.)
- La identidad que se verifica es la **efectiva** — el `client_email` de la
  credencial que se cargó —, no el project id declarado. Ver más abajo.
- El camino del emulador no toca nada de esto: **sin credencial, anda**. La
  única excepción: una variable apuntando adentro de un árbol de git se rechaza
  igual. `FIRESTORE_EMULATOR_HOST` desvía **Firestore y nada más** — Storage y
  Auth de Admin siguen yendo a la nube, así que eso sería producción disfrazada
  de local. Una variable vieja o rota, en cambio, no frena nada.

Lo que impide que el próximo script nazca salteándose todo esto es
`test/frontera.test.js`: escanea `scripts/` y falla si aparece un
`initializeApp`, un `credential.cert`, un `sa-key.json` o una lectura de
`GOOGLE_APPLICATION_CREDENTIALS` fuera de `lib/`.

Tests: `cd scripts && npm test`.

### Migración (una sola vez, si todavía tenés el archivo en el repo)

```sh
mkdir -p ~/.config/treino
mv scripts/sa-key.json ~/.config/treino/sa-key.json
chmod 600 ~/.config/treino/sa-key.json

# En tu ~/.zshrc (o ~/.bashrc), para que valga en toda sesión:
export TREINO_SA_KEY="$HOME/.config/treino/sa-key.json"
```

Verificá que quedó bien:

```sh
[ -e scripts/sa-key.json ] && echo "TODAVÍA ESTÁ EN EL REPO" || echo "fuera del repo, ok"
stat -f '%Sp' "$TREINO_SA_KEY"   # tiene que decir -rw-------
```

**Qué se rompe si NO hacés esto, y por qué está bien:** todo. Los 43 scripts
que tocan credenciales fallan cerrado hasta que exportes la variable — no hay
default y no hay fallback a `scripts/sa-key.json`. Es el punto: mientras
existiera un camino que funcionara sin migrar, nadie migraba, y la clave seguía
en el árbol al alcance de cualquiera de los ~27 worktrees.

El corte es de un comando: el mensaje de error trae el bloque de arriba entero.

Si preferís seguir usando `GOOGLE_APPLICATION_CREDENTIALS` porque ya la tenés
en el ambiente, sirve igual — con las mismas reglas, y apuntando afuera del
repo:

```sh
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/.config/treino/sa-key.json"
```

No las pongas a las dos apuntando a archivos distintos: eso se rechaza.

### Sin credencial: el emulador (el camino por defecto)

Todo lo local se corre contra el emulador y no necesita ninguna clave:

```sh
./scripts/emulator.sh
FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/<script>.js
```

### Por qué se mira la identidad y no el project id

El guard viejo miraba el proyecto. El revisor de #843 encontró por dónde se
escapa: `firebase use` escribe `activeProjects` en
`~/.config/configstore/firebase-tools.json`, ese valor le gana al default de
`.firebaserc`, y **no deja ningún rastro adentro del repo**. Mirando el
proyecto declarado no hay forma de darse cuenta.

La identidad no se escapa. Una credencial de
`…@treino-dev.iam.gserviceaccount.com` sólo puede escribir en `treino-dev`,
diga lo que diga el project id que la acompañe. Si la service account es de un
proyecto de producción, **esto es producción**, venga de donde venga la
configuración.

### Otros requisitos

```sh
cd scripts && npm install   # firebase-admin
```

---

## Lo que sólo puede hacer un humano (#834)

Nada de esto lo corre un agente: son operaciones de IAM sobre el proyecto de
producción. Los comandos están completos para copiar y pegar; **leelos antes de
ejecutarlos** y hacelos en este orden.

**1. Auditar qué puede realmente la SA de hoy.** Es la SA por defecto del Admin
SDK y arranca con permisos amplios; hay que ver el alcance real antes de
reemplazarla.

```sh
gcloud projects get-iam-policy treino-dev \
  --flatten="bindings[].members" \
  --filter="bindings.members:firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com" \
  --format="table(bindings.role)"

# Cuántas claves tiene vivas y desde cuándo (las de tipo USER_MANAGED son las
# descargables — cada una es una copia de la credencial dando vueltas):
gcloud iam service-accounts keys list \
  --iam-account=firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com \
  --project=treino-dev
```

**2. Crear una SA de menor privilegio** para el trabajo de scripts, en vez de
seguir usando la de permisos amplios.

```sh
gcloud iam service-accounts create treino-scripts \
  --display-name="TREINO — scripts de mantenimiento" \
  --project=treino-dev

# Sólo lo que los scripts necesitan de verdad. `datastore.user` da lectura y
# escritura de Firestore y NADA más: ni rules, ni deploys, ni Auth, ni Storage.
gcloud projects add-iam-policy-binding treino-dev \
  --member="serviceAccount:treino-scripts@treino-dev.iam.gserviceaccount.com" \
  --role="roles/datastore.user"

gcloud iam service-accounts keys create ~/.config/treino/sa-key.json \
  --iam-account=treino-scripts@treino-dev.iam.gserviceaccount.com \
  --project=treino-dev
chmod 600 ~/.config/treino/sa-key.json
```

Si algún script necesita más que Firestore (Auth, Storage), sumá el rol
puntual — `roles/firebaseauth.admin`, `roles/storage.objectAdmin` — y no
`roles/editor`. El punto del ejercicio es que la clave que anda suelta por la
máquina no pueda borrar el proyecto.

**3. Rotar la clave vieja.** La de `firebase-adminsdk-fbsvc@` estuvo en `644`
adentro del repo: hay que tratarla como comprometida. Primero deshabilitala
(reversible) y dejá correr unos días por si algo la usaba sin que sepamos;
después borrala.

```sh
gcloud iam service-accounts keys list \
  --iam-account=firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com \
  --managed-by=user --project=treino-dev          # anotá el KEY_ID

gcloud iam service-accounts keys disable <KEY_ID> \
  --iam-account=firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com \
  --project=treino-dev

# Días después, si nada se rompió:
gcloud iam service-accounts keys delete <KEY_ID> \
  --iam-account=firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com \
  --project=treino-dev
```

**4. Confirmar que no quedaron copias.** El repo estaba limpio (gitignored,
`.gitignore:54`) y había una sola copia, pero después de rotar conviene
verificar la máquina entera:

```sh
fd -HI 'sa-key.json|.*-firebase-adminsdk-.*\.json' ~ --exec stat -f '%Sp %N'
```

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

Two idempotent, **emulator-first** Admin SDK scripts that close out the gyms-foundation
migration (two-level brand→sucursal catalog, `gymName` denormalization).
There is no "dev-first" here: `treino-dev` is production, `treino-prod` does not
exist, and the only disposable environment is the local emulator
(`./scripts/emulator.sh`, then prefix the command with
`FIRESTORE_EMULATOR_HOST=localhost:8080`). (#845)
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

Sin ninguna de las dos variables el destino ya **no** es producción: desde el
#840 el `default` del `.firebaserc` es `demo-treino`, el último eslabón de la
cadena de arriba cae ahí, y el bucket que se deriva es
`demo-treino.firebasestorage.app` — un bucket que no existe. La corrida falla
sin haber tocado nada. Hasta el #840 ese mismo comando subía a producción, con
cartel, pero subía.

Para escribir en producción hay que **nombrarla**, por cualquiera de los cuatro
caminos de la cadena (`--project=treino-dev`, `GOOGLE_CLOUD_PROJECT`,
`GCLOUD_PROJECT` o la credencial de prod en `GOOGLE_APPLICATION_CREDENTIALS`).
Ahí sí sale el cartel del #826 antes de la primera escritura, igual que antes:
lo que el #840 le sacó de encima al guard es el default que lo hacía disparar
sin que nadie hubiera pedido producción.

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

**Quedan tres archivos con el bucket de producción hardcodeado, y ninguno abre
Storage.** El #840 cambia el proyecto por default, no el literal: donde el
bucket está escrito a mano, sigue escrito a mano. Se midió qué pasa ahí y la
respuesta es que hoy es inerte —

- `build_catalog_proposal.js` y `match_drive_videos_to_catalog.js` son
  read-only: leen `exercises` de Firestore y escriben un CSV/JSON en `docs/`. El
  `storageBucket:` de su `initializeApp` es opción muerta, no hay un solo
  `admin.storage()` en esos archivos.
- `_video_map.js` no es un script sino un mapa `exerciseId → videoUrl`. El
  bucket vive adentro de una URL de **descarga** que `seed_workout_catalog.js` y
  `backfill_exercise_videos.js` estampan en Firestore. Contra el emulador esas
  URLs ya apuntaban al bucket real desde antes del #840; leer de producción no
  es escribir en producción.

Inerte hoy no es inerte siempre, y las dos formas de romperlo son silenciosas:
agregarle un `admin.storage().bucket()` a alguno de esos archivos escribiría en
producción sin pasar por `exigirDestinoCoherente` y sin cartel, y un cuarto
archivo que copie el literal sería un cuarto destino que no responde ni a
`--bucket=` ni al default del `.firebaserc`. Las dos las agarra
`test/storage_scripts_destination.test.js`, que barre `scripts/*.js` y
`scripts/lib/*.js` y falla si la lista de archivos con el literal cambia o si
alguno de ellos empieza a tocar Storage.

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
