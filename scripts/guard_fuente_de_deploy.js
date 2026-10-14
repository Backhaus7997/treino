#!/usr/bin/env node
/**
 * guard_fuente_de_deploy.js — frena un deploy de reglas o índices si lo que se
 * va a subir no es idéntico a `origin/develop`.
 *
 *   node scripts/guard_fuente_de_deploy.js firestore.rules firestore.indexes.json
 *
 * Lo corren los `predeploy` de `firebase.json` (firestore y storage), ANTES de
 * todo lo demás. El por qué y la invariante están en `lib/fuente_de_deploy.js`.
 *
 * Emergencia (deployar algo que no es `develop`, a sabiendas):
 *   TREINO_DEPLOY_FUERA_DE_DEVELOP=1 firebase deploy ...
 * Deja pasar, pero imprime igual qué difiere. Avisá al equipo si lo usás.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { REF_FUENTE, VAR_OVERRIDE, verificarFuente } = require('./lib/fuente_de_deploy');

// La raíz sale de este archivo, no del cwd: los hooks de firebase-tools no
// garantizan desde dónde corren.
const ROOT = path.join(__dirname, '..');

function git(args) {
  return execFileSync('git', args, {
    cwd: ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    maxBuffer: 64 * 1024 * 1024,
  });
}

function main(archivos) {
  if (archivos.length === 0) {
    console.error('uso: node scripts/guard_fuente_de_deploy.js <archivo> [<archivo>...]');
    return 2;
  }

  const r = verificarFuente({
    archivos,
    actualizarRemoto: () => git(['fetch', '--quiet', 'origin', 'develop']),
    leerLocal: (archivo) => fs.readFileSync(path.join(ROOT, archivo), 'utf8'),
    leerRemoto: (archivo) => git(['show', `${REF_FUENTE}:${archivo}`]),
    env: process.env,
  });

  if (r.problemas.length === 0) {
    console.log(`✓ ${archivos.join(', ')}: idéntico a ${REF_FUENTE}.`);
    return 0;
  }

  const lineas = r.problemas.map((p) => `    - ${p.archivo}: ${p.motivo}`);
  const atras = contarCommitsAtras();

  if (r.override) {
    console.warn(
      [
        '',
        `⚠ DEPLOY FUERA DE ${REF_FUENTE} (${VAR_OVERRIDE}=1). Va a subir esto, que NO es develop:`,
        ...lineas,
        '  Si no es una emergencia, cortá ahora. Si lo es, avisá al equipo qué subiste y por qué.',
        '',
      ].join('\n'),
    );
    return 0;
  }

  console.error(
    [
      '',
      `✗ DEPLOY FRENADO: lo que vas a subir no es idéntico a ${REF_FUENTE}.`,
      ...lineas,
      atras > 0 ? `    (este checkout está ${atras} commits atrás de ${REF_FUENTE})` : '',
      '',
      '  Así se hizo el rollback de reglas del 2026-10-13: un deploy desde una rama',
      '  vieja borró de producción reglas ya mergeadas, sin conflicto ni aviso.',
      '',
      '  Qué hacer: deployar desde un checkout limpio en develop, por ejemplo',
      '    git worktree add .claude/worktrees/deploy origin/develop',
      '  y correr el deploy desde ese directorio. Para ver la diferencia:',
      `    git fetch origin develop && git diff ${REF_FUENTE} -- ${archivos.join(' ')}`,
      '',
      `  Emergencia, a sabiendas: ${VAR_OVERRIDE}=1 (deja pasar e imprime igual esta lista).`,
      '',
    ]
      .filter((l, i, a) => !(l === '' && a[i - 1] === ''))
      .join('\n'),
  );
  return 1;
}

// Sólo para el mensaje: si falla, no opina.
function contarCommitsAtras() {
  try {
    return Number(git(['rev-list', '--count', `HEAD..${REF_FUENTE}`]).trim()) || 0;
  } catch {
    return 0;
  }
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}

module.exports = { main };
