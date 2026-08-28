#!/usr/bin/env bash
set -euo pipefail

# Falla si el `default` de `.firebaserc` deja de ser un proyecto `demo-`.
#
# `treino-dev` es PRODUCCION (#826). Era el `default` de `.firebaserc`, o sea que
# cualquier `firebase deploy` o `firestore:delete` SIN `--project` iba derecho a
# los datos de usuarios reales. #840 lo movio a `demo-treino`: Firebase trata el
# prefijo `demo-` como proyecto offline del emulador, asi que un comando pelado
# FALLA en vez de resolver a produccion.
#
# Ese fix vive en UN valor de UN archivo versionado. Un merge mal resuelto, un
# `firebase use --add` que reescribe el bloque, o un revert distraido lo deshacen
# sin que nada chille — y el sintoma recien aparece el dia que alguien corre algo
# destructivo. Este check es el gate que convierte ese silencio en un CI rojo.
#
#   bash scripts/check_firebaserc_default.sh
#
# Nota: esto cubre la mitad VERSIONADA del problema. La otra mitad —el pin de
# `firebase use` en `~/.config/configstore/firebase-tools.json`, que le gana al
# default y se hereda de los directorios padre— vive fuera del repo y CI no la
# ve. Para esa hay `scripts/sync_firebaserc_worktrees.sh`.

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
exec python3 - "${ROOT}/.firebaserc" <<'PY'
import io, json, sys

path = sys.argv[1]
try:
    data = json.loads(io.open(path, encoding='utf-8').read())
except Exception as err:
    print("FAIL: no se pudo parsear %s (%s)" % (path, err))
    raise SystemExit(1)

projects = data.get('projects') or {}
default = projects.get('default')

if not default:
    print("FAIL: %s no declara `projects.default`.\n"
          "      Sin default, la CLI cae en el unico alias si hay uno solo — y hoy\n"
          "      `prod` apunta a treino-dev (PRODUCCION). Poné un `demo-*`."
          % path)
    raise SystemExit(1)

if not default.startswith('demo-'):
    print("FAIL: el `default` de %s es `%s`, que NO empieza con `demo-`.\n"
          "      Firebase solo trata como offline los ids con prefijo `demo-`; con\n"
          "      cualquier otro, un `firebase deploy` o un `firestore:delete` SIN\n"
          "      `--project` resuelve a un proyecto REAL. Ver #840 y AGENTS.md.\n"
          "      Para tocar produccion se escribe `--project prod`, no se cambia\n"
          "      el default." % (path, default))
    raise SystemExit(1)

print("OK: el `default` de .firebaserc es `%s` (offline). Un comando sin "
      "`--project` no llega a produccion." % default)
PY
