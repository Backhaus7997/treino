#!/usr/bin/env bash
#
# scripts/test_watch_swift.sh
#
# Corre los tests de la logica PURA del reloj en el host — segundos, sin
# simulador y sin xcodebuild.
#
#   bash scripts/test_watch_swift.sh
#
# Se compila el archivo REAL del reloj, no una copia: si alguien lo cambia sin
# tocar los tests, este corredor se pone rojo. Mismo principio que
# `conformance/run_swift.sh`, distinto contrato — aquellos fixtures son el
# acuerdo Dart<->Swift, estos son reglas que solo viven en el reloj.
#
# Los archivos que corren acá se mantienen libres de HealthKit. Ojo con el
# porque: HealthKit SI existe en macOS (`import HealthKit`, `HKHealthStore` y
# `HKObjectType.workoutType()` compilan). Lo que es watchOS-only es la parte de
# SESION DE ENTRENAMIENTO — `HKWorkoutSession.init(healthStore:configuration:)`
# da "unavailable in macOS". Medido.
#
# O sea que la regla no es "no se puede importar", es "no hace falta": la
# decision no necesita el framework, y no arrastrarlo la deja verificable en
# segundos. Lo que si toca HealthKit se typechequea contra el SDK de watchOS
# con `scripts/typecheck_watch.sh`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WATCH_SOURCES=(
  "${REPO_ROOT}/ios/TreinoWatch Watch App/HealthAccess.swift"
  "${REPO_ROOT}/ios/TreinoWatch Watch App/WorkoutSessionLifecycle.swift"
  "${REPO_ROOT}/ios/TreinoWatch Watch App/HeartRateRules.swift"
  "${REPO_ROOT}/ios/TreinoWatch Watch App/WorkoutDurationRules.swift"
)

TEST_SOURCES=(
  "${REPO_ROOT}/ios/watch_tests/main.swift"
)

for src in "${WATCH_SOURCES[@]}" "${TEST_SOURCES[@]}"; do
  if [[ ! -f "${src}" ]]; then
    echo "ERROR: no se encontró ${src}" >&2
    echo "El corredor compila el código real del reloj; si la ruta cambió," >&2
    echo "actualizá WATCH_SOURCES en este script." >&2
    exit 1
  fi
done

if ! command -v swiftc >/dev/null 2>&1; then
  echo "ERROR: no hay swiftc en el PATH (viene con Xcode)." >&2
  exit 1
fi

BIN_DIR="$(mktemp -d)"
trap 'rm -rf "${BIN_DIR}"' EXIT

swiftc -O \
  "${WATCH_SOURCES[@]}" \
  "${TEST_SOURCES[@]}" \
  -o "${BIN_DIR}/watch_tests"

"${BIN_DIR}/watch_tests"
