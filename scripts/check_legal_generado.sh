#!/usr/bin/env bash
set -euo pipefail

# Falla si un cambio edita un documento legal PUBLICADO mientras
# `legal_content.dart` sigue siendo el texto escrito a mano.
#
#   bash scripts/check_legal_generado.sh [<sha base>]
#
# Los textos legales de la app se GENERAN desde `docs/legal/*.md` con
# `scripts/build_legal_content.py`. El gate que ya existia —el paso "Gate de
# desfasaje legal" del job `test`— compara markdown contra Dart con `--check`, y
# arranca con esta condicion:
#
#     head -1 lib/.../legal_content.dart | grep -q "GENERADO POR"
#
# La primera linea de ese archivo dice hoy `/// Contenido de los documentos
# legales de TREINO (Terminos y Condiciones +`, porque el generador NUNCA
# corrio: aborta a proposito mientras queden marcadores `[[PENDIENTE]]`, y
# quedan. El `grep` no matchea, el bloque no entra, el job pasa en verde.
#
# O sea: alguien edita un markdown de `docs/legal/`, no regenera nada, y CI lo
# aprueba. El gate esta en el repo y no se dispara NUNCA. Por AGENTS.md 11.1 una
# advertencia falsa es peor que ninguna, y un gate que siempre pasa es el caso
# extremo de eso: el `else` imprime "gate omitido" y quien lo lee entiende
# "cubierto".
#
# Este check cubre esa ventana —la que va desde hoy hasta la primera corrida
# real del generador— y no la puede cubrir el `--check`: comparar exige
# `dart format` (si no, compara salida sin formatear contra archivo formateado y
# grita SIEMPRE), o sea el toolchain entero. Esto, en cambio, solo necesita git
# y python3.
#
# La lista de documentos publicados NO se copia aca: sale de `ORDER`, en el
# propio generador. `docs/legal/` tiene 14 archivos y solo 9 se publican — los
# otros cinco (README, ESTADO, BRIEFING, AUDITORIA, spec-web-legal) son notas
# internas, y un gate que se pone rojo por editar un README entrena a ignorarlo.
# Dos copias de la misma lista en dos lenguajes es, ademas, el bug que este repo
# ya cometio tres veces (Block.toJson, feedbackCounts #1160, Post.reactionCounts
# — este ultimo rompio la publicacion de posts SIETE SEMANAS con la suite en
# verde).

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
cd "$ROOT"

DART="lib/features/auth/presentation/legal/legal_content.dart"

# Contra que se compara. En un PR, CI pasa `base.sha`; en un push a main,
# `event.before`. Sin argumento (uso local) va contra main.
#
# Siempre a traves de `merge-base`, incluso con el sha que da GitHub: `base.sha`
# es el tip de la rama base cuando el PR se abrio o se actualizo por ultima vez,
# asi que puede estar atrasado. Comparar contra el directamente contaria commits
# ajenos —los que entraron a la base mientras tanto— como si fueran de este PR, y
# el gate se pondria rojo por el trabajo de otro. Un cartel que acusa al que no
# fue se apaga rapido.
RAW="${1:-}"

# Un `github.event.before` de ceros no es una base: es un push que crea la
# rama. Ahi si corresponde caer a main.
if [ -z "$RAW" ] || [ "$RAW" = "0000000000000000000000000000000000000000" ]; then
  RAW="origin/main"
fi

# FALLA CERRADO. Esta funcion es la que decide si el gate corre, asi que un
# "no pude resolver la base" que imprime [OK] y sale 0 es un gate que reporta
# haber verificado algo que no miro — exactamente el modo de falla que este
# script existe para arreglar, adentro del arreglo.
#
# Pasa de verdad: un force-push a main deja `github.event.before` inalcanzable,
# y en local `origin/main` puede no existir en un clone recien hecho. En los
# dos casos la version anterior dejaba pasar un cambio a un documento legal
# publicado sin decir una palabra.
if ! git rev-parse --verify --quiet "${RAW}^{commit}" >/dev/null; then
  echo "FAIL: no se pudo resolver la base '${RAW}'."
  echo ""
  echo "  Sin base no hay con que comparar, y este check NO puede decir que"
  echo "  todo esta bien: no miro nada. Falla cerrado a proposito."
  echo ""
  echo "  En CI suele ser un force-push que dejo el commit anterior"
  echo "  inalcanzable. En local, que falte 'origin/main':"
  echo ""
  echo "      git fetch origin main"
  echo ""
  echo "  O pasale una base explicita:"
  echo ""
  echo "      bash scripts/check_legal_generado.sh <sha>"
  exit 1
fi

if ! BASE="$(git merge-base "$RAW" HEAD)"; then
  echo "FAIL: '${RAW}' y HEAD no tienen ancestro comun."
  echo ""
  echo "  Sin ancestro comun no se puede saber que archivos toco este cambio,"
  echo "  asi que este check no puede opinar. Falla cerrado."
  exit 1
fi

# Los nueve nombres del ORDER, leidos del generador. Import puro: el modulo no
# tiene efectos de lado (el `main()` esta detras de `if __name__`).
PUBLICADOS=()
while IFS= read -r f; do
  [ -n "$f" ] && PUBLICADOS+=("$f")
done < <(python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('blc', 'scripts/build_legal_content.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print('\n'.join('docs/legal/' + n for n in m.ORDER))
")

if [ "${#PUBLICADOS[@]}" -eq 0 ]; then
  echo "FAIL: no se pudo leer ORDER de scripts/build_legal_content.py."
  echo "      Sin esa lista este check no sabe que archivos mirar, y un check"
  echo "      que no sabe que mirar no puede decir 'todo bien'."
  exit 1
fi

TOCADOS="$(git diff --name-only "$BASE" HEAD -- "${PUBLICADOS[@]}")"

if [ -z "$TOCADOS" ]; then
  echo "[OK] Este cambio no toca ningun documento legal publicado."
  exit 0
fi

if head -1 "$DART" 2>/dev/null | grep -q "GENERADO POR"; then
  echo "[OK] ${DART} esta generado — el desfasaje lo verifica \`--check\`."
  exit 0
fi

echo "FAIL: este cambio edita documentos legales publicados y el generador nunca corrio."
echo ""
echo "  Tocados:"
echo "$TOCADOS" | sed 's/^/    · /'
echo ""
echo "  Sigue siendo el texto ESCRITO A MANO —su primera linea no dice"
echo "  'GENERADO POR'—:"
echo "    ${DART}"
echo ""
echo "  El markdown que acabas de editar y lo que el usuario ve en la app son"
echo "  dos documentos distintos, y este cambio agranda la diferencia sin que"
echo "  nada mas lo note."
echo ""
echo "  Mientras queden marcadores [[PENDIENTE]] el generador aborta a proposito"
echo "  y el circuito no se puede cerrar. Para ver cuales faltan:"
echo ""
echo "      python3 scripts/build_legal_content.py"
echo ""
echo "  Si tu cambio NO puede esperar a que se resuelvan, decilo en el PR: que"
echo "  quede escrito que la app siguio mostrando el texto viejo, y por cuanto."
exit 1
