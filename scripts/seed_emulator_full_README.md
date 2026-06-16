# scripts/seed_emulator_full.js

Full-stack emulator seed for manual testing of TREINO. Creates Auth users and
Firestore documents for 3 coaches (trainers) and 5 athletes, with trainer
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

In another terminal:

```sh
flutter run --dart-define=USE_EMULATOR=true
```

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
| `martin@emulator.treino` | `Emulator1234!` | Martín López | Megatlon Palermo | intermediate |
| `sofia@emulator.treino` | `Emulator1234!` | Sofía Ramírez | Megatlon Palermo | beginner |
| `mateo@emulator.treino` | `Emulator1234!` | Mateo Quiroga | SmartFit Caballito | advanced |
| `valentina@emulator.treino` | `Emulator1234!` | Valentina Peralta | SmartFit Caballito | intermediate |
| `nicolas@emulator.treino` | `Emulator1234!` | Nicolás Fernández | — | beginner |

---

## What gets seeded

### Gyms (`gyms/`)
3 gyms in Buenos Aires (Megatlon Palermo, SmartFit Caballito, Megatlon Nueva Córdoba).

### Users + public profiles
- `users/{uid}` — full `UserProfile` including trainer fields for coaches.
- `userPublicProfiles/{uid}` — for all users (5 athletes + 3 coaches).
- `trainerPublicProfiles/{uid}` — for coaches, with geohash set to Buenos Aires
  so trainer discovery queries resolve them correctly.

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
9 posts covering all privacy levels:
- `public` — 3 posts (visible in home feed for any authenticated user)
- `friends` — 3 posts (visible only to `members` of accepted friendships)
- `gym` — 3 posts (visible to users sharing the same `gymId`)

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

---

## Extending

- To add more sessions, edit `SESSIONS` array or call `makeSessionsForAthlete()`.
- To add a coach location of type `custom` (no gym), set `gymId: null` in COACHES.
- To add recurring appointments, set `recurringId` to a shared string.
- All doc IDs are deterministic (`seed-*`) — re-running overwrites cleanly.
