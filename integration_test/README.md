# TREINO — E2E integration tests (QA Fase 6)

Five end-to-end suites that drive the **real** `TreinoApp` against the local
**Firebase emulators** (Auth `9099`, Firestore `8080` on `127.0.0.1`). They are
written and ready but **not yet runnable**: the `integration_test` package is
intentionally **not** in `dev_dependencies`. QA does not touch `pubspec.yaml` —
enabling the dependency is the runner's call (one line, below).

> ⚠️ **Emulators only, never cloud.** Every suite wires `useAuthEmulator` /
> `useFirestoreEmulator` to `127.0.0.1`. Do not run these against a real
> Firebase project.

## Suites

| File | Flow |
|------|------|
| `login_to_home_test.dart` | login → `/home` |
| `register_to_home_test.dart` | register → profile-setup → `/home` |
| `workout_session_flow_test.dart` | start session → session player → summary |
| `coach_athlete_chat_test.dart` | coach ↔ athlete 1-1 chat |
| `my_routine_edit_test.dart` | edit own routine |
| `support/e2e_helpers.dart` | shared bootstrap + driving helpers (not a suite) |

Each suite has a **SEED CONTRACT** header describing the emulator data it needs
(a verified user, an assigned routine, a chat doc, …) and inline `TODO(seed)` /
`TODO(finder)` / `TODO(activate)` markers where a real uid, id, or the exact
last-mile widget interaction must be filled in. They compile and boot the app;
the seed-dependent assertions are marked so the flow can be completed once the
emulator is seeded.

## Prerequisites (see `qa-report/environment.md`)

- **Flutter 3.41** stable / Dart 3.11 (already installed).
- **JDK 21** for `firebase-tools` 15.x — the **only** JDK that unblocks the
  emulators. The Oracle Java 8 shim wins on `PATH` by default, so you must
  override `JAVA_HOME`. On this machine JDK 21 lives in the Android Studio JBR.
- **An Android AVD.** Two are available: **`Pixel_6`** and **`Pixel_9_Pro`**.
- Firebase emulators configured in `firebase.json` (auth 9099, firestore 8080,
  functions 5001, storage 9199).

## One-step enable + run

**1. Add the dependency** (the only `pubspec.yaml` edit — runner's decision):

```yaml
# pubspec.yaml → dev_dependencies:
  integration_test:
    sdk: flutter
```

**2. Then, from the repo root:**

```bash
# Fetch the new dev dependency.
flutter pub get

# Boot an Android emulator (either AVD works).
flutter emulators --launch Pixel_6      # or: Pixel_9_Pro

# Start the Firebase emulators in a SEPARATE terminal. JAVA_HOME must point at
# JDK 21 (msys path form — the C: form gets split on the ':' by Git Bash).
export JAVA_HOME="C:/Program Files/Android/Android Studio/jbr"
export PATH="/c/Program Files/Android/Android Studio/jbr/bin:$PATH"; hash -r
# Vía el script: fija `--project treino-dev`, el namespace donde siembran los
# seeds. El default de .firebaserc es `demo-treino` a propósito (#840).
SKIP_FUNCTIONS=1 ./scripts/emulator.sh

# Seed the emulator with the SEED CONTRACT data for the suites you want to run
# (Auth user + Firestore docs). See each suite header + its TODO(seed) markers.

# Run all five E2E suites on the running AVD.
flutter test integration_test/
```

Run a single suite instead:

```bash
flutter test integration_test/login_to_home_test.dart
```

### Optional: `flutter drive` (screenshots / device farm)

`flutter test integration_test/` is enough for CI on a connected device/AVD.
Use `flutter drive` only when you need a driver-side hook (screenshots, perf
timelines):

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/login_to_home_test.dart
```

(That requires a `test_driver/integration_test.dart` shim — one line re-exporting
`integration_test`'s `integrationDriver`. Not needed for the plain
`flutter test integration_test/` path.)

## Notes for the runner

- **`flutter analyze` will flag `package:integration_test/...` as unresolved
  until step 1 is done.** That is expected — the import is correct; the package
  is just not installed yet. The unit-test suite under `test/` is unaffected
  (these files live in the separate top-level `integration_test/` folder and are
  not picked up by `flutter test` without a path).
- If first frame hangs, it is almost certainly the FCM / notification providers
  that `TreinoApp.initState` eagerly reads on a bare AVD — see the
  `TODO(e2e-infra)` note in `support/e2e_helpers.dart` (`pumpTreinoApp` accepts
  provider `overrides` to stub them).
- iOS E2E is **out of scope** here (needs a Mac) — tracked in
  `qa-report/manual-checklist.md`.
