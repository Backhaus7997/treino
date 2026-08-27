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
# Y ese segundo grupo es el problema real de #840: al escribir esto son 29
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
# Arreglar los `.firebaserc` no alcanza: `firebase use <alias>` escribe
# `activeProjects` en `~/.config/configstore/firebase-tools.json` (NO versionado)
# y eso le GANA al default. La precedencia real es:
#
#     options.project = --project ?? activeProjects[<dir o ANCESTRO>] ?? .firebaserc default
#
# ⚠️ EL PIN SE HEREDA DE LOS DIRECTORIOS PADRE. Medido contra la firebase-tools
# que está EN EL PATH — **15.19.0** — no contra una caché de npx:
#
#   firebase-tools/lib/command.js:234 `configstoreProject(dir)` arranca en
#   `projectRoot` y sube por `path.dirname()` hasta `/`, devolviendo el PRIMER
#   directorio con pin. O sea: un `firebase use prod` en la raíz del repo —o en
#   `$HOME`— pinea la raíz Y los worktrees de adentro, todos de una.
#
# Esto NO es lo que hacía 13.35.1, que leía `activeProjects[projectRoot]` EXACTO
# (`command.js:196`) y por eso pinear un directorio no tocaba a los hermanos ni a
# los hijos. Una medición contra 13.35.1 da la respuesta tranquilizadora y
# EQUIVOCADA para la CLI que este repo realmente ejecuta.
#
# Por eso el audit de abajo sube por `dirname` igual que la CLI, en vez de
# comparar el path exacto: filtrar por igualdad reportaba "ningún worktree
# pineado" con un pin en un ancestro gobernando a todos. Siempre read-only,
# incluso con `--write`.

WRITE=0
[ "${1:-}" = "--write" ] && WRITE=1

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
found=0
changed=0

# Los directorios de todos los worktrees, para reusarlos en el audit de abajo.
# OJO: `$ROOT` es el toplevel de ESTE worktree, no el del repo principal —
# filtrar los pins por `$ROOT` se perderia todos los demas.
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
import io, json, os, sys

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


def pin_efectivo(d):
    """Mismo algoritmo que `configstoreProject()` de firebase-tools 15.19.0:
    arranca en el directorio y SUBE por dirname hasta `/`, devolviendo el primer
    pin que encuentre. Comparar el path exacto (lo que hacia 13.35.1) reportaria
    "ningun worktree pineado" con un pin en un ancestro gobernandolos a todos."""
    cur = os.path.realpath(d)
    while True:
        if active.get(cur):
            return cur, active[cur]
        parent = os.path.dirname(cur)
        if parent == cur:
            return None, None
        cur = parent


# `prod` y `treino-dev` resuelven los dos a produccion (alias de .firebaserc)
PROD = ('prod', 'treino-dev')
afectados = []
for wt in worktrees:
    origen, proj = pin_efectivo(wt)
    if proj:
        afectados.append((wt, origen, proj))

if not afectados:
    print("activeProjects: %d pin(es) en la maquina, ninguno alcanza a los %d "
          "worktrees de este repo (chequeado subiendo por dirname, igual que la "
          "CLI)." % (len(active), len(worktrees)))
    raise SystemExit(0)

en_prod = [a for a in afectados if a[2] in PROD]
print("activeProjects: %d de %d worktree(s) de este repo estan PINEADOS -- el pin "
      "le gana al default de `.firebaserc`:" % (len(afectados), len(worktrees)))
for wt, origen, proj in sorted(afectados):
    danger = '  <-- PRODUCCION' if proj in PROD else ''
    heredado = '' if os.path.realpath(wt) == origen else '  (heredado de %s)' % origen
    print("  %s  ->  %s%s%s" % (wt, proj, danger, heredado))
if en_prod:
    print("%d de ellos resuelven a PRODUCCION. Corre `firebase use --clear` en el "
          "directorio que tiene el pin (el de la columna 'heredado de', si lo hay)."
          % len(en_prod))
else:
    print("Para soltar uno: `firebase use --clear` dentro del directorio pineado.")
PYEOF
fi
