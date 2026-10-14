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
# Requisitos:
#   - Java 21+  — lo exige firebase-tools 15+ para CUALQUIER emulador, no sólo
#     para el de Functions. **Ya no hace falta resolverlo a mano**: este script
#     busca un JDK 21 si el del PATH no sirve (ver `lib/java21.sh`). Android
#     Studio trae el suyo y es el primero de la lista.
#   - Deps de functions instaladas (sólo para el modo con Functions):
#     (cd functions && npm install)
#
# Modo liviano (solo Firestore + Auth, sin compilar TS ni tocar functions/):
#   SKIP_FUNCTIONS=1 ./scripts/emulator.sh
#
# Corré la app Flutter en otra terminal:
#   flutter run --flavor phone --dart-define=USE_EMULATOR=true
#
# El `--flavor phone` NO es opcional en Android: `android/app/build.gradle.kts`
# declara DOS flavors —`phone` y `wear`— y sin elegir uno el build falla. Esta
# línea lo omitía, así que el comando que documentaba no corría.
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
# que el proyecto decida si el emulador de Firestore aplica reglas. Las aplica
# a CUALQUIER proyecto que le pidan, no sólo al default: con las reglas
# cargadas, un GET y un PATCH sin auth dan 403 tanto en `demo-treino` como en
# `treino-dev` (medido otra vez el 2026-10-14). Donde el proyecto default SÍ
# decide el resultado es en las reglas de Storage que hacen `firestore.get()`
# cross-service — ahí manda `emulators.singleProjectMode: true` de
# firebase.json. Eso vive en scripts/test_rules.sh, no acá.
#
# `emulators:start` no toca la red de los servicios emulados, así que nombrar
# treino-dev acá no alcanza producción. Lo que alcanzaba producción era el
# default, y el default ya no puede.
#
# --------------------------------------------------------------------------
# Qué reglas carga el emulador de Firestore, y por qué este script las genera
# --------------------------------------------------------------------------
# NO carga `firestore.rules`. Carga el archivo que `firebase.json` nombra en
# `firestore.rules`, y desde el #1132 (2026-09-15) ese archivo es
# `firestore.deploy.rules`: las mismas reglas sin comentarios, que genera
# `scripts/strip_rules.js` y que está en `.gitignore`. El `predeploy` lo genera
# para el deploy; para el emulador no lo generaba nadie.
#
# Y si falta, el emulador NO falla. Avisa dos cosas —"Cloud Firestore rules
# file <ruta> specified in firebase.json does not exist." y "The emulator will
# default to allowing all reads and writes."— y la segunda la cumple. Eso
# pasaba en todo clone y todo worktree limpio. Medido el 2026-10-14 sobre
# develop: un PATCH SIN auth que crea `users/victima` con `role: "trainer"`
# —lo que la regla 3 de AGENTS.md reserva al Admin SDK— devolvía 200. Con el
# archivo generado, 403.
#
# Por eso se corre `strip_rules.js` antes de levantar el emulador, y si falla
# no se levanta. Se regenera SIEMPRE, no sólo cuando falta: un
# `firestore.deploy.rules` que quedó de otra corrida son las reglas de otro día
# con cara de las de hoy. Lo fija `scripts/test/emulator_genera_reglas.test.js`.
#
# ⚠ Editar `firestore.rules` con el emulador corriendo NO se refleja solo. El
# emulador recarga las reglas en caliente, pero el archivo que vigila es
# `firestore.deploy.rules`. Después de cada edición, en otra terminal:
#
#   node scripts/strip_rules.js
#
# y el emulador loguea "Change detected, updating rules...". Medido el
# 2026-10-14: editar sólo `firestore.rules` deja cargadas las reglas viejas
# (403 → 403); correr el strip las actualiza (→ 200, con una regla allow-all).
#
# No se agregó un watcher que lo haga solo, a propósito: sería un proceso más
# corriendo detrás del emulador, y si el strip fallara ahí adentro —reglas
# pasadas del límite, por ejemplo— no escribe nada, así que quedarían cargadas
# las viejas con el aviso enterrado en el log.
#
# Casi todas las suites de reglas son independientes de esto: `scripts/rules_test/`
# y los `*-rules.test.ts` de functions leen `firestore.rules` directo y, salvo
# los de análisis estático, lo cargan con `initializeTestEnvironment`. Las
# excepciones son las dos `watch-rest-*-rules.test.ts`: le pegan al emulador
# por REST y miden las reglas que ÉL tenga cargadas, o sea las que nombra
# `firebase.json`. Para listarlas:
#
#   rg --files-without-match initializeTestEnvironment functions/src/__tests__ -g '*rules*.test.ts'
#
# (da tres; `rules-read-isolation.test.ts` es estático y lee `firestore.rules`.)

# Java 21+, que `firebase-tools` 15+ exige para cualquier emulador.
#
# Va ANTES del branch de SKIP_FUNCTIONS a propósito: ese camino también levanta
# Firestore y Auth, y los dos son Java. Ponerlo abajo dejaba al modo liviano
# —el que usa quien no quiere compilar TypeScript— chocándose igual.
#
# `asegurar_java21` no hace NADA si el `java` del PATH ya sirve, así que esto no
# cambia el comportamiento en ninguna máquina donde hoy funcione.
# shellcheck source=lib/java21.sh
source "$(dirname "$0")/lib/java21.sh"
asegurar_java21 || exit 1

abortar_sin_reglas() {
  {
    echo ""
    echo "ERROR: no se pudo generar firestore.deploy.rules; el emulador NO se levanta."
    echo "Levantarlo igual sería correr con las reglas de otra corrida o, si el"
    echo "archivo no existe, sin ninguna: el emulador de Firestore cae a allow-all."
  } >&2
  exit 1
}

# Las reglas que va a cargar el emulador (ver "Qué reglas carga" arriba). Va
# antes del branch de SKIP_FUNCTIONS para cubrir los dos `emulators:start`.
# `strip_rules.js` resuelve sus rutas desde su propio directorio: escribe en la
# raíz del repo, al lado de `firebase.json`, que es donde el emulador lo busca.
node "$(dirname "$0")/strip_rules.js" || abortar_sin_reglas

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
