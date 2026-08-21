#!/usr/bin/env bash
#
# scripts/test_watch_capabilities.sh
#
# Guard de las capabilities del target watchOS (change `watch-workout-session`,
# fase F0).
#
#   bash scripts/test_watch_capabilities.sh
#
# POR QUE EXISTE ESTE TEST
#
# Una capability que se pierde de `project.pbxproj` NO rompe la compilacion. La
# app sigue compilando, se instala y arranca igual; el unico sintoma es que
# HealthKit niega todo en silencio en la muñeca del atleta. Es el peor modo de
# falla que hay: verde en todos lados menos donde importa.
#
# Y el archivo lo reescriben las herramientas, no solo las personas:
#
#   - CocoaPods lo reescribe entero en cada `pod install`. Una version de
#     Xcodeproj que no entienda una clave puede descartarla al escribir, sin
#     error (documentado en docs/setup/watchos-target.md, donde casi se come
#     el enganche del target del reloj).
#   - El paso de configuracion de iOS de Flutter lo toca en cada build
#     (reescribe `objectVersion`, ver commit 29bf0f90).
#
# Este corredor convierte esa perdida silenciosa en CI rojo.
#
# No necesita Xcode ni el bootstrap de Flutter: lee las fuentes commiteadas,
# que son justamente las que esas herramientas pisan.
#
# Cubre: entitlement de HealthKit, su enganche a las TRES configuraciones del
# target, y los textos de permiso que ve el atleta.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PBXPROJ="${REPO_ROOT}/ios/Runner.xcodeproj/project.pbxproj"
ENTITLEMENTS="${REPO_ROOT}/ios/TreinoWatch Watch App/TreinoWatch Watch App.entitlements"
# Ruta relativa al .xcodeproj, que es como la escribe Xcode en el pbxproj.
ENTITLEMENTS_REL="TreinoWatch Watch App/TreinoWatch Watch App.entitlements"

INFOPLIST="${REPO_ROOT}/ios/TreinoWatch-Info.plist"
INFOPLIST_REL="TreinoWatch-Info.plist"

# El target del reloj es el UNICO que declara app companion. Sirve de ancla
# para encontrar sus configuraciones sin clavar UUIDs, que cambian.
WATCH_MARKER="INFOPLIST_KEY_WKCompanionAppBundleIdentifier"
EXPECTED_CONFIGS=3  # Debug, Release, Profile

failures=0

fail() {
  echo "  ✗ $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "  ✓ $1"
}

# --- 1. El archivo de entitlements ------------------------------------------

echo "Entitlements del reloj"

if [[ ! -f "${ENTITLEMENTS}" ]]; then
  fail "no existe ${ENTITLEMENTS_REL}"
else
  pass "existe ${ENTITLEMENTS_REL}"

  # Se lee con python3 y no con `plutil` para que este corredor pueda vivir en
  # un runner de linux, igual que `conformance/run_swift.sh`: un job macOS sale
  # diez veces mas caro y acá no hace falta.
  healthkit="$(python3 - "${ENTITLEMENTS}" <<'PY' 2>/dev/null || echo "ILEGIBLE"
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        print(plistlib.load(f).get("com.apple.developer.healthkit", "AUSENTE"))
except Exception:
    print("ILEGIBLE")
PY
)"
  case "${healthkit}" in
    ILEGIBLE) fail "${ENTITLEMENTS_REL} no es un plist valido" ;;
    True)     pass "com.apple.developer.healthkit = true" ;;
    *)        fail "com.apple.developer.healthkit no esta en true (esta: ${healthkit})" ;;
  esac
fi

# --- 1b. El background mode de entrenamiento ---------------------------------
#
# Sin `WKBackgroundModes = workout-processing` el reloj se suspende al bajar la
# muñeca AUNQUE haya una HKWorkoutSession abierta, y el descanso muere.
#
# Esto NO es teoria, esta medido con las cuatro combinaciones (F1):
#
#   ni sesion ni background mode ........ perdio 57s en 84 reales
#   sesion abierta, SIN background mode .. perdio 53s en 62
#   background mode, SIN sesion .......... perdio 50s en 56
#   sesion + background mode ............. perdio  1s en 58
#
# Los dos son necesarios y ninguno alcanza solo. Por eso el guard cubre los dos:
# perder cualquiera de los dos devuelve el bug, y sin sintoma visible.

echo
echo "Background mode de entrenamiento"

if [[ ! -f "${INFOPLIST}" ]]; then
  fail "no existe ${INFOPLIST_REL}"
else
  pass "existe ${INFOPLIST_REL}"

  modes="$(python3 - "${INFOPLIST}" <<'PY' 2>/dev/null || echo "ILEGIBLE"
import plistlib, sys
try:
    with open(sys.argv[1], "rb") as f:
        print(",".join(plistlib.load(f).get("WKBackgroundModes", [])))
except Exception:
    print("ILEGIBLE")
PY
)"
  case "${modes}" in
    ILEGIBLE)            fail "${INFOPLIST_REL} no es un plist valido" ;;
    *workout-processing*) pass "WKBackgroundModes incluye workout-processing" ;;
    *)                   fail "WKBackgroundModes no incluye workout-processing (esta: '${modes}')" ;;
  esac
fi

# Y que las TRES configuraciones lo enganchen: un Info.plist que no esta
# referenciado no llega al bundle, y el sintoma seria identico a no tenerlo.
infoplist_refs="$(grep -c "INFOPLIST_FILE = \"${INFOPLIST_REL}\"" "${PBXPROJ}" || true)"
if [[ "${infoplist_refs}" -ne "${EXPECTED_CONFIGS}" ]]; then
  fail "INFOPLIST_FILE apunta a ${INFOPLIST_REL} en ${infoplist_refs} configuraciones, se esperaban ${EXPECTED_CONFIGS}"
else
  pass "las ${EXPECTED_CONFIGS} configuraciones enganchan ${INFOPLIST_REL}"
fi

# --- 2. Las configuraciones del target del reloj -----------------------------
#
# Se recorre cada bloque XCBuildConfiguration del pbxproj y se filtran los del
# reloj por el marcador de app companion. Cada uno tiene que enganchar el
# entitlement y declarar los dos textos de permiso.

echo
echo "Configuraciones del target del reloj"

configs="$(awk -v marker="${WATCH_MARKER}" '
  /isa = XCBuildConfiguration;/ { inCfg = 1; buf = ""; next }
  inCfg && /^\t\t\};$/ {
    inCfg = 0
    if (buf ~ marker) {
      name = buf
      sub(/.*[\n\t]name = /, "", name)
      sub(/;.*/, "", name)
      print name "\t" \
        (buf ~ /CODE_SIGN_ENTITLEMENTS = /                        ? "1" : "0") "\t" \
        (buf ~ /INFOPLIST_KEY_NSHealthShareUsageDescription = ./   ? "1" : "0") "\t" \
        (buf ~ /INFOPLIST_KEY_NSHealthUpdateUsageDescription = ./  ? "1" : "0")
    }
    next
  }
  inCfg { buf = buf "\n" $0 }
' "${PBXPROJ}" || true)"

# Que el entitlement enganchado sea EL DEL RELOJ y no otro se chequea abajo,
# fuera del awk: la ruta lleva espacios y complica pasarla como variable.
found_configs=0
while IFS=$'\t' read -r name has_entitlements has_share has_update; do
  [[ -z "${name}" ]] && continue
  found_configs=$((found_configs + 1))

  if [[ "${has_entitlements}" != "1" ]]; then
    fail "[${name}] sin CODE_SIGN_ENTITLEMENTS"
  else
    pass "[${name}] engancha un entitlements"
  fi

  if [[ "${has_share}" != "1" ]]; then
    fail "[${name}] sin INFOPLIST_KEY_NSHealthShareUsageDescription (texto de LECTURA)"
  else
    pass "[${name}] declara el texto de lectura"
  fi

  if [[ "${has_update}" != "1" ]]; then
    fail "[${name}] sin INFOPLIST_KEY_NSHealthUpdateUsageDescription (texto de ESCRITURA)"
  else
    pass "[${name}] declara el texto de escritura"
  fi
done <<< "${configs}"

if [[ "${found_configs}" -ne "${EXPECTED_CONFIGS}" ]]; then
  fail "se esperaban ${EXPECTED_CONFIGS} configuraciones del reloj, se encontraron ${found_configs}"
else
  pass "las ${EXPECTED_CONFIGS} configuraciones del reloj estan presentes"
fi

# La ruta del entitlements lleva espacios, asi que se compara aparte del awk.
entitlement_refs="$(grep -c "CODE_SIGN_ENTITLEMENTS = \"${ENTITLEMENTS_REL}\"" \
  "${PBXPROJ}" || true)"
if [[ "${entitlement_refs}" -ne "${EXPECTED_CONFIGS}" ]]; then
  fail "CODE_SIGN_ENTITLEMENTS apunta a ${ENTITLEMENTS_REL} en ${entitlement_refs} configuraciones, se esperaban ${EXPECTED_CONFIGS}"
else
  pass "las ${EXPECTED_CONFIGS} apuntan al entitlements del reloj"
fi

# --- 3. Los textos de permiso los lee un humano ------------------------------
#
# Un texto vacio o de relleno pasa la validacion de Apple pero deja al atleta
# sin saber que le estan pidiendo. Se exige que digan algo.

echo
echo "Textos de permiso"

MIN_TEXT_LEN=25
for key in INFOPLIST_KEY_NSHealthShareUsageDescription \
           INFOPLIST_KEY_NSHealthUpdateUsageDescription; do
  text="$(grep -m1 "${key} = " "${PBXPROJ}" 2>/dev/null \
    | sed -E 's/^[^=]+= *"?//; s/"?;$//' || true)"
  if [[ -z "${text}" ]]; then
    fail "${key}: sin texto"
  elif [[ "${#text}" -lt "${MIN_TEXT_LEN}" ]]; then
    fail "${key}: el texto tiene ${#text} caracteres, muy corto para explicar el pedido"
  else
    pass "${key}: \"${text}\""
  fi
done

# --- Resultado ---------------------------------------------------------------

echo
if [[ "${failures}" -gt 0 ]]; then
  echo "FALLA: ${failures} chequeo(s) de capabilities del reloj" >&2
  echo >&2
  echo "Si esto se puso rojo sin que nadie tocara la config a mano, el" >&2
  echo "sospechoso numero uno es una herramienta que reescribio el pbxproj:" >&2
  echo "`pod install` lo reescribe entero. Mirar el diff de" >&2
  echo "ios/Runner.xcodeproj/ antes de agregar nada de vuelta." >&2
  exit 1
fi

echo "OK: capabilities del reloj intactas"
