/**
 * test/emulator_genera_reglas.test.js
 *
 * QUE `scripts/emulator.sh` NUNCA LEVANTE EL EMULADOR SIN REGLAS.
 *
 *   cd scripts && npm test
 *
 * ─── EL BUG ─────────────────────────────────────────────────────────────────
 *
 * Desde el #1132 (2026-09-15) `firebase.json` le hace cargar al emulador
 * `firestore.deploy.rules`, un archivo GENERADO por `strip_rules.js` y
 * gitignoreado. `emulator.sh` no lo generaba, y sin el archivo el emulador de
 * Firestore no falla: avisa que "will default to allowing all reads and
 * writes" y arranca en allow-all. En todo clone y worktree limpio el flujo de
 * dev recomendado (AGENTS.md § Entornos) corría sin reglas. Medido el
 * 2026-10-14: un PATCH sin auth que crea `users/victima` con
 * `role: "trainer"` → 200.
 *
 * ─── POR QUÉ NO ES UN TEST TEXTUAL ──────────────────────────────────────────
 *
 * "emulator.sh nombra strip_rules.js antes de emulators:start" lo cumple
 * también la línea comentada, metida en un branch que no corre, seguida de un
 * `|| true` que se traga el fallo, o condicionada a que el archivo falte. Lo
 * que importa es QUÉ REGLAS HAY en el instante en que arranca `firebase`.
 *
 * Así que se corre el `emulator.sh` REAL —copiado a un repo de juguete, con lo
 * que él mismo invoca y el `firebase.json` real— con `firebase`, `npm` y `java`
 * reemplazados por stubs en el PATH. El stub de `firebase` hace lo mismo que el
 * de verdad: lee qué archivo de reglas nombra `firebase.json` y lo copia en el
 * momento en que lo llaman. Por eso el nombre no está escrito acá: si alguien
 * le cambia el destino a `firebase.json` o a `strip_rules.js` sin el otro, el
 * test se pone rojo.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const SCRIPTS_DIR = path.join(__dirname, '..');

/** El script y lo que él mismo carga o corre. Se copian del repo en cada test. */
const COPIADOS = ['emulator.sh', 'strip_rules.js', path.join('lib', 'java21.sh')];
const FIREBASE_JSON = path.join(SCRIPTS_DIR, '..', 'firebase.json');

const STUBS = {
  // Con `exec`, después de esto no queda script: lo que exista ahora es lo que
  // el emulador cargaría. Y cargaría lo que diga `firebase.json`, no un nombre
  // fijo.
  firebase: [
    '#!/usr/bin/env bash',
    'printf "%s\\n" "$*" > "$FOTO_DIR/argv"',
    'archivo="$(node -p \'require("./firebase.json").firestore.rules\')"',
    'if [ -f "$archivo" ]; then cp "$archivo" "$FOTO_DIR/reglas"; fi',
  ].join('\n'),
  // El `npm --prefix functions run build` del modo completo.
  npm: '#!/usr/bin/env bash\nexit 0',
  // `asegurar_java21` retorna en su primera línea si el java del PATH dice 21.
  java: '#!/usr/bin/env bash\necho \'openjdk version "21.0.8" 2025-07-15\' >&2',
};

const COMENTARIO = 'COMENTARIO_QUE_EL_STRIP_SACA';

/**
 * Reglas con una marca única por test: si el archivo que ve el emulador la
 * tiene, salió de ESTE `firestore.rules` y no de otra corrida.
 */
function reglasFuente(marca) {
  return [
    "rules_version = '2';",
    `// ${COMENTARIO}`,
    'service cloud.firestore {',
    '  match /databases/{database}/documents {',
    `    match /${marca}/{doc} {`,
    '      allow read, write: if false;',
    '    }',
    '  }',
    '}',
    '',
  ].join('\n');
}

function repoDeJuguete(t, { conFuente = true, viejas = null } = {}) {
  const raiz = fs.mkdtempSync(path.join(os.tmpdir(), 'emulator-reglas-'));
  t.after(() => fs.rmSync(raiz, { recursive: true, force: true }));

  for (const rel of COPIADOS) {
    const destino = path.join(raiz, 'scripts', rel);
    fs.mkdirSync(path.dirname(destino), { recursive: true });
    fs.copyFileSync(path.join(SCRIPTS_DIR, rel), destino);
  }
  fs.copyFileSync(FIREBASE_JSON, path.join(raiz, 'firebase.json'));
  // El modo con Functions corta antes de arrancar si no ve las deps.
  fs.mkdirSync(path.join(raiz, 'functions', 'node_modules'), { recursive: true });

  const bin = path.join(raiz, 'bin');
  fs.mkdirSync(bin);
  for (const [nombre, cuerpo] of Object.entries(STUBS)) {
    fs.writeFileSync(path.join(bin, nombre), `${cuerpo}\n`, { mode: 0o755 });
  }
  const foto = path.join(raiz, 'foto');
  fs.mkdirSync(foto);

  const marca = `marca_${crypto.randomBytes(6).toString('hex')}`;
  if (conFuente) fs.writeFileSync(path.join(raiz, 'firestore.rules'), reglasFuente(marca));
  if (viejas !== null) fs.writeFileSync(path.join(raiz, 'firestore.deploy.rules'), viejas);

  return { raiz, bin, foto, marca };
}

function correr(repo, extra) {
  const env = { ...process.env };
  delete env.SKIP_FUNCTIONS;
  Object.assign(env, extra, {
    // Los stubs primero; después el node que corre este test, para el strip.
    PATH: [repo.bin, path.dirname(process.execPath), process.env.PATH].join(path.delimiter),
    FOTO_DIR: repo.foto,
  });

  const r = spawnSync('bash', [path.join(repo.raiz, 'scripts', 'emulator.sh')], {
    cwd: repo.raiz,
    env,
    encoding: 'utf8',
    // Si un stub no se usara, el que arranca es el emulador de verdad, que no
    // termina nunca. Mejor un rojo a los 30 s que una suite colgada.
    timeout: 30_000,
  });
  assert.strictEqual(r.error, undefined, `no pude correr emulator.sh: ${r.error}`);

  const leer = (f) => (fs.existsSync(f) ? fs.readFileSync(f, 'utf8') : null);
  return {
    code: r.status,
    salida: r.stdout + r.stderr,
    argv: leer(path.join(repo.foto, 'argv')),
    reglas: leer(path.join(repo.foto, 'reglas')),
  };
}

const MODOS = [
  { nombre: 'SKIP_FUNCTIONS=1', env: { SKIP_FUNCTIONS: '1' }, only: 'firestore,auth,storage' },
  { nombre: 'modo completo', env: {}, only: 'firestore,auth,functions,storage' },
];

for (const modo of MODOS) {
  test(`${modo.nombre}: el emulador arranca con las reglas de firestore.rules, sin comentarios`, (t) => {
    const repo = repoDeJuguete(t);
    const r = correr(repo, modo.env);

    assert.strictEqual(r.code, 0, `emulator.sh salió con ${r.code}.\nSALIDA:\n${r.salida}`);
    assert.ok(r.argv, `no llamó a \`firebase\` — el test no mide nada.\nSALIDA:\n${r.salida}`);
    // Que sea ESTE branch el que arrancó, y no el otro.
    assert.ok(
      r.argv.includes('emulators:start') && r.argv.includes(`--only ${modo.only} `),
      `arrancó otra cosa: ${r.argv}`,
    );
    assert.notStrictEqual(
      r.reglas,
      null,
      'el emulador arrancó SIN el archivo de reglas que nombra firebase.json: el de\n' +
        'Firestore cae a allow-all.\n' +
        `SALIDA:\n${r.salida}`,
    );
    assert.ok(r.reglas.includes(repo.marca), `no son las reglas de este firestore.rules:\n${r.reglas}`);
    assert.ok(!r.reglas.includes(COMENTARIO), `no pasaron por strip_rules.js:\n${r.reglas}`);
  });

  test(`${modo.nombre}: un firestore.deploy.rules de otra corrida se regenera, no se reusa`, (t) => {
    const repo = repoDeJuguete(t, { viejas: 'REGLAS_DE_OTRA_CORRIDA\n' });
    const r = correr(repo, modo.env);

    assert.strictEqual(r.code, 0, `emulator.sh salió con ${r.code}.\nSALIDA:\n${r.salida}`);
    assert.ok(r.reglas, `no llamó a \`firebase\` o no había reglas.\nSALIDA:\n${r.salida}`);
    assert.ok(
      !r.reglas.includes('REGLAS_DE_OTRA_CORRIDA') && r.reglas.includes(repo.marca),
      `el emulador cargó las reglas viejas:\n${r.reglas}`,
    );
  });

  test(`${modo.nombre}: si strip_rules.js falla, el emulador NO arranca`, (t) => {
    // Sin `firestore.rules`, el strip sale con 1. Y con un `deploy.rules` viejo
    // a mano, que es el caso tentador: arrancar "con lo que hay".
    const repo = repoDeJuguete(t, { conFuente: false, viejas: 'REGLAS_DE_OTRA_CORRIDA\n' });
    const r = correr(repo, modo.env);

    assert.notStrictEqual(r.code, 0, `salió con 0 sin poder generar las reglas.\nSALIDA:\n${r.salida}`);
    assert.strictEqual(r.argv, null, `llamó a firebase igual: ${r.argv}`);
    assert.match(r.salida, /el emulador NO se levanta/);
  });
}
