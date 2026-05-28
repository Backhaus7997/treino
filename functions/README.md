# TREINO Cloud Functions

Firebase Cloud Functions for the TREINO app — Node.js 20 + TypeScript 5.

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
# From project root
firebase emulators:start --only firestore,auth

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
# From project root — builds functions first via predeploy hook
firebase emulators:start --only firestore,auth,functions
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

```bash
# Authenticate first
firebase login --reauth

# Deploy to treino-dev (requires Blaze plan)
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
