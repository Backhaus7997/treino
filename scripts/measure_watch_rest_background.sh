#!/usr/bin/env bash
#
# scripts/measure_watch_rest_background.sh
#
# Mide cuantos segundos de descanso PIERDE el reloj mientras la app esta en
# segundo plano. Es la medicion que justifica el change `watch-workout-session`:
# sin sesion de entrenamiento, watchOS suspende la app al bajar la muñeca —que
# en el gimnasio es el caso NORMAL— y el `Timer` del descanso deja de correr.
#
#   bash scripts/measure_watch_rest_background.sh t0     <watch-udid>
#   (apretar la Digital Crown para mandar la app al fondo)
#   bash scripts/measure_watch_rest_background.sh t1     <watch-udid> [segundos]
#
# PRECONDICION: tiene que haber un descanso YA CORRIENDO en el reloj, o sea una
# serie recien marcada. El script no la marca: automatizar el toque agrega una
# fuente de error, no la saca.
#
# POR QUE VA EN DOS PASOS
#   Mandar la app al fondo tiene que ser la DIGITAL CROWN, que es lo que hace el
#   atleta al bajar la muñeca. `simctl terminate` NO sirve: mata el proceso, que
#   es un escenario distinto —y mas benigno, porque al relanzar se restaura
#   desde disco—. Como simctl no expone la corona, el paso del medio se hace
#   afuera y el script solo ancla los tiempos.
#
# COMO SE LEE EL RESULTADO
#   perdido = (segundos reales) - (banner_t0 - banner_t1)
#
#   El control que convierte esto en prueba y no en indicio: si al volver el
#   banner SIGUE PRESENTE, la app no se reinicio. `restRemaining` no se
#   persiste, asi que un relanzamiento lo dejaria en nil y sin banner. Banner
#   presente + numero que no bajo lo suficiente = suspension, no reinicio.

set -euo pipefail

MODO="${1:?Falta el modo: t0 o t1}"
WATCH="${2:?Falta el UDID del reloj}"
BUNDLE="com.backhaus.treino.watchkitapp"
ESTADO="/tmp/medicion-descanso-${WATCH}"

case "${MODO}" in

  t0)
    mkdir -p "${ESTADO}"
    xcrun simctl io "${WATCH}" screenshot "${ESTADO}/t0.png" >/dev/null 2>&1
    date +%s > "${ESTADO}/t0.epoch"
    echo "T0 anclado: $(cat "${ESTADO}/t0.epoch")"
    echo "captura:    ${ESTADO}/t0.png"
    echo
    echo "AHORA: apreta la Digital Crown (boton HOME) para mandar la app al fondo,"
    echo "y despues corre el paso t1."
    ;;

  t1)
    ESPERA="${3:-45}"
    [[ -f "${ESTADO}/t0.epoch" ]] || { echo "ERROR: no hay t0 anclado" >&2; exit 1; }

    echo "Esperando ${ESPERA}s reales con la app en el fondo..."
    sleep "${ESPERA}"

    # Traerla al frente. Sin espera artificial despues: cuanto mas tarde la
    # captura, mas descanso corre en PRIMER PLANO y menos se nota lo que se
    # perdio en el fondo.
    xcrun simctl launch "${WATCH}" "${BUNDLE}" >/dev/null 2>&1 || true
    xcrun simctl io "${WATCH}" screenshot "${ESTADO}/t1.png" >/dev/null 2>&1
    date +%s > "${ESTADO}/t1.epoch"

    T0=$(cat "${ESTADO}/t0.epoch")
    T1=$(cat "${ESTADO}/t1.epoch")

    echo
    echo "SEGUNDOS REALES T0->T1: $((T1 - T0))"
    echo
    echo "Leer los dos banners y restar:"
    echo "  perdido = $((T1 - T0)) - (banner_t0 - banner_t1)"
    echo
    echo "  ${ESTADO}/t0.png"
    echo "  ${ESTADO}/t1.png"
    ;;

  *)
    echo "ERROR: modo desconocido '${MODO}'. Usar t0 o t1." >&2
    exit 1
    ;;
esac
