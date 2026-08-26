#!/usr/bin/env bash
set -euo pipefail

# Pone el default seguro de `.firebaserc` (`demo-treino`) en los worktrees que
# todavía tienen el viejo (`treino-dev`, o sea PRODUCCIÓN).  Ver #840.
#
# ── POR QUÉ EXISTE ESTE SCRIPT ───────────────────────────────────────────────
# `.firebaserc` está VERSIONADO, y el `.firebaserc` de cada worktree es un
# checkout limpio del branch de ese worktree (verificado: `git status --short
# .firebaserc` sale vacío en todos). O sea:
#
#   - Todo worktree que se cree DESPUÉS de que #840 esté en main hereda el
#     default seguro solo. No hay nada que hacer, no hay nada que "regenerar".
#   - Todo worktree que YA existe está parado en un branch que forkeó ANTES,
#     así que sigue con `default: treino-dev` hasta que rebasee o mergee main.
#
# Y ese segundo grupo es el problema real de #840: al escribir esto son 26
# directorios vivos, cada uno con un agente autónomo adentro, donde un `deploy`
# o un `firestore:delete` sin `--project` todavía apunta a datos de usuarios
# reales. Esperar a que cada uno rebasee no es una mitigación, es una ilusión.
#
# ── POR QUÉ NO SE CORRE SOLO ─────────────────────────────────────────────────
# Deja el archivo MODIFICADO SIN COMMITEAR en el worktree ajeno, y hay un agente
# trabajando adentro: puede metérselo de prenda en un PR que no tiene nada que
# ver, o pisarlo con un `git checkout --`. El daño de que se lo lleve puesto es
# nulo (el contenido es exactamente el que main ya tiene), pero la sorpresa no,
# así que lo corre un humano cuando quiere, no un agente por su cuenta.
#
#   bash scripts/sync_firebaserc_worktrees.sh          # dry-run, sólo lista
#   bash scripts/sync_firebaserc_worktrees.sh --write  # aplica
#
# Es idempotente y sólo toca archivos que todavía dicen `treino-dev`.

WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
found=0
changed=0

while IFS= read -r wt; do
  f="${wt}/.firebaserc"
  [ -f "$f" ] || continue
  grep -q '"default": "treino-dev"' "$f" || continue
  found=$((found + 1))
  if [ "$WRITE" = "1" ]; then
    python3 - "$f" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
io.open(p, 'w', encoding='utf-8').write(
    s.replace('"default": "treino-dev"', '"default": "demo-treino"')
)
PY
    changed=$((changed + 1))
    echo "  actualizado  ${f}"
  else
    echo "  pendiente    ${f}"
  fi
done < <(git -C "$ROOT" worktree list --porcelain | awk '/^worktree /{print $2}')

if [ "$found" = "0" ]; then
  echo "Todos los worktrees ya tienen el default seguro (demo-treino)."
elif [ "$WRITE" = "1" ]; then
  echo "Listo: ${changed} worktree(s) actualizados. Quedan como cambio SIN commitear en cada uno."
else
  echo "${found} worktree(s) con el default de PRODUCCIÓN. Corré con --write para arreglarlos."
fi
