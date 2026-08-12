#!/usr/bin/env bash
# Regenera lib/wear_spike_fixtures.dart desde conformance/*.json.
#
# El spike de Wear OS corre EN EL RELOJ, donde no hay acceso al filesystem del
# repo. Los fixtures viajan embebidos en un .dart. Al ser generado y no copiado
# a mano, no puede divergir del contrato real.
#
# Uso: bash scripts/gen_wear_spike_fixtures.sh
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, pathlib

root = pathlib.Path('.')
out = ["// GENERADO — no editar a mano.",
       "// Fuente: conformance/plan_advance.json, conformance/routine_selection.json",
       "// Regenerar con: bash scripts/gen_wear_spike_fixtures.sh",
       "//",
       "// Existe porque el spike corre EN EL RELOJ y ahi no hay acceso al filesystem",
       "// del repo: los fixtures viajan embebidos. Al ser generado, no puede divergir",
       "// del contrato real.",
       ""]

for name, var in (('plan_advance', 'planAdvanceFixturesJson'),
                  ('routine_selection', 'routineSelectionFixturesJson')):
    raw = (root / 'conformance' / f'{name}.json').read_text()
    compact = json.dumps(json.loads(raw), ensure_ascii=False, separators=(',', ':'))
    escaped = compact.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')
    out.append(f"const String {var} = '{escaped}';")
    out.append("")

(root / 'lib' / 'wear_spike_fixtures.dart').write_text('\n'.join(out))
print("escrito lib/wear_spike_fixtures.dart")
PY

# El gate de calidad del repo es `dart format .`; que el generado salga ya
# formateado evita que la proxima corrida ensucie el diff.
dart format lib/wear_spike_fixtures.dart
