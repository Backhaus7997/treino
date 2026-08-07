#!/usr/bin/env bash
#
# conformance/run_swift.sh
#
# Corre los fixtures compartidos contra la implementación SWIFT — la misma que
# usa el reloj, no una copia.
#
# El lado Dart corre los MISMOS archivos dentro de `flutter test`. Los dos
# juntos son la única red contra el riesgo estructural de este change: las
# mismas reglas escritas dos veces divergen, y cuando eso pasa el historial del
# usuario se corrompe en silencio.
#
#   bash conformance/run_swift.sh
#
# Requiere `swiftc` (viene con Xcode o con las Command Line Tools).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Se compila el archivo REAL del reloj, no una copia. Si alguien lo cambia sin
# tocar el contrato, este corredor se pone rojo — que es todo el punto.
WATCH_SOURCES=(
  "${REPO_ROOT}/ios/TreinoWatch Watch App/PlanAdvance.swift"
  "${REPO_ROOT}/ios/TreinoWatch Watch App/RoutineSelection.swift"
)

for src in "${WATCH_SOURCES[@]}"; do
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
  "${SCRIPT_DIR}/swift/main.swift" \
  -o "${BIN_DIR}/conformance"

"${BIN_DIR}/conformance" "${SCRIPT_DIR}"
