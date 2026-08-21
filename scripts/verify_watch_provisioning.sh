#!/usr/bin/env bash
#
# scripts/verify_watch_provisioning.sh
#
# Verifica que el reloj tenga un provisioning profile con HealthKit, que es lo
# unico que falta para poder probarlo en un Apple Watch real.
#
#   bash scripts/verify_watch_provisioning.sh
#
# POR QUE HACE FALTA UN CHEQUEO APARTE
#
# `scripts/test_watch_capabilities.sh` cubre lo que vive en el REPO: el
# entitlement, el background mode y los textos de permiso. Esto vive en la
# CUENTA DE APPLE, que ningun test del repo alcanza.
#
# Y el modo de falla es el peor que hay: sin el entitlement en el perfil de
# dispositivo, la app compila, se instala y arranca igual — HealthKit
# simplemente niega todo EN SILENCIO en la muñeca del atleta. Ni crash ni error:
# no hay pulsaciones y el entreno no llega a Salud.
#
# Es local por maquina: mide los perfiles que tiene ESTA Mac, no lo que hay en
# el portal. Corre despues de que Xcode regenere.

set -euo pipefail

BUNDLE_ID="com.backhaus.treino.watchkitapp"
CAPABILITY="com.apple.developer.healthkit"
PROFILES_DIR="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"

echo "Buscando un perfil para ${BUNDLE_ID}"
echo

if [[ ! -d "${PROFILES_DIR}" ]]; then
  echo "  ✗ no existe ${PROFILES_DIR}" >&2
  echo >&2
  echo "Xcode todavia no genero ningun perfil en esta maquina." >&2
  exit 1
fi

encontrados=0
con_healthkit=0

shopt -s nullglob
for profile in "${PROFILES_DIR}"/*.mobileprovision; do
  plist="$(security cms -D -i "${profile}" 2>/dev/null || true)"
  [[ -z "${plist}" ]] && continue

  app_id="$(printf '%s' "${plist}" \
    | plutil -extract 'Entitlements.application-identifier' raw -o - - 2>/dev/null || true)"

  # El application-identifier viene con el Team ID adelante: J66AQRRM96.com.foo
  case "${app_id}" in
    *".${BUNDLE_ID}") ;;
    *) continue ;;
  esac

  encontrados=$((encontrados + 1))
  name="$(printf '%s' "${plist}" | plutil -extract Name raw -o - - 2>/dev/null || echo '?')"
  expira="$(printf '%s' "${plist}" | plutil -extract ExpirationDate raw -o - - 2>/dev/null || echo '?')"

  # Los puntos van escapados: plutil los toma como separador de keypath.
  hk="$(printf '%s' "${plist}" \
    | plutil -extract "Entitlements.${CAPABILITY//./\\.}" raw -o - - 2>/dev/null || echo 'AUSENTE')"

  echo "  perfil: ${name}"
  echo "    app id: ${app_id}"
  echo "    vence:  ${expira}"

  if [[ "${hk}" == "true" || "${hk}" == "1" ]]; then
    echo "    ✓ declara ${CAPABILITY}"
    con_healthkit=$((con_healthkit + 1))
  else
    echo "    ✗ NO declara ${CAPABILITY} (esta: ${hk})"
  fi
  echo
done

if [[ "${encontrados}" -eq 0 ]]; then
  echo "  ✗ no hay NINGUN perfil que cubra ${BUNDLE_ID}" >&2
  echo >&2
  echo "El companion nunca se firmo para un dispositivo real. Seguir el paso a" >&2
  echo "paso de docs/setup/watchos-target.md — hay que crear el App ID en el" >&2
  echo "portal antes de que Xcode pueda generar el perfil." >&2
  exit 1
fi

if [[ "${con_healthkit}" -eq 0 ]]; then
  echo "  ✗ hay ${encontrados} perfil(es) para el reloj, pero NINGUNO con HealthKit" >&2
  echo >&2
  echo "Falta tildar HealthKit en el App ID del portal y dejar que Xcode" >&2
  echo "regenere. Detalle en docs/setup/watchos-target.md." >&2
  exit 1
fi

echo "OK: hay ${con_healthkit} perfil(es) del reloj con HealthKit."
echo "El reloj se puede firmar para un dispositivo real."
