#!/usr/bin/env bash
#
# scripts/typecheck_watch.sh
#
# Typecheck del codigo del reloj en segundos, contra los +20 minutos que tarda
# `xcodebuild`.
#
#   bash scripts/typecheck_watch.sh
#
# POR QUE ESTE SCRIPT Y NO EL COMANDO SUELTO
#
# El comando corto que veniamos usando —swiftc -typecheck contra el SDK de
# watchOS, sin mas— NO reproduce los flags del target, y por eso deja pasar
# errores que despues aparecen recien en el build largo.
#
# Medido en el change `watch-workout-session`, F0: un archivo que usaba
# `@Published` sin `import Combine` pasaba el typecheck corto y rompia el
# build. La razon es que el target activa MemberImportVisibility, que exige
# que cada archivo importe lo que usa; sin ese flag, el import de OTRO archivo
# del mismo lote alcanzaba para que resolviera.
#
# Costo: un build de 20 minutos. Por eso los flags viven acá y no en la memoria
# de quien escribe el comando.
#
# Los flags salen de las tres configuraciones del target en project.pbxproj:
#   SWIFT_VERSION = 5.0
#   SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
#   WATCHOS_DEPLOYMENT_TARGET = 26.2
#
# Esto NO reemplaza al build: no linkea, no firma, no arma el bundle ni corre
# nada. Es el filtro rapido de antes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WATCH_DIR="${REPO_ROOT}/ios/TreinoWatch Watch App"

if [[ ! -d "${WATCH_DIR}" ]]; then
  echo "ERROR: no se encontró ${WATCH_DIR}" >&2
  exit 1
fi

DEPLOYMENT_TARGET="26.2"
SDK_PATH="$(xcrun --sdk watchos --show-sdk-path)"

# `-sdk iphonesimulator` pisa el SDKROOT de TODOS los targets y compila el reloj
# contra iOS, dando errores falsos. Acá se apunta al SDK de watchOS derecho.
xcrun swiftc -typecheck \
  -sdk "${SDK_PATH}" \
  -target "arm64_32-apple-watchos${DEPLOYMENT_TARGET}" \
  -swift-version 5 \
  -enable-upcoming-feature MemberImportVisibility \
  "${WATCH_DIR}/"*.swift

echo "OK: typecheck del reloj limpio"
