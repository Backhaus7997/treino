#!/usr/bin/env bash
# scripts/test_rules.sh
#
# Smoke-test for Firestore + Storage security rules (posts, friendships,
# chatMedia, and the rest of scripts/rules_test/*.test.js).
#
# Run it:
#   npm --prefix scripts/rules_test ci   # once, or when package.json changes
#   bash scripts/test_rules.sh
#
# It brings its OWN emulator up and down (`emulators:exec` below), so there is
# nothing to start beforehand. Needs Java 21+ — the Emulator Suite of
# firebase-tools 15+ refuses to boot on anything older.
#
# ⚠️  NO ESQUIVES el Java 21 pinneando `firebase-tools@13`. Da CUATRO ROJOS
#     FALSOS sobre reglas que están perfectas, y el mensaje no dice "emulador
#     viejo": dice `PERMISSION_DENIED`, que es exactamente lo que dice un
#     agujero de seguridad real. Ya mandó a alguien a buscar un bug inexistente
#     en `firestore.rules` (2026-09-10).
#
#     La causa, aislada con un control negativo de ocho líneas —mismas reglas,
#     mismo cliente, misma máquina, lo único que cambia es el .jar:
#
#       cloud-firestore-emulator v1.21.0 (fb-tools 15) → get() de un doc que NO
#         existe devuelve `null`. Es el comportamiento de producción.
#       cloud-firestore-emulator v1.19.8 (fb-tools 13) → el mismo get() tira
#         `Service call error. Function: [get]` y revienta la evaluación entera
#         de la regla, que termina denegando.
#
#     Este repo usa ese idiom a propósito y en varios lados
#     (`paywallEnforcedFor`, `rutinaEsPaga` en firestore.rules): `let u =
#     get(...)` seguido de `u != null && ...`, para fallar ABIERTO cuando el
#     doc todavía no está. Contra el emulador 1.19.8 el guard `!= null` nunca
#     llega a correr. Los cuatro que caen son SCENARIO-PERIOD-050,
#     SCENARIO-PERIOD-054, SCENARIO-WPRES-RULES-01 y el "rutina inexistente"
#     de athlete-paywall-sessions.test.js — los únicos cuyo fixture, a
#     propósito, NO siembra el doc que el `get()` va a buscar.
#
#     En esta máquina el JDK 21 YA ESTÁ (Homebrew). El comando correcto:
#
#       JAVA_HOME=/opt/homebrew/opt/openjdk@21 \
#       PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH \
#       bash scripts/test_rules.sh
#
#     Verificado el 2026-09-10 sobre ecf0175a, sin cambios locales encima:
#     con fb-tools 13 → 4 failed / 183 passed; con el comando de arriba →
#     187/187, idéntico a lo que da el job `rules-test` de CI.
#
# Covers SCENARIO-130, SCENARIO-131, SCENARIO-132 (REQ-PFM-009, REQ-PFM-010),
# and SCENARIO-CHATMEDIA-* (rules-hardening Slice A, storage chatMedia).
#
# THIS SCRIPT IS THE CI GATE. The `rules-test` job of
# .github/workflows/ci.yml invokes this exact file — not a copy of its
# command — so what a dev runs locally and what blocks a merge cannot drift
# apart. It was a manual checklist item until #680 Slice B, and the drift that
# buys is measured: the suite had been red for weeks (4 stale assertions in
# rules.test.js, the oldest dating to 2026-06-09) and nobody found out,
# because "run it before merging" is not a gate.
#
# If you add a *.test.js file to scripts/rules_test/, it is picked up here
# automatically — jest globs the directory, there is no list to update.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES_TEST_DIR="${SCRIPT_DIR}/rules_test"

# --- ensure test suite exists ------------------------------------------------
if [[ ! -f "${RULES_TEST_DIR}/rules.test.js" ]]; then
  echo "ERROR: rules test file not found at ${RULES_TEST_DIR}/rules.test.js"
  echo "Create it first (see companion JS suite)."
  exit 1
fi

# --- run via firebase emulators:exec -----------------------------------------
#
# NOTE (rules-hardening Slice B): multiple *.test.js sibling files share the
# SAME emulator PROJECT_ID ('treino-test-rules'). Jest's default parallel
# worker execution runs sibling test files concurrently against that one
# shared emulator project, so one file's `afterEach(testEnv.clearFirestore())`
# can wipe data another file just seeded moments earlier mid-test — flaky,
# order-dependent false failures with no rule defect involved. `--runInBand`
# forces serial execution (one file/test at a time) and eliminates the
# collision. Confirmed via isolated runs during Slice B apply.
# --- por qué `--project treino-dev` explícito (#840) --------------------------
#
# El default de `.firebaserc` pasó a ser `demo-treino` — un id que Firebase
# trata como proyecto offline del emulador — para que un `deploy` o un
# `firestore:delete` sin `--project` FALLE en vez de resolver a produccion desde
# cualquiera de los ~27 worktrees del repo. Este comando resolvía por ese
# default, así que ahora nombra su proyecto.
#
# El id NO es cosmético, y está MEDIDO: correr esta misma suite con
# `--project demo-treino` deja `chat-media-storage.test.js` en rojo
# (SCENARIO-CHATMEDIA-05 y 05b, `storage/unauthorized` para un miembro legítimo
# del chat), mientras que con `treino-dev` da 149/149. La causa está escrita en
# la cabecera de ese archivo: `firebase.json` tiene
# `emulators.singleProjectMode: true`, que pinea el `firestore.get()`
# cross-service de las reglas de Storage al proyecto DEFAULT del emulador. Con
# otro id, ese `get` busca el doc de chat bajo el proyecto equivocado y la regla
# deniega. O sea: sin este flag, este gate de CI se ponía rojo.
#
# `emulators:exec` además exporta el id resuelto como GCLOUD_PROJECT, que es de
# donde lo lee el hermano de functions/ (session-feedback-storage-rules.test.ts).
cd "${SCRIPT_DIR}/.."
firebase emulators:exec \
  --only firestore,storage \
  --project treino-dev \
  "cd scripts/rules_test && npx jest --runInBand"
