/**
 * test/emulador_de_functions_con_datos.test.js
 *
 * QUE NINGÚN COMANDO DEL REPO LEVANTE EL EMULADOR DE FUNCTIONS CON LOS DATOS
 * EN PRODUCCIÓN.
 *
 *   cd scripts && npm test
 *
 * ─── EL BUG ─────────────────────────────────────────────────────────────────
 *
 * `functions/package.json` traía el `serve` de la plantilla de `firebase init`:
 *
 *   npm run build && firebase emulators:start --only functions --project treino-dev
 *
 * Con Functions como único emulador, el runtime no recibe
 * `FIRESTORE_EMULATOR_HOST` ni los hosts de Auth y Storage, así que el Admin
 * SDK de cada función escribe en los servicios REALES de `treino-dev`. La
 * credencial la pone firebase-tools (`lib/emulator/env.js`,
 * `getCredentialsEnvironment`): las ADC de gcloud si existen, y si no, el login
 * de `firebase`, que el emulador vuelca a `~/.config/firebase/` y le pasa al
 * runtime por `GOOGLE_APPLICATION_CREDENTIALS`. "No hay ADC en la máquina" no
 * protege de nada.
 *
 * Medido el 2026-10-14 con firebase-tools 15.19.0: el `serve` viejo servía 27
 * funciones HTTP/callable en `127.0.0.1:5001/treino-dev/...` —`deleteAccount`,
 * `mpWebhook`, `createPreapproval` entre ellas— y una función sonda en ese
 * mismo runtime veía los tres hosts de emulador en null y la credencial
 * `UserRefreshClient` de las ADC de gcloud. El único aviso es una línea entre
 * ochenta: "calls to these services from the Functions emulator will affect
 * production".
 *
 * ─── QUÉ MIRA ───────────────────────────────────────────────────────────────
 *
 * Toda invocación de `emulators:start` / `emulators:exec` en los archivos que
 * se EJECUTAN: los `.sh`, los `.yml` (workflows de CI) y los `scripts` de cada
 * `package.json`. Si su `--only` incluye `functions`, tiene que incluir también
 * `firestore`, `auth` y `storage`, o nombrar un proyecto `demo-*`, que del lado
 * de Google no existe. Sin `--project` explícito no hay exención: el proyecto
 * sale de `.firebaserc` o de un `firebase use` heredado (AGENTS.md § Entornos,
 * corolario 4), y eso no se ve desde acá.
 *
 * Los `.md` y los comentarios quedan afuera a propósito: no se ejecutan, y un
 * gate que se pone rojo por un comentario entrena a ignorarlo. Para ver todas
 * las menciones del repo, incluidas las que este test no mira:
 *
 *   rg -n 'emulators:(start|exec)' --hidden -g '!node_modules' -g '!.git' .
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const REPO = path.join(__dirname, '..', '..');

/** Los archivos que se ejecutan. */
const EJECUTABLES = /(^|\/)package\.json$|\.(sh|ya?ml)$/;

const DE_DATOS = ['firestore', 'auth', 'storage'];

/** Los comandos de un archivo, con las continuaciones de shell ya unidas. */
function comandos(archivo, texto) {
  if (path.basename(archivo) === 'package.json') {
    return Object.values(JSON.parse(texto).scripts ?? {});
  }
  return texto
    .split(/\r?\n/)
    .filter((linea) => !/^\s*#/.test(linea))
    .join('\n')
    .replace(/\\\r?\n/g, ' ')
    .split('\n');
}

/** Cada `emulators:start|exec` de un comando, con su `--only` y su `--project`. */
function invocaciones(comando) {
  return comando
    .split(/(?=emulators:(?:start|exec)\b)/)
    .filter((tramo) => /^emulators:(?:start|exec)\b/.test(tramo))
    .map((tramo) => {
      const only = /--only[=\s]+["']?([^\s"']+)/.exec(tramo);
      const project = /(?:--project|-P)[=\s]+["']?([^\s"']+)/.exec(tramo);
      return {
        only: only ? only[1].split(',').map((s) => s.split(':')[0]) : null,
        project: project ? project[1] : null,
      };
    });
}

function problema({ only, project }) {
  // Sin `--only` se levantan todos los que declara firebase.json (ver el
  // último test).
  if (only === null) return null;
  if (only.some((s) => s.includes('$'))) {
    return `--only no se puede resolver acá: ${only.join(',')}`;
  }
  if (!only.includes('functions')) return null;
  if (project !== null && project.startsWith('demo-')) return null;
  const faltan = DE_DATOS.filter((s) => !only.includes(s));
  return faltan.length > 0 ? `levanta functions sin emular ${faltan.join(', ')}` : null;
}

function problemasDe(archivo, texto) {
  return comandos(archivo, texto).flatMap((comando) =>
    invocaciones(comando).map(problema).filter(Boolean),
  );
}

test('el detector marca el `serve` de la plantilla y deja pasar los buenos', () => {
  const malos = [
    'npm run build && firebase emulators:start --only functions --project treino-dev',
    'firebase emulators:start --only firestore,auth,functions --project treino-dev',
    'firebase emulators:start --only functions:deleteAccount --project=treino-dev',
    'firebase emulators:start --only functions',
  ];
  for (const comando of malos) {
    assert.strictEqual(problemasDe('x.sh', comando).length, 1, comando);
  }

  const buenos = [
    'exec firebase emulators:start --only firestore,auth,functions,storage --project treino-dev',
    'firebase emulators:exec --only firestore,auth,storage --project treino-dev "npm test"',
    'firebase emulators:start --only functions --project demo-sonda',
    'firebase emulators:start --project treino-dev',
    '# firebase emulators:start --only functions --project treino-dev',
  ];
  for (const comando of buenos) {
    assert.deepStrictEqual(problemasDe('x.sh', comando), [], comando);
  }

  // Las continuaciones de shell: `scripts/test_rules.sh` parte así su comando.
  const partido = 'firebase emulators:exec \\\n  --only functions \\\n  --project treino-dev "x"';
  assert.strictEqual(problemasDe('x.sh', partido).length, 1);

  const pkg = JSON.stringify({
    scripts: { serve: 'firebase emulators:start --only functions --project treino-dev' },
  });
  assert.strictEqual(problemasDe('functions/package.json', pkg).length, 1);
});

test('ningún comando del repo levanta functions con los datos en producción', () => {
  const r = spawnSync('git', ['ls-files', '-z'], { cwd: REPO, encoding: 'utf8' });
  assert.strictEqual(r.status, 0, r.stderr);
  const archivos = r.stdout.split('\0').filter((f) => f && EJECUTABLES.test(f));

  const encontrados = [];
  for (const archivo of archivos) {
    const texto = fs.readFileSync(path.join(REPO, archivo), 'utf8');
    for (const comando of comandos(archivo, texto)) {
      for (const inv of invocaciones(comando)) {
        encontrados.push({ archivo, comando: comando.trim(), ...inv });
      }
    }
  }

  // Control: el barrido tiene que ver el modo completo de emulator.sh, que es
  // una invocación con `functions`. Si no la ve, un verde no diría nada.
  assert.ok(
    encontrados.some((e) => e.archivo === 'scripts/emulator.sh' && e.only?.includes('functions')),
    'el barrido no encontró el `emulators:start` con functions de scripts/emulator.sh',
  );

  const malos = encontrados
    .map((e) => ({ ...e, problema: problema(e) }))
    .filter((e) => e.problema)
    .map((e) => `${e.archivo}: ${e.problema}\n    ${e.comando}`);
  assert.deepStrictEqual(malos, [], `\n${malos.join('\n')}\n` +
    'Usá ./scripts/emulator.sh, que levanta Functions junto con Firestore, Auth y Storage.');
});

test('sin --only, firebase.json levanta Firestore, Auth y Storage', () => {
  const firebaseJson = JSON.parse(fs.readFileSync(path.join(REPO, 'firebase.json'), 'utf8'));
  for (const servicio of DE_DATOS) {
    assert.ok(firebaseJson.emulators?.[servicio], `firebase.json no declara el emulador de ${servicio}`);
  }
});
