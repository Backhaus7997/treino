# TREINO Cloud Functions

Firebase Cloud Functions for the TREINO app — Node.js 20 + TypeScript 5.

> ## 🚨 `treino-dev` IS PRODUCTION
>
> It is TREINO's **only** Firebase project — `treino-prod` does not exist, and
> there is no separate cloud dev environment. Real users live there. The
> `firebase deploy` under [Deploying](#deploying) publishes to them.
>
> **A bare `firebase deploy`, with no `--project`, goes there too.**
> `.firebaserc` declares `"default": "treino-dev"` and the CLI fills it in
> silently, so nothing on the command line warns you. Run `firebase use`
> (read-only) first to see which project you are actually pointed at.
>
> Emulators are the only disposable environment — everything under
> [Running Tests](#running-tests) is safe. Read
> [AGENTS.md → Entornos](../AGENTS.md#-entornos--leer-antes-de-correr-cualquier-comando) before deploying. (#826)

## Prerequisites

- Node.js 20+
- Java 21+ (required by Firebase Emulator Suite as of firebase-tools v15)
- Firebase CLI: `npm install -g firebase-tools`
- Blaze (pay-as-you-go) plan on `treino-dev` — required for Cloud Functions deployment

## Local Setup

```bash
cd functions
npm install
```

## Running Tests

Tests run against the Firebase Local Emulator Suite. Start emulators first:

```bash
# From project root. El script fija `--project treino-dev`, que es el namespace
# donde la app y las semillas escriben; un `emulators:start` pelado resolvería
# `demo-treino` (el default seguro de .firebaserc, #840) y los datos quedarían
# en otro proyecto: la UI de :4444 vacía y las suites de Storage en rojo.
SKIP_FUNCTIONS=1 ./scripts/emulator.sh

# In a second terminal
cd functions
npm test
```

Note: set `JAVA_HOME` to a Java 21+ installation before starting emulators:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21   # macOS via Homebrew
```

## Running the Full Emulator (with Functions)

```bash
# From project root — compila functions antes de arrancar, y fija
# `--project treino-dev` (ver nota de arriba, #840).
./scripts/emulator.sh
```

The `deleteAccount` callable will be available at:
`http://127.0.0.1:5001/treino-dev/us-central1/deleteAccount`

## Type Checking

```bash
cd functions
npx tsc --noEmit
```

## Lint

```bash
cd functions
npm run lint
```

## Building

```bash
cd functions
npm run build
# Outputs compiled JS to functions/lib/
```

## Deploying

⚠️ **This deploys to PRODUCTION.** `treino-dev` is TREINO's only Firebase
project and it serves real users (#826). Maintainer sign-off required. Dropping
`--project treino-dev` does **not** make it safer — `.firebaserc` defaults to
the same project, it just stops showing you the name.

```bash
# Authenticate first
firebase login --reauth

# Confirm the target BEFORE deploying (read-only)
firebase use

# ⚠️ WRITES TO PRODUCTION — treino-dev is the live project (requires Blaze plan)
firebase deploy --only functions --project treino-dev
```

> **Important**: Do NOT deploy from a feature branch. Deployment is handled via the main branch after PR merge.

## Architecture

- `src/index.ts` — function exports (entry point for Firebase runtime)
- `src/delete-account.ts` — `deleteAccount` callable handler + core logic
- `src/cascade/audit-log.ts` — audit log helper (writeStarted / writeFinal)
- `src/types.ts` — shared TypeScript interfaces

## PR Roadmap

| PR | Scope |
|----|-------|
| PR#1 (this) | CF skeleton: auth guard, anti-spoof, audit log, Auth user deletion |
| PR#2 | Full Firestore + Storage cascade (6 modules) |
| PR#3 | Flutter UI: re-auth sheet, deletion notifier, profile tile rewiring |
