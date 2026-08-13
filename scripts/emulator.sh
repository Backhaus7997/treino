#!/usr/bin/env bash
set -euo pipefail

# Launches the Firebase Emulator Suite for TREINO local dev.
#
#   Firestore:  localhost:8080
#   Auth:       localhost:9099
#   Functions:  localhost:5001   (rankings, borrado en cascada, notificaciones)
#   UI:         localhost:4444
#
# Las Cloud Functions ahora corren en el emulador, así que las features que
# dependen de ellas son testeables en local. Ej: los rankings de VOLUMEN/LIFTS
# los calcula functions/src/ranking-aggregate.ts; sin el emulador de functions
# esos rankings quedaban siempre vacíos aunque el alumno estuviera adentro (#365).
#
# Requisitos (solo para el modo con Functions):
#   - Java 21+  — el emulador de firebase-tools 15+ no arranca con Java 17.
#   - Deps de functions instaladas:  (cd functions && npm install)
#
# Modo liviano (solo Firestore + Auth, sin compilar TS ni tocar functions/):
#   SKIP_FUNCTIONS=1 ./scripts/emulator.sh
#
# Corré la app Flutter en otra terminal:
#   flutter run --dart-define=USE_EMULATOR=true

if [ "${SKIP_FUNCTIONS:-0}" = "1" ]; then
  echo "SKIP_FUNCTIONS=1 -> Firestore + Auth solamente (sin Functions)."
  exec firebase emulators:start --only firestore,auth
fi

# El emulador carga las Functions desde functions/lib (JS compilado, gitignoreado),
# así que compilamos TypeScript -> lib/ antes de arrancar (mismo patrón que el
# script `serve` de functions/package.json). tsc es rápido e idempotente.
if [ ! -d functions/node_modules ]; then
  echo "ERROR: faltan las dependencias de functions." >&2
  echo "Instalalas con:  (cd functions && npm install)" >&2
  echo "O levantá el emulador liviano con:  SKIP_FUNCTIONS=1 ./scripts/emulator.sh" >&2
  exit 1
fi
npm --prefix functions run build

exec firebase emulators:start --only firestore,auth,functions
