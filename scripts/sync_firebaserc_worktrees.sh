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
#
# ── TAMBIÉN AUDITA `activeProjects` ──────────────────────────────────────────
# Arreglar los 28 `.firebaserc` no alcanza: `firebase use <alias>` escribe
# `activeProjects` en `~/.config/configstore/firebase-tools.json` (NO versionado)
# y eso le GANA al default. La precedencia real, en
# `firebase-tools/lib/command.js:196` (`applyRC`):
#
#     options.project = --project ?? activeProjects[projectRoot] ?? .firebaserc default
#
# Medido contra firebase-tools 13.35.1 con este mismo `.firebaserc`: sin la clave
# resuelve `demo-treino`; con `activeProjects[dir] = "prod"` resuelve
# `treino-dev`, o sea PRODUCCIÓN. Es por directorio (`projectRoot`), así que
# pinea un worktree y no los otros. Como no deja rastro en el repo, la única
# forma de saberlo es mirar el configstore — que es lo que hace la segunda
# sección de este script, siempre read-only, incluso con `--write`.

WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
found=0
changed=0

# Los directorios de los 29 worktrees, para reusarlos en el audit de abajo.
# OJO: `$ROOT` es el toplevel de ESTE worktree, no el del repo principal —
# filtrar los pins por `$ROOT` se perderia los otros 27.
WT_LIST="$(mktemp)"
trap 'rm -f "$WT_LIST"' EXIT
# Sacar el prefijo `worktree ` en vez de `awk '{print $2}'`: awk corta en el
# primer espacio y un path con espacios quedaria truncado, el `.firebaserc` no
# existiria, y el worktree se saltearia EN SILENCIO — o sea, reportando "todo
# seguro" con uno todavia apuntando a produccion.
while IFS= read -r line; do
  case "$line" in
    "worktree "*) printf '%s\n' "${line#worktree }" ;;
  esac
done < <(git -C "$ROOT" worktree list --porcelain) > "$WT_LIST"

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
done < "$WT_LIST"

if [ "$found" = "0" ]; then
  echo "Todos los worktrees ya tienen el default seguro (demo-treino)."
elif [ "$WRITE" = "1" ]; then
  echo "Listo: ${changed} worktree(s) actualizados. Quedan como cambio SIN commitear en cada uno."
else
  echo "${found} worktree(s) con el default de PRODUCCION. Corre con --write para arreglarlos."
fi

# -- `activeProjects`: lo que le gana al default (ver cabecera) ----------------
# READ-ONLY siempre. Nunca escribe el configstore: sacar un pin ajeno es una
# decision de la persona que lo puso, no de este script.
echo
CONFIGSTORE="${XDG_CONFIG_HOME:-${HOME}/.config}/configstore/firebase-tools.json"
if [ ! -f "$CONFIGSTORE" ]; then
  echo "activeProjects: sin configstore (${CONFIGSTORE}). Nada que pueda pisar el default."
else
  python3 - "$CONFIGSTORE" "$WT_LIST" <<'PYEOF'
import io, json, sys

path, wt_list = sys.argv[1], sys.argv[2]
worktrees = [l.strip() for l in io.open(wt_list, encoding='utf-8') if l.strip()]
try:
    data = json.loads(io.open(path, encoding='utf-8').read())
except Exception as err:  # configstore corrupto o ilegible: decilo, no lo tapes
    print("activeProjects: no se pudo leer %s (%s)." % (path, err))
    raise SystemExit(0)

active = data.get('activeProjects') or {}
if not active:
    print("activeProjects: la clave no existe. Ningun directorio esta pineado; "
          "manda el default de `.firebaserc`.")
    raise SystemExit(0)

mine = {d: p for d, p in active.items() if d in worktrees}
if not mine:
    print("activeProjects: %d pin(es) en la maquina, ninguno en los %d worktrees "
          "de este repo." % (len(active), len(worktrees)))
    raise SystemExit(0)

print("activeProjects: %d directorio(s) de este repo PINEADOS -- le ganan al "
      "default de `.firebaserc`:" % len(mine))
for d, proj in sorted(mine.items()):
    # `prod` y `treino-dev` resuelven los dos a produccion (alias de .firebaserc)
    danger = '  <-- PRODUCCION' if proj in ('prod', 'treino-dev') else ''
    print("  %s  ->  %s%s" % (d, proj, danger))
print("Para soltar uno: `firebase use --clear` dentro de ese directorio.")
PYEOF
fi
