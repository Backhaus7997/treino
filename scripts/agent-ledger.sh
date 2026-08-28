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
#   ./scripts/agent-ledger.sh release
#   ./scripts/agent-ledger.sh prune
#
# Variables:
#   AGENT_NAME          fuerza el nombre del agente (si no, se detecta)
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

die() { echo "agent-ledger: $*" >&2; exit 2; }

# La deteccion es best-effort: si tu herramienta no aparece, exporta AGENT_NAME.
detect_agent() {
  if [ -n "${AGENT_NAME:-}" ];        then field "$AGENT_NAME"
  elif [ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]; then echo "claude-code"
  elif [ -n "${CODEX_SANDBOX:-}${CODEX_HOME:-}" ];          then echo "codex"
  elif [ -n "${CURSOR_TRACE_ID:-}" ]; then echo "cursor"
  else echo "unknown"; fi
}

clean() { printf '%s' "$1" | tr '\t\n' '  ' | sed 's/  *$//'; }

# Para los campos de IDENTIDAD (agente, rama, worktree). Dos diferencias con
# clean, y las dos importan:
#
# 1. Nunca devuelve vacio. Un campo vacio no deja un hueco: CORRE todas las
#    columnas siguientes, porque `read` con IFS=tab trata al tab como
#    whitespace y colapsa delimitadores consecutivos. Una fila con el agente
#    vacio se lee con la rama en la columna del agente y `check` pierde el claim.
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

# Los dos son campos del TSV: un \t o un \n adentro forjaria filas enteras. Van
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
  note="$(clean "${*:-}")"
  cmd_check "$scope" || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" "$(detect_agent)" "$(branch)" "$(worktree)" "$scope" "$note" >> "$LEDGER"
  echo "anotado: $scope  [$(detect_agent) · $(branch)]"
}

cmd_release() {
  local scope me tmp
  # Mismo clean que uso claim al escribir, si no `release 826 ` no matchea.
  scope="$(clean "${1:-}")"; me="$(worktree)"
  [ -f "$LEDGER" ] || { echo "ledger vacio"; return 0; }
  # ENVIRON y no `-v`: awk procesa secuencias de escape en las asignaciones de
  # `-v`, asi que un path que contenga los caracteres literales `\t` se compara
  # como si tuviera un tab de verdad y el release no encuentra su propia fila.
  #
  # El temp lleva el PID: con el nombre fijo, dos worktrees liberando a la vez
  # escribian el mismo `.tmp` y se truncaban entre si.
  tmp="$LEDGER.tmp.$$"
  ME="$me" SC="$scope" awk -F"$TAB" \
    'BEGIN { me = ENVIRON["ME"]; sc = ENVIRON["SC"] }
     !($4 == me && (sc == "" || $5 == sc))' "$LEDGER" > "$tmp"
  mv "$tmp" "$LEDGER"
  echo "liberado${scope:+: $scope}"
}

cmd_list() {
  local n=0
  while IFS="$TAB" read -r ts agent br wt scope note; do
    [ -n "${ts:-}" ] || continue
    n=$((n+1))
    printf '  %-14s %-12s %-38s %s%s\n' \
      "$scope" "$agent" "$br" "$(age_label "$ts")" \
      "$(is_stale "$ts" && echo '  ← VIEJO, capaz murio' || true)"
    [ -n "${note:-}" ] && printf '                 %s\n' "$note"
  done <<< "$(rows)"
  [ "$n" -eq 0 ] && echo "  (nadie trabajando en nada)"
  return 0
}

cmd_check() {
  [ $# -ge 1 ] || die "uso: check <scope>"
  # Las seis del `read` van en `local` a proposito: sin eso, el loop pisa las
  # variables del que llama. cmd_claim setea su `note` ANTES de llamar aca, y
  # el read se la borraba — la nota se perdia y el ledger quedaba sin el dato
  # que le dice al proximo agente que estas haciendo.
  local scope me hit=0 ts agent br wt scope2 note
  scope="$(clean "$1")"; me="$(worktree)"
  while IFS="$TAB" read -r ts agent br wt scope2 note; do
    [ -n "${ts:-}" ] || continue
    [ "$scope2" = "$scope" ] || continue
    [ "$wt" = "$me" ] && continue
    hit=1
    echo "⚠  YA HAY ALGUIEN EN '$scope':" >&2
    echo "   $agent · rama $br · $(age_label "$ts")$(is_stale "$ts" && echo ' (viejo)' || true)" >&2
    [ -n "${note:-}" ] && echo "   \"$note\"" >&2
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
  -h|--help|help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "comando desconocido: $1  (claim|release|check|list|prune)" ;;
esac
