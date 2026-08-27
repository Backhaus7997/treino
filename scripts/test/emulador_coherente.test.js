/**
 * test/emulador_coherente.test.js
 *
 * #834 — QUE "EMULADOR" SIGNIFIQUE QUE EL DESTINO ESTÁ REDIRIGIDO.
 *
 *   cd scripts && npm test
 *
 * ─── POR QUÉ ESTE TEST NO SE PARECE A NINGÚN OTRO DE LA SUITE ───────────────
 *
 * El bug que cierra no se ve en un diff. La variable no desapareció, no cambió
 * de nombre, no se movió de lugar: cambió de DE DÓNDE SALE.
 *
 *   antes:  const USANDO_EMULADOR = Boolean(FIRESTORE_EMULATOR_HOST)
 *   ahora:  const USANDO_EMULADOR = contexto.modo === 'emulador'
 *
 * Dos líneas que se leen igual de bien, y `contexto.modo` valía `'emulador'`
 * con CUALQUIERA de cuatro variables mientras la redirección real la hacía UNA.
 * O sea que `FIREBASE_DATABASE_EMULATOR_HOST` —de un producto que TREINO ni
 * usa— alcanzaba para que un backfill se saltee la credencial entera (#834),
 * apague el cartel de producción (#826) y escriba en el `treino-dev` REAL.
 *
 * Ninguna herramienta de diff ve eso. La revisión por líneas tampoco: no falta
 * ninguna línea, ni siquiera con la regla buena ("¿qué agregó el otro PR que
 * hoy no está?"). Lo único que lo ve es CORRER EL SCRIPT Y MIRAR LA SALIDA.
 *
 * Por eso este archivo no asserta sobre módulos: levanta los scripts REALES en
 * un subproceso, con `firebase-admin` stubbeado, y afirma un INVARIANTE sobre
 * lo que sale por pantalla, para cada combinación de variables de emulador.
 * Un test así falla igual el día que la condición se reescriba de una tercera
 * forma que hoy no existe — que es exactamente lo que hace falta acá.
 *
 * ─── EL INVARIANTE ──────────────────────────────────────────────────────────
 *
 *   Un script NUNCA toca Firestore de producción sin que el operador lo haya
 *   visto venir.
 *
 * Formalmente, para toda combinación de variables:
 *
 *   llegóAFirestore ∧ ¬firestoreRedirigido  ⟹  salió el cartel de PRODUCCIÓN
 *
 * Con la versión que este PR trajo, `FIREBASE_AUTH_EMULATOR_HOST=…` sola daba
 * `llegóAFirestore = true`, `firestoreRedirigido = false` y `cartel = false`.
 * Ese es el caso que este archivo mide, y es el bug del #838 otra vez.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { RUTA_CREDENCIAL_FALSA } = require('./fixtures/stub_firebase_admin');

const SCRIPTS_DIR = path.join(__dirname, '..');
const STUB = path.join(__dirname, 'fixtures', 'stub_firebase_admin.js');

/**
 * El vocabulario sale del módulo, no de una copia local: si mañana aparece una
 * quinta variable de emulador, entra sola a las 8 combinaciones de abajo. Una
 * lista repetida acá dejaría a la nueva sin cubrir el día que se agregue, que es
 * exactamente cuando hace falta.
 */
const {
  VAR_EMULADOR_FIRESTORE: FIRESTORE,
  VARS_DE_EMULADOR_PARCIALES: PARCIALES,
} = require('../lib/credenciales');

/**
 * Los scripts que ramifican en "¿emulador?" y que, si esa rama miente, escriben
 * en producción sin cartel.
 *
 * Están los DOS caminos por los que hoy se responde esa pregunta, a propósito:
 *   · `contexto.modo === 'emulador'`  (lib/credenciales.js)  → los backfills
 *   · `usandoEmulador()`              (lib/target_project.js) → los entrypoints
 * Tener una sola familia acá dejaría a la otra libre de volver a divergir, que
 * es justo cómo el desfasaje se metió.
 */
const SCRIPTS = [
  { script: 'backfill_gym_ids.js', argv: ['--dry-run'] },
  { script: 'backfill_gym_names.js', argv: ['--dry-run'] },
  { script: 'seed_trainer_profiles.js', argv: [] },
  { script: 'promote_user_to_trainer.js', argv: ['uid-de-prueba'] },
  { script: 'seed_workout_catalog.js', argv: ['--exercises'] },
];

/**
 * Levanta el script con el stub puesto.
 *
 * `conCredencial` decide si se exporta `$TREINO_SA_KEY`. El caso SIN es el que
 * importa de verdad: prueba que una variable de emulador parcial no es una
 * llave maestra para saltearse la frontera entera del #834.
 */
function correr({ script, argv }, emuladores = {}, { conCredencial = true } = {}) {
  const env = { ...process.env };
  // Si la máquina que corre los tests tiene alguna exportada, el test mediría
  // otra cosa que la que dice medir.
  for (const v of [
    FIRESTORE,
    ...PARCIALES,
    'STORAGE_EMULATOR_HOST',
    'GOOGLE_CLOUD_PROJECT',
    'GCLOUD_PROJECT',
    'FIREBASE_STORAGE_BUCKET',
    'TREINO_SA_KEY',
    'GOOGLE_APPLICATION_CREDENTIALS',
  ]) {
    delete env[v];
  }
  if (conCredencial) env.TREINO_SA_KEY = RUTA_CREDENCIAL_FALSA;
  Object.assign(env, emuladores);

  const res = spawnSync(
    process.execPath,
    ['--require', STUB, path.join(SCRIPTS_DIR, script), ...argv],
    { cwd: SCRIPTS_DIR, env, encoding: 'utf8' },
  );
  assert.strictEqual(res.error, undefined, `no pude ejecutar ${script}: ${res.error}`);
  const todo = res.stdout + res.stderr;
  return {
    todo,
    code: res.status,
    llegoAFirestore: todo.includes('STUB_FIRESTORE_REACHED'),
    cartel: todo.includes('IS PRODUCTION'),
    aborto: todo.includes('ABORTADO'),
  };
}

/** Todas las combinaciones de las tres parciales, con y sin la de Firestore. */
function combinaciones() {
  const out = [];
  for (let mascara = 0; mascara < 1 << PARCIALES.length; mascara++) {
    const puestas = PARCIALES.filter((_, i) => mascara & (1 << i));
    for (const conFirestore of [false, true]) {
      const env = Object.fromEntries(puestas.map((v) => [v, 'localhost:9999']));
      if (conFirestore) env[FIRESTORE] = 'localhost:8080';
      out.push({
        env,
        conFirestore,
        etiqueta:
          [conFirestore ? FIRESTORE : null, ...puestas].filter(Boolean).join(' + ') || '(ninguna)',
      });
    }
  }
  return out;
}

for (const entrada of SCRIPTS) {
  const { script } = entrada;

  for (const { env, conFirestore, etiqueta } of combinaciones()) {
    test(`${script}: INVARIANTE con ${etiqueta}`, () => {
      const r = correr(entrada, env);

      if (r.llegoAFirestore && !conFirestore) {
        assert.ok(
          r.cartel,
          `escribió en el Firestore REAL sin cartel de producción (env: ${etiqueta}).\n` +
            'Eso es el #838 otra vez: el proceso se cree local y los datos van a\n' +
            `\`treino-dev\`, que es producción (#826).\n\nSALIDA:\n${r.todo}`,
        );
      }

      // La otra mitad, y la que atrapa el desfasaje: si el script se comportó
      // como si estuviera en el emulador —no pidió credencial, no gritó— es
      // porque Firestore está redirigido de verdad. No hay tercera opción.
      if (!conFirestore) {
        assert.ok(
          r.cartel || r.aborto,
          `ni cartel ni abort con Firestore apuntando a la nube (env: ${etiqueta}).\n` +
            `SALIDA:\n${r.todo}`,
        );
      }
    });
  }

  for (const parcial of PARCIALES) {
    test(`${script}: ${parcial} sola ABORTA y no toca Firestore`, () => {
      // EL TEST DEL BUG. Antes de este arreglo la corrida seguía derecho: sin
      // credencial, sin cartel, contra el Firestore real.
      const r = correr(entrada, { [parcial]: 'localhost:9999' });

      assert.strictEqual(r.code, 1, `tenía que cortar con exit 1.\nSALIDA:\n${r.todo}`);
      assert.match(r.todo, /Firestore NO está redirigido/);
      assert.ok(!r.llegoAFirestore, `llegó a Firestore igual.\nSALIDA:\n${r.todo}`);
    });

    test(`${script}: ${parcial} sola NO saltea la frontera de credenciales`, () => {
      // Sin `$TREINO_SA_KEY`: la variable parcial no puede ser una llave maestra
      // que apague el #834 entero. Si el script arranca acá, cualquiera con ADC
      // de `gcloud` puesto escribe en producción autenticado y sin enterarse.
      const r = correr(entrada, { [parcial]: 'localhost:9999' }, { conCredencial: false });

      assert.strictEqual(r.code, 1, `tenía que cortar con exit 1.\nSALIDA:\n${r.todo}`);
      assert.ok(!r.llegoAFirestore, `llegó a Firestore sin credencial.\nSALIDA:\n${r.todo}`);
    });
  }

  test(`${script}: con FIRESTORE_EMULATOR_HOST corre sin credencial y sin cartel`, () => {
    // El contracontrol: el arreglo NO puede cobrarle nada al camino documentado.
    // `FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/<script>.js` es la
    // invocación de scripts/README.md y tiene que seguir andando pelada.
    const r = correr(entrada, { [FIRESTORE]: 'localhost:8080' }, { conCredencial: false });

    assert.ok(!r.cartel, `gritó producción contra el emulador.\nSALIDA:\n${r.todo}`);
    assert.ok(!r.aborto, `abortó una corrida válida.\nSALIDA:\n${r.todo}`);
    assert.ok(r.llegoAFirestore, `no llegó a Firestore — el test no mide nada.\nSALIDA:\n${r.todo}`);
  });
}
