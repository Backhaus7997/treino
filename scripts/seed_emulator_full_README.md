# scripts/seed_emulator_full.js

Full-stack emulator seed for manual testing of TREINO. Creates Auth users and
Firestore documents for 3 coaches (trainers) and 13 athletes, with trainer
links, multi-week routines, historical sessions, posts (all privacy levels),
friendships, appointments, and availability rules.

> **WARNING — EMULATOR-ONLY CREDENTIALS.** All passwords listed here are
> throwaway, for the local emulator only. They are NOT real Firebase accounts
> and they will NOT work against the `treino-dev` production project.

---

## Prerequisites

- Firebase CLI installed (`npm install -g firebase-tools` or via Homebrew).
- Node.js 18+.
- `cd scripts && npm install` (installs `firebase-admin`).

---

## 1. Start the emulator

In a dedicated terminal tab:

```sh
# From the repo root:
bash scripts/emulator.sh
```

Wait until you see:
```
✔  All emulators ready! It is now safe to connect your app.
```

The emulator UI is at <http://localhost:4444>.

---

## 2. Run the seed

```sh
cd scripts
npm run seed:emulator
```

Or directly:

```sh
FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
FIRESTORE_EMULATOR_HOST=localhost:8080 \
node scripts/seed_emulator_full.js
```

Re-running is idempotent (upserts via `set(..., {merge:true})`). Auth users are
created on the first run; subsequent runs update them.

---

## 3. Run the app against the emulator

In another terminal. Mobile app:

```sh
flutter run --dart-define=USE_EMULATOR=true
```

Coach Hub (the Flutter **web** target):

```sh
flutter run -t lib/main_coach_hub.dart -d web-server \
  --web-hostname 127.0.0.1 --web-port 5555 \
  --dart-define=USE_EMULATOR=true
```

Both targets point Firestore at `localhost:8080` and Auth at `localhost:9099`
(`lib/main.dart`, `lib/main_coach_hub.dart:53-60`), while the page above is
served from `127.0.0.1`. That mismatch is not a problem, and it is worth knowing
why, because it looks like one: the emulator binds IPv4 `127.0.0.1` only, and on
macOS `localhost` resolves to `::1` *and* `127.0.0.1`. Measured — the connection
lands on IPv4 either way:

```sh
curl -s -o /dev/null -w 'ip=%{remote_ip}\n' http://localhost:9099/   # -> ip=127.0.0.1
lsof -nP -iTCP:9099 -sTCP:LISTEN                                     # -> 127.0.0.1:9099 only
```

The two *are* different origins, though, so every Auth call gets a CORS
preflight and the emulator answers it (`OPTIONS ... 204 No Content`). That
preflight is normal, not a symptom.

---

## 4. Clear seed data

```sh
cd scripts
npm run seed:emulator:clear
```

---

## Seeded accounts (EMULATOR-ONLY)

### Coaches (role: `trainer`)

| Email | Password | Name | Specialty | Rate |
|---|---|---|---|---|
| `coach.lautaro@emulator.treino` | `Emulator1234!` | Lautaro Pérez | powerlifting | $45.000 |
| `coach.camila@emulator.treino` | `Emulator1234!` | Camila Ruiz | crossfit | $38.000 |
| `coach.diego@emulator.treino` | `Emulator1234!` | Diego Aguirre | kinesiologia | $52.000 |

### Athletes (role: `athlete`)

| Email | Password | Name | Gym | Experience |
|---|---|---|---|---|
| `martin@emulator.treino` | `Emulator1234!` | Martín López | Hierro Palermo | intermediate |
| `sofia@emulator.treino` | `Emulator1234!` | Sofía Ramírez | Hierro Palermo | beginner |
| `mateo@emulator.treino` | `Emulator1234!` | Mateo Quiroga | Cadencia Caballito | advanced |
| `valentina@emulator.treino` | `Emulator1234!` | Valentina Peralta | Cadencia Caballito | intermediate |
| `nicolas@emulator.treino` | `Emulator1234!` | Nicolás Fernández | — | beginner |
| `julieta@emulator.treino` | `Emulator1234!` | Julieta Acosta | Hierro Palermo | beginner |
| `tomas@emulator.treino` | `Emulator1234!` | Tomás Benítez | Hierro Palermo | intermediate |
| `agustina@emulator.treino` | `Emulator1234!` | Agustina Sosa | Hierro Palermo | advanced |
| `franco@emulator.treino` | `Emulator1234!` | Franco Molina | Hierro Palermo | beginner |
| `malena@emulator.treino` | `Emulator1234!` | Malena Castro | Hierro Palermo | intermediate |
| `ignacio@emulator.treino` | `Emulator1234!` | Ignacio Torres | Hierro Palermo | advanced |
| `rocio@emulator.treino` | `Emulator1234!` | Rocío Medina | Hierro Palermo | beginner |
| `facundo@emulator.treino` | `Emulator1234!` | Facundo Ríos | Hierro Palermo | intermediate |

---

## Is the app REALLY on the emulator?

Measured 2026-09-07 on `lib/main_coach_hub.dart` with
`--dart-define=USE_EMULATOR=true`: **yes**, both Auth and Firestore. The wiring
in `main_coach_hub.dart:53-60` works. This section exists because the obvious
way to check it produces a convincing false positive, and that cost an
afternoon.

### The trap — the emulator URL CONTAINS the production host

The Auth emulator does not invent its own path scheme. It mounts the real
Identity Toolkit path underneath itself, so the URL the SDK actually calls is:

```
http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=AIza...
```

`identitytoolkit.googleapis.com` there is a **path segment, not the origin**. A
`window.fetch` hook, a grep over a log, or any truncated readout will show that
substring on a perfectly correct emulator call. Reading it as
`https://identitytoolkit.googleapis.com/...` — "the app is talking to
production" — is wrong, and the request body is identical either way, so the
body proves nothing:

```json
{"returnSecureToken":true,"email":"...","password":"...","clientType":"CLIENT_TYPE_WEB"}
```

Same trap in the other direction: the red bar at the bottom of the page,
`Running in emulator mode. Do not use with production credentials.`, is injected
by the Firebase JS SDK's `connectAuthEmulator`, not by this repo:

```sh
rg -n 'Do not use with production credentials' .   # -> no hits
```

It proves the emulator wiring was applied to the default `FirebaseAuth`
instance. It does **not** prove where any individual request went.

### What actually decides it

Sign in as a user that exists ONLY in the emulator. If the app lets you in,
the call reached the emulator — there is no other explanation. Create one, note
`lastLoginAt`, log in from the app, and read it again:

```sh
curl -s -X POST -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
  'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/projects/treino-dev/accounts:query' \
  -d '{}' \
| python3 -c 'import sys,json;[print(u.get("email"),u.get("lastLoginAt")) for u in json.load(sys.stdin)["userInfo"]]'
```

Two things to know about that endpoint: it is a **POST**, and it needs
`Authorization: Bearer owner`. `GET /emulator/v1/projects/<id>/accounts` answers
`{"message":"Method GET not allowed"}` — a body with no `userInfo` key, which a
careless parser reports as "0 users" instead of as an error. Same for Firestore:
a plain `curl` of a document returns `403 PERMISSION_DENIED` because the
emulator applies `firestore.rules` to the REST API too. Add the owner token.

For the network view, read it in browser devtools (CDP level), not from a
`fetch` hook. Firestore is unambiguous there because it has no host-in-path
trick:

```
http://localhost:8080/google.firestore.v1.Firestore/Listen/channel?...&database=projects%2Ftreino-dev%2Fdatabases%2F(default)
```

### "La contraseña es incorrecta" was telling the truth

The seed password is `Emulator1234!` for **every** account (table above).
`emulador123` belongs to no seeded user, and the emulator rejects it:

```sh
curl -s -X POST 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key' \
  -H 'Content-Type: application/json' \
  -d '{"email":"coach.lautaro@emulator.treino","password":"emulador123","returnSecureToken":true}'
# -> {"error":{"code":400,"message":"INVALID_PASSWORD", ...}}
```

The emulator answers `400 INVALID_PASSWORD`, the SDK maps it to
`wrong-password`, and `AuthFailure` renders "La contraseña es incorrecta"
(`lib/features/auth/domain/auth_failure.dart:40-58`). A wrong password against
production renders the same string, so **the UI message is not evidence of where
the call went, in either direction**. Note also that `network-request-failed`
maps to "Sin conexión", not to the password message: if you are seeing the
password error, a request was made and a server answered it.

---

## What gets seeded

### Gyms (`gyms/`)
3 gyms in Buenos Aires (Hierro Palermo, Cadencia Caballito, Hierro Nueva Córdoba).

### Users + public profiles
- `users/{uid}` — full `UserProfile` including trainer fields for coaches.
- `userPublicProfiles/{uid}` — for all users (13 athletes + 3 coaches).
- `trainerPublicProfiles/{uid}` — for coaches, with geohash set to Buenos Aires
  so trainer discovery queries resolve them correctly.

Eight athletes share Martín's `gymId` but have no friendship with him. This
leaves more than five eligible candidates for “Sugerencias”, so the UI limit
and the remaining candidate pool can both be exercised.

### Trainer links (`trainer_links/`)

| ID | Trainer | Athlete | Status | Notes |
|---|---|---|---|---|
| seed-link-001 | Lautaro | Martín | **active** | session sharing ON |
| seed-link-002 | Lautaro | Sofía | **active** | sharing OFF |
| seed-link-003 | Camila | Mateo | **active** | session sharing ON |
| seed-link-004 | Diego | Valentina | **pending** | tests trainer inbox |
| seed-link-005 | Lautaro | Nicolás | **terminated** | tests history view |

`session_shares/{athleteId}` is also written for links where `sharedWithTrainer: true`
(Martín and Mateo), enabling the trainer to read their sessions.

### Routines (`routines/`)

| ID | Name | Weeks | Source | Assigned |
|---|---|---|---|---|
| seed-routine-001 | Fuerza Base – 3 semanas | 3 | trainer-assigned | Lautaro → Martín |
| seed-routine-002 | Crossfit WOD – 2 semanas | 2 | trainer-assigned | Camila → Mateo |
| seed-routine-003 | Full Body Principiante | 1 | system | public |

### Sessions (`users/{uid}/sessions/`)
- **Martín** — 14 sessions over 28 days, mix of `wasFullyCompleted: true/false`.
- **Mateo** — 8 sessions over 20 days, all `wasFullyCompleted: true`.
- **Sofía** — 4 sessions over 15 days, mix.

Streak + `workoutsCount` in `userPublicProfiles` are pre-computed to match.

### Posts (`posts/`)
81 posts covering all privacy levels, with 27 posts per tier:
- `public` — 27 posts (visible in home feed for any authenticated user)
- `friends` — 27 posts; the extra authors are accepted friends of Martín
- `gym` — 27 posts; 26 belong to Hierro Palermo and are visible to Martín

Every generated post has a distinct `createdAt`, separated by at least one
hour. Each tier therefore exceeds the repository page size of 20 and exercises
the second page, `hasMore`, infinite scroll, and the loading indicator without
losing documents at the strict cursor boundary.

### Friendships (`friendships/`)
- Martín ↔ Sofía — `accepted` (same gym, tests gym + friends feed)
- Martín ↔ Mateo — `accepted` (different gyms, tests friends-only feed)
- Sofía → Nicolás — `pending` (tests friendship inbox)

### Appointments (`appointments/`)
5 appointments across Lautaro (coach-001) and Camila (coach-002):
- 1 past (yesterday) — appears as "completada" in trainer dashboard.
- 2 today/tomorrow for Lautaro — "pendiente" and "próxima".
- 2 for Camila + Mateo — tests "Entrenaron hoy" section.

### Availability rules (`coach_availability_rules/`)
- Lautaro: Mon/Wed/Fri 09:00–13:00 — slots 60 min
- Camila: Tue/Thu 17:00–20:00 — slots 60 min
- Diego: Mon–Sat 08:00–11:30 — slots 90 min

---

## Suggested test scenarios

| Scenario | Login as |
|---|---|
| Full coach dashboard (trainer hub, appointments, athlete list) | `coach.lautaro@emulator.treino` |
| Pending trainer link in inbox | `coach.diego@emulator.treino` |
| Assigned routine + session history with streak | `martin@emulator.treino` |
| Beginner athlete, pending friendship request | `sofia@emulator.treino` |
| Advanced athlete, fully completed sessions, crossfit plan | `mateo@emulator.treino` |
| Athlete with no gym, no coach link | `nicolas@emulator.treino` |
| Coach discovery — all 3 coaches appear in Buenos Aires map | any athlete |
| Feed pagination in public, friends, and gym segments | `martin@emulator.treino` |
| Suggested users capped at 5 with extra candidates remaining | `martin@emulator.treino` |

---

## Extending

- To add more sessions, edit `SESSIONS` array or call `makeSessionsForAthlete()`.
- To add a coach location of type `custom` (no gym), set `gymId: null` in COACHES.
- To add recurring appointments, set `recurringId` to a shared string.
- All doc IDs are deterministic (`seed-*`) — re-running overwrites cleanly.
