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
#
# --------------------------------------------------------------------------
# Por qué `--project treino-dev` explícito en los dos `emulators:start` (#840)
# --------------------------------------------------------------------------
# El default de `.firebaserc` YA NO es `treino-dev`: es `demo-treino`, un id
# que Firebase trata como proyecto offline del emulador. El motivo es que este
# repo vive en ~27 directorios simultáneos (repo raíz + los worktrees de
# .claude/worktrees/), cada uno con su copia de `.firebaserc` y un agente
# adentro; con el default apuntando a producción, un `deploy` o un
# `firestore:delete` sin `--project` tocaba datos de usuarios reales. Ahora
# falla, que es exactamente lo que queremos (#826, #840).
#
# Pero el emulador SÍ necesita `treino-dev`, porque ese id es el NAMESPACE
# local donde viven los datos, y ese namespace ya está fijado en dos lados que
# no cambian acá:
#   - la app Flutter se inicializa con `lib/firebase_options.dart` → treino-dev
#   - `scripts/seed_emulator_full.js:50` → admin.initializeApp({projectId:'treino-dev'})
# Con `demo-treino` acá el emulador levantaría igual, pero la UI de :4444
# apuntaría a un namespace vacío mientras la app y la semilla escriben en otro.
# Medido en el emulador: tras `seed_emulator_full.js`, el proyecto `treino-dev`
# tiene 16 usuarios de Auth y 81 posts / 16 users / 3 gyms en Firestore, y
# `demo-treino` tiene CERO de todo. No se pierde nada, pero "no aparece nada"
# es la peor forma de romper el arranque local.
#
# Lo que NO es cierto (se verificó, y vale escribirlo para que nadie lo repita):
# el emulador de Firestore aplica `firestore.rules` a CUALQUIER proyecto que le
# pidan, no sólo al default. Un GET sin auth a `demo-treino` devuelve el mismo
# PERMISSION_DENIED con línea de regla que a `treino-dev`. Donde el proyecto
# default SÍ decide el resultado es en las reglas de Storage que hacen
# `firestore.get()` cross-service — ahí manda `emulators.singleProjectMode: true`
# de firebase.json. Eso vive en scripts/test_rules.sh, no acá.
#
# `emulators:start` no toca la red de los servicios emulados, así que nombrar
# treino-dev acá no alcanza producción. Lo que alcanzaba producción era el
# default, y el default ya no puede.

if [ "${SKIP_FUNCTIONS:-0}" = "1" ]; then
  echo "SKIP_FUNCTIONS=1 -> Firestore + Auth solamente (sin Functions)."
  exec firebase emulators:start --only firestore,auth --project treino-dev
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

exec firebase emulators:start --only firestore,auth,functions --project treino-dev
