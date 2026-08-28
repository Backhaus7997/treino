#!/usr/bin/env bash
set -euo pipefail
#
# agent-ledger.sh — quién está trabajando en qué, compartido entre worktrees.
#
# El problema: este repo corre con varias herramientas (Claude Code, Codex,
# Cursor…) y muchos worktrees en paralelo. Un archivo commiteado NO sirve como
# estado compartido: cada worktree tiene su propia copia en su propia rama.
#
# La solución: guardar el ledger en el git common dir (`.git/`), que es el único
# directorio que TODOS los worktrees comparten y que nunca se commitea.
#
#   ./scripts/agent-ledger.sh claim 826 "banner de entornos en docs"
#   ./scripts/agent-ledger.sh check 826
#   ./scripts/agent-ledger.sh list
#   ./scripts/agent-ledger.sh release          # sólo los claims de ESTA sesión
#   ./scripts/agent-ledger.sh release 826      # ese scope, sea de quien sea
#   ./scripts/agent-ledger.sh release --all    # todo lo de este worktree
#   ./scripts/agent-ledger.sh prune
#
# La identidad de un agente es la SESIÓN, no el worktree. Varias sesiones de la
# misma herramienta comparten árbol, y con el worktree como identidad `release`
# sin scope se llevaba los claims de las otras y `check` contestaba "libre"
# sobre un scope que ya tenía dueño.
#
# Variables:
#   AGENT_NAME          fuerza el nombre del agente (si no, se detecta)
#   AGENT_SESSION       fuerza el id de sesión (si no, se detecta; ver session())
#                       hace falta en toda herramienta que no publique un id propio
#   LEDGER_STALE_HOURS  horas tras las cuales una entrada se marca vieja (default 8)

STALE_HOURS="${LEDGER_STALE_HOURS:-8}"
# Termina en contexto aritmetico en cmd_prune, y ahi va SIN `$` — bash evalua el
# contenido de la variable de forma recursiva. Si no es un entero, ignoralo.
#
# El `10#` no es decorativo: "08" pasa el case pero revienta la aritmetica con
# "value too great for base", porque el cero inicial la vuelve octal y 8 no es
# un digito octal. Normalizar aca y no en cada uso.
case "$STALE_HOURS" in ''|*[!0-9]*) STALE_HOURS=8 ;; esac
STALE_HOURS=$(( 10#$STALE_HOURS ))

LEDGER="$(git rev-parse --git-common-dir)/agent-ledger.tsv"
TAB="$(printf '\t')"

# INVARIANTE DEL FORMATO: ningun campo puede quedar vacio, salvo el ultimo.
#
# No es estetica. `read` con IFS=tab trata al tab como whitespace y COLAPSA
# delimitadores consecutivos, asi que un campo vacio no deja un hueco: corre
# todas las columnas siguientes.
#
#   printf 'A\tB\tC\t\tE\n' | IFS=$'\t' read -r a b c d e   ->  d=E  e=
#
# Por eso `field` nunca devuelve vacio y por eso la nota, que si puede venir
# vacia del usuario, se escribe como '?' desde que dejo de ser la ultima
# columna. Antes zafaba por posicion: al agregar la sesion detras, una nota
# vacia hacia que la sesion se leyera como nota y `check` perdia el campo con
# el que decide de quien es la fila.
#
# Si algun dia agregas otra columna: va DESPUES de la sesion, y el campo que
# queda en el medio tiene que dejar de poder estar vacio.
#
# (awk con -F tab no colapsa — solo el FS por defecto lo hace — por eso
# release y prune leen el archivo directo.)

die() { echo "agent-ledger: $*" >&2; exit 2; }

# La deteccion es best-effort: si tu herramienta no aparece, exporta AGENT_NAME.
detect_agent() {
  if [ -n "${AGENT_NAME:-}" ];        then field "$AGENT_NAME"
  elif [ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then echo "claude-code"
  elif [ -n "${CODEX_SANDBOX:-}${CODEX_HOME:-}" ];          then echo "codex"
  elif [ -n "${CURSOR_TRACE_ID:-}" ]; then echo "cursor"
  else echo "unknown"; fi
}

# Que sesion es esta. Best-effort igual que detect_agent, y con la misma salida
# si no se puede: exporta AGENT_SESSION.
#
# `$PPID` NO sirve y no es una omision: adentro de este script el padre es el
# shell efimero que lo invoco, uno distinto en cada llamada. Lo que hace falta
# es un id que sobreviva a toda la sesion del agente.
#
# Que devuelva '?' no es un bug, es el peor caso honesto: dos sesiones de una
# herramienta que no publica id vuelven a ser indistinguibles entre si — igual
# que antes de este cambio, ni mejor ni peor. AGENT_SESSION lo arregla.
#
# CODEX_THREAD_ID sale de la review de Codex sobre el PR que trajo esta funcion:
# lo publica el, es estable, y sin el dos sesiones de Codex en el mismo arbol
# seguian escribiendo '?' las dos — el agujero que este script cierra, abierto
# justo para la herramienta que detect_agent ya sabe reconocer por CODEX_HOME.
#
# CURSOR_TRACE_ID NO esta en esta lista aunque detect_agent lo use. Ahi solo
# hace falta que exista para saber que es Cursor; aca hace falta que sea el
# MISMO valor en cada invocacion de la sesion. Un "trace id" que cambie por
# request seria peor que '?': cada llamada pareceria otra sesion, `release` no
# encontraria sus propias filas y `check` avisaria sobre tus propios claims.
# Hasta poder verificar cual de las dos cosas es, se queda afuera.
#
# El PID va ultimo a proposito: el SO los reusa, asi que es el mas debil de los
# identificadores reales.
session() {
  if   [ -n "${AGENT_SESSION:-}" ];          then field "$AGENT_SESSION"
  elif [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then field "$CLAUDE_CODE_SESSION_ID"
  elif [ -n "${CODEX_THREAD_ID:-}" ];        then field "$CODEX_THREAD_ID"
  elif [ -n "${CLAUDE_PID:-}" ];             then field "claude-pid-$CLAUDE_PID"
  else echo '?'; fi
}

clean() { printf '%s' "$1" | tr '\t\n' '  ' | sed 's/  *$//'; }

# Para los campos de IDENTIDAD (agente, sesion, rama, worktree). Dos diferencias
# con clean, y las dos importan:
#
# 1. Nunca devuelve vacio. Un campo vacio no deja un hueco: CORRE todas las
#    columnas siguientes (ver INVARIANTE DEL FORMATO). Una fila con el agente
#    vacio se lee con la rama en la columna del agente y `check` pierde el
#    claim. Ademas, para la sesion, el vacio ya significa otra cosa: "fila
#    escrita por la version de este script que no tenia columna de sesion".
#
# 2. NO recorta los espacios finales, que es lo unico que hace clean de mas.
#    El path del worktree es una identidad, no un texto para mostrar: si se
#    normaliza, `/tmp/wt` y `/tmp/wt ` colapsan en el mismo valor y `check`
#    contesta "libre" a un worktree distinto del que tiene el claim. Dos
#    agentes en el mismo scope es exactamente lo que este script existe para
#    evitar. El tab y el newline SI hay que neutralizarlos: rompen el TSV.
field() {
  local v; v="$(printf '%s' "${1:-}" | tr '\t\n' '  ')"
  case "$v" in *[![:space:]]*) printf '%s' "$v" ;; *) printf '?' ;; esac
}

# Sin lock a proposito. Un append de una linea corta es atomico en POSIX, y un
# lock trabado bloquearia a los 27 worktrees a la vez — peor que perder una
# entrada cada tanto. release/prune reescriben con temp + mv (atomico).

# Los tres son campos del TSV: un \t o un \n adentro forjaria filas enteras. Van
# por field aca y no en el call site, asi el valor que se escribe y el que se
# compara en release/check son el mismo.
branch()   { field "$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"; }
worktree() { field "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; }

rows() { [ -f "$LEDGER" ] && cat "$LEDGER" || true; }

# El ts sale del archivo y entra a contexto aritmetico. Bash resuelve command
# substitution dentro de subindices de array en $(( )), asi que una fila con
# `x[$(cmd)]` en el campo 1 ejecutaria cmd. Validar ANTES de la aritmetica.
is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

age_label() {
  is_num "${1:-}" || { echo "fecha invalida"; return 0; }
  local secs=$(( $(date +%s) - 10#$1 )) h
  h=$(( secs / 3600 ))
  if   [ "$h" -ge 24 ]; then echo "hace $(( h / 24 ))d"
  elif [ "$h" -ge 1 ];  then echo "hace ${h}h"
  else echo "hace $(( secs / 60 ))m"; fi
}

# Una fila con ts corrupto se trata como vieja: se marca en list y prune la come.
is_stale() {
  is_num "${1:-}" || return 0
  [ $(( ( $(date +%s) - 10#$1 ) / 3600 )) -ge "$STALE_HOURS" ]
}

cmd_claim() {
  [ $# -ge 1 ] || die "uso: claim <scope> [nota]   (scope = numero de issue o slug corto)"
  local scope note; scope="$(clean "$1")"; shift
  # Un scope vacio corre las columnas del TSV igual que cualquier otro campo
  # vacio (ver `field`), y ademas hace un claim que nadie puede buscar.
  [ -n "$scope" ] || die "el scope no puede quedar vacio"
  # Ver INVARIANTE DEL FORMATO: la nota dejo de ser la ultima columna, asi
  # que vacia corre la sesion una posicion. El '?' es el mismo convenio
  # que usa `field` para los campos de identidad.
  note="$(clean "${*:-}")"; [ -n "$note" ] || note='?'
  cmd_check "$scope" || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$(detect_agent)" "$(branch)" "$(worktree)" "$scope" "$note" "$(session)" >> "$LEDGER"
  echo "anotado: $scope  [$(detect_agent) · $(branch)]"
}

cmd_release() {
  local scope all=0 me sess tmp
  case "${1:-}" in
    --all) all=1; scope="" ;;
    # Mismo clean que uso claim al escribir, si no `release 826 ` no matchea.
    *)     scope="$(clean "${1:-}")" ;;
  esac
  me="$(worktree)"; sess="$(session)"
  [ -f "$LEDGER" ] || { echo "ledger vacio"; return 0; }

  # Que se lleva cada forma, y por que:
  #
  #   release          las filas de ESTE worktree Y ESTA sesion. El worktree
  #                    solo no alcanza: paso el 2026-08-28 que tres claims
  #                    compartian `wt` y un release sin scope se llevo los tres.
  #   release <scope>  ese scope en este worktree, sea de la sesion que sea. Es
  #                    un acto explicito que nombra su objetivo — y es la unica
  #                    salida manual para limpiar el claim de un agente muerto.
  #                    Si la fila no era tuya, se avisa.
  #   release --all    todo lo de este worktree. El barrido de antes, ahora hay
  #                    que pedirlo.
  #
  # Una fila con la sesion VACIA (no '?') la escribio la version anterior de
  # este script y no se puede atribuir. El release pelado NO se la lleva: no
  # borrar lo que no podes probar que es tuyo. Muere igual por prune, o a mano
  # con `release <scope>`.
  #
  # ENVIRON y no `-v`: awk procesa secuencias de escape en las asignaciones de
  # `-v`, asi que un path que contenga los caracteres literales `\t` se compara
  # como si tuviera un tab de verdad y el release no encuentra su propia fila.
  #
  # El temp lleva el PID: con el nombre fijo, dos worktrees liberando a la vez
  # escribian el mismo `.tmp` y se truncaban entre si.
  tmp="$LEDGER.tmp.$$"
  ME="$me" SS="$sess" SC="$scope" ALL="$all" OUT="$tmp" awk -F"$TAB" '
    BEGIN {
      me  = ENVIRON["ME"]; ss = ENVIRON["SS"]; sc = ENVIRON["SC"]
      all = (ENVIRON["ALL"] == "1"); out = ENVIRON["OUT"]
      # Crea el temp aunque no sobreviva ninguna fila, si no el mv revienta.
      printf "" > out
    }
    {
      mine = ($4 == me)
      if      (!mine)     keep = 1
      else if (sc != "")  keep = ($5 != sc)
      else if (all)       keep = 0
      else                keep = ($7 != ss)

      if (keep) {
        print > out
        if (mine && sc == "" && !all) kept[++nk] = $5 "  (" $2 " · " $3 ")"
      } else {
        ngone++
        # Solo cuenta como ajena si se puede PROBAR que lo es. La fila sin
        # sesion (version vieja del script) puede ser tuya: avisar ahi seria
        # una advertencia falsa, que es peor que ninguna (AGENTS.md 11.1).
        if ($7 != ss && $7 != "") stolen[++ns] = $5
      }
    }
    END {
      if      (sc != "") printf "liberado: %s\n", sc
      else if (all)      printf "liberado: %d claim(s) de este worktree\n", ngone+0
      else               printf "liberado: %d claim(s) de esta sesion\n", ngone+0

      if (ns > 0) {
        if (sc != "") printf "ojo: '\''%s'\'' no era de esta sesion.\n", stolen[1]
        else          printf "ojo: %d de esos claims no eran de esta sesion.\n", ns
      }
      if (nk > 0) {
        printf "quedan %d claim(s) en este worktree que esta sesion no reclama:\n", nk
        for (i = 1; i <= nk; i++) printf "   %s\n", kept[i]
        printf "   → son de otra sesion (o previos a la columna de sesion).\n"
        printf "     Para barrerlos igual: release --all\n"
      }
    }
  ' "$LEDGER"
  mv "$tmp" "$LEDGER"
}

cmd_list() {
  local n=0 me sess ts agent br wt scope note sess2
  me="$(worktree)"; sess="$(session)"
  while IFS="$TAB" read -r ts agent br wt scope note sess2; do
    [ -n "${ts:-}" ] || continue
    n=$((n+1))
    # Marcar las propias no es cosmetico: son exactamente las que se lleva un
    # `release` sin scope, asi que se ve antes de correrlo.
    printf '  %-14s %-12s %-38s %s%s%s\n' \
      "$scope" "$agent" "$br" "$(age_label "$ts")" \
      "$([ "$wt" = "$me" ] && [ "$sess2" = "$sess" ] && echo '  ← esta sesion' || true)" \
      "$(is_stale "$ts" && echo '  ← VIEJO, capaz murio' || true)"
    [ -n "${note:-}" ] && [ "$note" != '?' ] && printf '                 %s\n' "$note"
  done <<< "$(rows)"
  [ "$n" -eq 0 ] && echo "  (nadie trabajando en nada)"
  return 0
}

cmd_check() {
  [ $# -ge 1 ] || die "uso: check <scope>"
  # Las siete del `read` van en `local` a proposito: sin eso, el loop pisa las
  # variables del que llama. cmd_claim setea su `note` ANTES de llamar aca, y
  # el read se la borraba — la nota se perdia y el ledger quedaba sin el dato
  # que le dice al proximo agente que estas haciendo.
  local scope me sess hit=0 ts agent br wt scope2 note sess2
  scope="$(clean "$1")"; me="$(worktree)"; sess="$(session)"
  while IFS="$TAB" read -r ts agent br wt scope2 note sess2; do
    [ -n "${ts:-}" ] || continue
    [ "$scope2" = "$scope" ] || continue
    # Propia = mismo worktree Y misma sesion. Con el worktree solo, dos
    # sesiones en el mismo arbol se salteaban entre si y `check` contestaba
    # "libre: 862" con exit 0 sobre un scope que ya tenia dueño: la
    # advertencia falsa de la regla 11.1, con el signo mas caro posible.
    #
    # La sesion vacia es la fila que escribio la version anterior del script.
    # Puede ser tuya, no hay como saberlo — callarse es el lado conservador de
    # 11.1, y prune se las come en ${STALE_HOURS}h. Ojo con la diferencia:
    # vacia es "sin columna", '?' es "columna presente, sesion desconocida".
    # Si la fila dice '?' y esta sesion SI tiene id, la fila no puede ser
    # propia — avisar ahi no es un falso positivo, es una certeza.
    if [ "$wt" = "$me" ] && { [ "$sess2" = "$sess" ] || [ -z "$sess2" ]; }; then
      continue
    fi
    hit=1
    echo "⚠  YA HAY ALGUIEN EN '$scope':" >&2
    echo "   $agent · rama $br · $(age_label "$ts")$(is_stale "$ts" && echo ' (viejo)' || true)" >&2
    [ "$wt" = "$me" ] && echo "   ↑ otra sesion en ESTE MISMO worktree" >&2
    [ -n "${note:-}" ] && [ "$note" != '?' ] && echo "   \"$note\"" >&2
  done <<< "$(rows)"
  if [ "$hit" = 1 ]; then
    echo "   → FRENA y confirma con el usuario antes de seguir (AGENTS.md regla 10)." >&2
    return 1
  fi
  echo "libre: $scope"
}

cmd_prune() {
  [ -f "$LEDGER" ] || { echo "ledger vacio"; return 0; }
  local cutoff tmp
  cutoff=$(( $(date +%s) - STALE_HOURS * 3600 ))
  tmp="$LEDGER.tmp.$$"
  # El regex + `$1+0` fuerzan comparacion numerica. Sin eso awk compara strings
  # cuando el campo no es un numero, y una fila con ts corrupto no muere nunca.
  # `cutoff` si va por `-v`: es un entero, no tiene escapes que interpretar.
  awk -F"$TAB" -v cutoff="$cutoff" \
    '$1 ~ /^[0-9]+$/ && $1+0 >= cutoff' "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
  echo "limpiadas las entradas de mas de ${STALE_HOURS}h"
}

case "${1:-list}" in
  claim)   shift; cmd_claim "$@" ;;
  release) shift; cmd_release "${1:-}" ;;
  check)   shift; cmd_check "$@" ;;
  prune)   cmd_prune ;;
  list|"") cmd_list ;;
  -h|--help|help) sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "comando desconocido: $1  (claim|release|check|list|prune)" ;;
esac
