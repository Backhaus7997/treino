#!/usr/bin/env bash
# scripts/test_rules.sh
#
# Manual smoke-test for Firestore security rules covering posts and friendships.
# Requires the Firebase emulator to be running:
#
#   bash scripts/emulator.sh   (or firebase emulators:start)
#
# Then run:
#   bash scripts/test_rules.sh
#
# Covers SCENARIO-130, SCENARIO-131, SCENARIO-132 (REQ-PFM-009, REQ-PFM-010).
# NOT part of CI — this is a manual PR checklist item (reconsider at Fase 6).

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
cd "${SCRIPT_DIR}/.."
firebase emulators:exec \
  --only firestore \
  "cd scripts/rules_test && npm test"
