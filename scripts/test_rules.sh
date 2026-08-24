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
cd "${SCRIPT_DIR}/.."
firebase emulators:exec \
  --only firestore,storage \
  "cd scripts/rules_test && npx jest --runInBand"
