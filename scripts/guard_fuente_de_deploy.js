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

// El fetch que trae `origin/develop`, con dos cosas que un `git fetch origin
// develop` pelado no garantiza:
//
// - **Refspec explícito.** El pelado actualiza `origin/develop` sólo si el
//   `remote.origin.fetch` del clon mapea esa rama. En un clon `--single-branch`
//   de main no la mapea: el fetch sale bien, `origin/develop` queda donde
//   estaba, y el guard compara contra esa copia vieja y dice "✓ idéntico".
//   Reproducido con un sandbox: develop con la regla nueva, el checkout con la
//   vieja, exit 0. Es la "comparación contra una mentira" que el guard existe
//   para evitar.
//
// - **Se corta si una conexión establecida deja de transferir.** Contra un
//   servidor http que acepta la conexión y no manda nada, git esperaba sin
//   límite (medido: seguía colgado a los 40 s) y el deploy con él, mudo por el
//   `--quiet`. Ahora aborta si pasa menos de 1 KB/s durante 30 s.
//
//   Qué NO hace, medido:
//   · No acota el connect ni el handshake TLS. En https —el remoto de este
//     repo— un handshake que nunca contesta sigue colgado hasta el timeout de
//     curl, 300 s. Lo que sí corta es una conexión https ya establecida que se
//     queda muda (5 s con lowSpeedTime=5).
//   · También corta a un servidor SANO que tarde más de 30 s en armar el pack:
//     con `--quiet` no viaja nada mientras lo prepara (medido con `git
//     http-backend` demorado: 35 s de silencio → corte a los 31 s). Contra
//     GitHub no está medido; si pasa, falla cerrado y se reintenta.
//   · Un remoto por ssh no lee `http.*`.
//
//   No es un timeout total a propósito: ponerse al día desde el checkout raíz
//   del 2026-10-14 (`7496e2d3`, 602 commits atrás) son ~32 MB —`git
//   pack-objects --revs` de `origin/develop ^7496e2d3`—, y un tope fijo
//   cortaría un fetch lento pero en marcha, que al reintentar empieza de cero.
const FETCH_DEVELOP = [
  '-c', 'http.lowSpeedLimit=1000',
  '-c', 'http.lowSpeedTime=30',
  'fetch', '--quiet', 'origin', `+refs/heads/develop:refs/remotes/${REF_FUENTE}`,
];

function main(archivos) {
  if (archivos.length === 0) {
    console.error('uso: node scripts/guard_fuente_de_deploy.js <archivo> [<archivo>...]');
    return 2;
  }

  const r = verificarFuente({
    archivos,
    actualizarRemoto: () => {
      try {
        git(FETCH_DEVELOP);
      } catch (e) {
        // `execFileSync` pone "Command failed: git …" en la primera línea y el
        // stderr de git abajo, y el mensaje del guard se queda con la primera:
        // la causa ("Operation too slow", "Could not resolve host") se perdía.
        // Va en una sola línea para que llegue entera.
        const causa = String(e.stderr || '').trim().split('\n').filter(Boolean).join(' · ');
        throw new Error(causa || e.message);
      }
    },
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
