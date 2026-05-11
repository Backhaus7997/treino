#!/usr/bin/env bash
set -euo pipefail

# Launches Firebase emulator suite for TREINO local dev.
# Firestore: localhost:8080
# Auth:      localhost:9099
# UI:        localhost:4000
#
# Run the Flutter app in a separate shell:
#   flutter run --dart-define=USE_EMULATOR=true

firebase emulators:start --only firestore,auth
