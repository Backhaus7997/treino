/**
 * test/credenciales.test.js
 *
 * #834 — los tests de la frontera de la credencial.
 *
 *   cd scripts && npm test
 *
 * Por qué importan: lo que decide este módulo es si un script escribe o no
 * escribe en el proyecto donde viven los usuarios reales. Un falso negativo acá
 * —"esto no es producción"— no ensucia la base, la destruye con permisos de
 * Admin SDK, que se saltean las rules.
 *
 * TODO entra por stub: `env`, `existeEntrada`, `leerArchivo`, `modoDeArchivo`.
 * Ningún test toca el filesystem ni necesita una credencial de verdad — la
 * credencial real nunca aparece en este archivo ni podría.
 *
 * `node:test` y `node:assert`, sin dependencias nuevas, igual que
 * `dedupe_setlogs_plan.test.js`.
 */

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const {
  VAR_RUTA,
  VAR_ADC,
  ErrorDeCredencial,
  resolverRutaCredencial,
  cargarCredencial,
  permisosDemasiadoAbiertos,
  proyectoDeLaIdentidad,
  evaluarProduccion,
  usandoEmulador,
  emuladoresParcialesPuestos,
  resolverContexto,
  RAIZ_DEL_REPO,
} = require('../lib/credenciales');

// ── Utilidades ─────────────────────────────────────────────────────────────

const HOME = '/home/tester';
const FUERA = '/home/tester/.config/treino/sa-key.json';

/** Un filesystem falso: un Set de rutas que "existen". */
const fsFalso = (...rutas) => {
  const set = new Set(rutas);
  return (p) => set.has(p);
};

/** Credencial de juguete. Nunca es una clave real: `private_key` es un sello. */
const credencialDe = (clientEmail, projectId) => ({
  type: 'service_account',
  project_id: projectId,
  client_email: clientEmail,
  private_key: '-----BEGIN PRIVATE KEY-----FALSA-----END PRIVATE KEY-----',
});

/** Corre `fn` y devuelve el `ErrorDeCredencial` que tiró. Falla si no tiró. */
const capturar = (fn) => {
  try {
    fn();
  } catch (err) {
    assert.ok(
      err instanceof ErrorDeCredencial,
      `esperaba ErrorDeCredencial y vino ${err.name}: ${err.message}`,
    );
    return err;
  }
  assert.fail('esperaba que fallara y no falló');
};

// ── 1. Sin la variable: falla, y el mensaje dice qué hacer ─────────────────

test('sin TREINO_SA_KEY falla — no hay default a ./sa-key.json', () => {
  const err = capturar(() =>
    resolverRutaCredencial({ env: {}, existeEntrada: fsFalso(), home: HOME }),
  );

  assert.strictEqual(err.codigo, 'SIN_VARIABLE');
});

test('el mensaje de "sin variable" trae las instrucciones, no sólo el reproche', () => {
  const err = capturar(() =>
    resolverRutaCredencial({ env: {}, existeEntrada: fsFalso(), home: HOME }),
  );

  // Qué variable falta y cómo setearla.
  assert.match(err.message, new RegExp(`export ${VAR_RUTA}=`));
  // Cómo migrar lo que ya está en el repo.
  assert.match(err.message, /mv scripts\/sa-key\.json/);
  assert.match(err.message, /chmod 600/);
  // La salida sin credencial.
  assert.match(err.message, /FIRESTORE_EMULATOR_HOST=localhost:8080/);
  // De dónde sale la regla.
  assert.match(err.message, /#834/);
});

// ── 1 bis. GOOGLE_APPLICATION_CREDENTIALS: el origen que no elegimos ──────
//
// El ADC de Google la lee adentro de la librería, sin pasar por el resolutor.
// Si la ignoráramos, `GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json`
// seguiría cargando la clave de producción desde adentro del repo y la frontera
// sería decorativa. Se acepta como origen, con las MISMAS reglas.

test('GOOGLE_APPLICATION_CREDENTIALS sola alcanza como origen', () => {
  const ruta = resolverRutaCredencial({
    env: { [VAR_ADC]: FUERA },
    existeEntrada: fsFalso(FUERA),
    home: HOME,
  });

  assert.strictEqual(ruta, FUERA);
});

test('GOOGLE_APPLICATION_CREDENTIALS adentro de un árbol de git se rechaza igual', () => {
  // Sin esto, cablear los 22 scripts de ADC no habría cerrado nada: el mismo
  // archivo prohibido entraba por la otra variable.
  const dentro = '/algun/repo/scripts/sa-key.json';
  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_ADC]: dentro },
      existeEntrada: fsFalso(dentro, '/algun/repo/.git'),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'DENTRO_DEL_REPO');
  // El mensaje nombra la variable que falló, no la canónica.
  assert.match(err.message, new RegExp(VAR_ADC));
});

test('con las dos variables a la MISMA ruta, no hay conflicto', () => {
  const ruta = resolverRutaCredencial({
    env: { [VAR_RUTA]: FUERA, [VAR_ADC]: FUERA },
    existeEntrada: fsFalso(FUERA),
    home: HOME,
  });

  assert.strictEqual(ruta, FUERA);
});

test('con las dos variables a rutas distintas se frena: son dos identidades', () => {
  const otra = '/home/tester/.config/treino/otra.json';
  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: FUERA, [VAR_ADC]: otra },
      existeEntrada: fsFalso(FUERA, otra),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'VARIABLES_EN_CONFLICTO');
  assert.match(err.message, new RegExp(`unset ${VAR_ADC}`));
});

test('el `~` se expande antes de comparar las dos variables', () => {
  // `~/x` y `/home/tester/x` son el mismo archivo: comparar los crudos daría
  // un conflicto falso y frenaría a alguien que no hizo nada mal.
  const ruta = resolverRutaCredencial({
    env: { [VAR_RUTA]: '~/.config/treino/sa-key.json', [VAR_ADC]: FUERA },
    existeEntrada: fsFalso(FUERA),
    home: HOME,
  });

  assert.strictEqual(ruta, FUERA);
});

test('cargarCredencial reporta de qué variable salió', () => {
  const cred = credencialDe('sa@ajeno.iam.gserviceaccount.com', 'ajeno');

  const desdeAdc = cargarCredencial({
    env: { [VAR_ADC]: FUERA },
    existeEntrada: fsFalso(FUERA),
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o600,
    home: HOME,
  });

  assert.strictEqual(desdeAdc.variable, VAR_ADC);
});

test('la variable vacía o en blanco cuenta como ausente', () => {
  for (const valor of ['', '   ', '\t\n']) {
    const err = capturar(() =>
      resolverRutaCredencial({
        env: { [VAR_RUTA]: valor, [VAR_ADC]: valor },
        existeEntrada: fsFalso(),
        home: HOME,
      }),
    );
    assert.strictEqual(err.codigo, 'SIN_VARIABLE', `valor ${JSON.stringify(valor)}`);
  }
});

// ── 2. Una ruta adentro del repo: falla ────────────────────────────────────

test('una ruta adentro de ESTE checkout falla', () => {
  const enElRepo = path.join(RAIZ_DEL_REPO, 'scripts', 'sa-key.json');

  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: enElRepo },
      // El archivo existe Y el repo tiene .git: el peor caso, el que hoy anda.
      existeEntrada: fsFalso(enElRepo, path.join(RAIZ_DEL_REPO, '.git')),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'DENTRO_DEL_REPO');
  assert.match(err.message, /este checkout/);
  assert.match(err.message, /#834/);
});

test('adentro de un worktree también falla — ahí `.git` es un ARCHIVO', () => {
  // El caso real: 26 worktrees de agente, cada uno con su `.git` archivo.
  const worktree = path.join(RAIZ_DEL_REPO, '.claude', 'worktrees', 'fix-834d');
  const clave = path.join(worktree, 'scripts', 'sa-key.json');

  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: clave },
      existeEntrada: fsFalso(clave, path.join(worktree, '.git')),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'DENTRO_DEL_REPO');
});

test('la ruta relativa que salta del worktree al repo raíz también falla', () => {
  // `../../../scripts/sa-key.json` desde un worktree: sale del worktree pero
  // cae en el repo raíz. Es EL agujero que #834 vino a cerrar.
  const worktree = path.join(RAIZ_DEL_REPO, '.claude', 'worktrees', 'fix-834d');
  const escape = path.resolve(worktree, '..', '..', '..', 'scripts', 'sa-key.json');

  assert.strictEqual(escape, path.join(RAIZ_DEL_REPO, 'scripts', 'sa-key.json'));

  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: escape },
      existeEntrada: fsFalso(escape, path.join(RAIZ_DEL_REPO, '.git')),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'DENTRO_DEL_REPO');
});

test('"adentro del repo" gana sobre "no existe" — el mensaje útil es la migración', () => {
  const enElRepo = path.join(RAIZ_DEL_REPO, 'scripts', 'sa-key.json');

  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: enElRepo },
      // El archivo NO está; sólo está el .git.
      existeEntrada: fsFalso(path.join(RAIZ_DEL_REPO, '.git')),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'DENTRO_DEL_REPO');
  assert.match(err.message, /mkdir -p ~\/\.config\/treino/);
});

test('una ruta fuera de todo árbol de git y existente resuelve', () => {
  const ruta = resolverRutaCredencial({
    env: { [VAR_RUTA]: FUERA },
    existeEntrada: fsFalso(FUERA),
    home: HOME,
  });

  assert.strictEqual(ruta, FUERA);
});

test('`~` se expande, y sigue valiendo la regla del árbol de git', () => {
  const ruta = resolverRutaCredencial({
    env: { [VAR_RUTA]: '~/.config/treino/sa-key.json' },
    existeEntrada: fsFalso(FUERA),
    home: HOME,
  });

  assert.strictEqual(ruta, FUERA);
});

test('una ruta fuera del repo pero inexistente falla como inexistente', () => {
  const err = capturar(() =>
    resolverRutaCredencial({
      env: { [VAR_RUTA]: FUERA },
      existeEntrada: fsFalso(),
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'NO_EXISTE');
  assert.match(err.message, /FIRESTORE_EMULATOR_HOST/);
});

// ── 3. El emulador anda sin credencial ─────────────────────────────────────

test('usandoEmulador es SÓLO la variable que desvía Firestore', () => {
  assert.strictEqual(usandoEmulador({}), false);
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: '' }), false);
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: '   ' }), false);
  assert.strictEqual(usandoEmulador({ FIRESTORE_EMULATOR_HOST: 'localhost:8080' }), true);

  // Ésta es la aserción que cambió de signo, y el cambio ES el arreglo. Antes
  // cualquiera de las tres devolvía `true`, y de ese `true` cuelgan las dos
  // decisiones más peligrosas del módulo: saltear la credencial (#834) y apagar
  // el cartel de producción (#826). Ninguna de las tres desvía Firestore, que
  // es lo que estos scripts escriben — o sea que las dos decisiones se tomaban
  // sobre una corrida que iba derecho a producción.
  assert.strictEqual(usandoEmulador({ FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099' }), false);
  assert.strictEqual(usandoEmulador({ FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199' }), false);
  assert.strictEqual(usandoEmulador({ FIREBASE_DATABASE_EMULATOR_HOST: 'localhost:9000' }), false);
});

test('emuladoresParcialesPuestos nombra las que están, en orden', () => {
  assert.deepStrictEqual(emuladoresParcialesPuestos({}), []);
  assert.deepStrictEqual(emuladoresParcialesPuestos({ FIRESTORE_EMULATOR_HOST: 'x' }), []);
  assert.deepStrictEqual(
    emuladoresParcialesPuestos({
      FIREBASE_DATABASE_EMULATOR_HOST: 'localhost:9000',
      FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099',
      FIREBASE_STORAGE_EMULATOR_HOST: '   ',
    }),
    ['FIREBASE_AUTH_EMULATOR_HOST', 'FIREBASE_DATABASE_EMULATOR_HOST'],
  );
});

test('un emulador parcial SIN Firestore redirigido aborta por incoherencia', () => {
  for (const v of [
    'FIREBASE_AUTH_EMULATOR_HOST',
    'FIREBASE_STORAGE_EMULATOR_HOST',
    'FIREBASE_DATABASE_EMULATOR_HOST',
  ]) {
    const err = capturar(() =>
      resolverContexto({
        env: { [v]: 'localhost:9999' },
        existeEntrada: () => assert.fail('no tiene que llegar a mirar el filesystem'),
        leerArchivo: () => assert.fail('no tiene que llegar a leer credenciales'),
        home: HOME,
      }),
    );
    assert.strictEqual(err.codigo, 'EMULADOR_INCOHERENTE');
    assert.match(err.message, new RegExp(v));
    assert.match(err.message, /FIRESTORE_EMULATOR_HOST/);
  }
});

test('la incoherencia se chequea ANTES que la credencial', () => {
  // Con el orden al revés el error sería "falta TREINO_SA_KEY", que manda a
  // exportar la clave de PRODUCCIÓN para arreglar una corrida que la persona
  // quería local. El mensaje equivocado acá es una invitación al accidente.
  const err = capturar(() =>
    resolverContexto({ env: { FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099' }, home: HOME }),
  );
  assert.strictEqual(err.codigo, 'EMULADOR_INCOHERENTE');
});

test('con Firestore redirigido, las parciales acompañan sin abortar', () => {
  const ctx = resolverContexto({
    env: {
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099',
      FIREBASE_STORAGE_EMULATOR_HOST: 'localhost:9199',
    },
    existeEntrada: () => assert.fail('el emulador no debe mirar el filesystem'),
    leerArchivo: () => assert.fail('el emulador no debe leer credenciales'),
    home: HOME,
  });
  assert.strictEqual(ctx.modo, 'emulador');
});

test('con el emulador el contexto resuelve sin credencial y sin TREINO_SA_KEY', () => {
  const ctx = resolverContexto({
    env: { FIRESTORE_EMULATOR_HOST: 'localhost:8080' },
    // Si tocara el filesystem, estos stubs explotan. Es el punto del test.
    existeEntrada: () => assert.fail('el emulador no debe mirar el filesystem'),
    leerArchivo: () => assert.fail('el emulador no debe leer credenciales'),
    modoDeArchivo: () => assert.fail('el emulador no debe stat-ear credenciales'),
    home: HOME,
  });

  assert.strictEqual(ctx.modo, 'emulador');
  assert.strictEqual(ctx.produccion, false);
  assert.strictEqual(ctx.projectId, 'treino-dev');
});

test('el emulador manda aunque TREINO_SA_KEY esté seteada y sea basura', () => {
  const ctx = resolverContexto({
    env: {
      FIRESTORE_EMULATOR_HOST: 'localhost:8080',
      [VAR_RUTA]: '/no/existe/ni/de/casualidad.json',
    },
    existeEntrada: fsFalso(),
    home: HOME,
  });

  assert.strictEqual(ctx.modo, 'emulador');
});

// ── 4. La identidad EFECTIVA, no el project id ─────────────────────────────

test('proyectoDeLaIdentidad parsea las dos formas que emite Google', () => {
  assert.strictEqual(
    proyectoDeLaIdentidad('firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com'),
    'treino-dev',
  );
  assert.strictEqual(
    proyectoDeLaIdentidad('treino-dev@appspot.gserviceaccount.com'),
    'treino-dev',
  );
  // Sin proyecto deducible: la SA de Compute por defecto.
  assert.strictEqual(
    proyectoDeLaIdentidad('123456789-compute@developer.gserviceaccount.com'),
    null,
  );
  assert.strictEqual(proyectoDeLaIdentidad(undefined), null);
});

test('una SA de treino-dev es producción AUNQUE el project id diga otra cosa', () => {
  // El agujero de #843: `firebase use` mete `activeProjects` en
  // ~/.config/configstore/firebase-tools.json, le gana al default de
  // .firebaserc, y no deja rastro en el repo. Mirando el proyecto declarado
  // esto pasaría por sandbox. Mirando la identidad, no.
  const veredicto = evaluarProduccion(
    credencialDe('firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com', 'sandbox-inventado'),
  );

  assert.strictEqual(veredicto.produccion, true);
  assert.strictEqual(veredicto.proyectoDeLaIdentidad, 'treino-dev');
  assert.match(veredicto.motivo, /treino-dev/);
  assert.match(veredicto.motivo, /NO manda/);
});

test('el projectIdDeclarado explícito tampoco puede tapar la identidad', () => {
  const veredicto = evaluarProduccion(
    credencialDe('firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com', 'treino-dev'),
    { projectIdDeclarado: 'un-proyecto-cualquiera' },
  );

  assert.strictEqual(veredicto.produccion, true);
});

test('el project id de producción también alcanza, aunque la identidad no lo diga', () => {
  // La sospecha sólo SUMA: una SA de Compute apuntada a treino-dev sigue
  // siendo producción.
  const veredicto = evaluarProduccion(
    credencialDe('123456789-compute@developer.gserviceaccount.com', 'treino-dev'),
  );

  assert.strictEqual(veredicto.produccion, true);
  assert.strictEqual(veredicto.proyectoDeLaIdentidad, null);
});

test('treino-prod también es producción', () => {
  assert.strictEqual(
    evaluarProduccion(
      credencialDe('firebase-adminsdk-x@treino-prod.iam.gserviceaccount.com', 'treino-prod'),
    ).produccion,
    true,
  );
});

test('una SA de un proyecto ajeno no es producción', () => {
  const veredicto = evaluarProduccion(
    credencialDe('firebase-adminsdk-x@otro-proyecto.iam.gserviceaccount.com', 'otro-proyecto'),
  );

  assert.strictEqual(veredicto.produccion, false);
  assert.strictEqual(veredicto.motivo, null);
});

test('resolverContexto marca producción leyendo la credencial de verdad', () => {
  const cred = credencialDe(
    'firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com',
    'sandbox-inventado',
  );

  const ctx = resolverContexto({
    env: { [VAR_RUTA]: FUERA },
    existeEntrada: fsFalso(FUERA),
    leerArchivo: () => JSON.stringify(cred),
    modoDeArchivo: () => 0o100600,
    home: HOME,
  });

  assert.strictEqual(ctx.modo, 'credencial');
  assert.strictEqual(ctx.produccion, true);
  assert.strictEqual(ctx.ruta, FUERA);
  assert.deepStrictEqual(ctx.avisos, []);
});

// ── Permisos y credenciales rotas ──────────────────────────────────────────

test('permisosDemasiadoAbiertos separa 600 de 644 y 640', () => {
  assert.strictEqual(permisosDemasiadoAbiertos(0o100600), false);
  assert.strictEqual(permisosDemasiadoAbiertos(0o100400), false);
  assert.strictEqual(permisosDemasiadoAbiertos(0o100644), true); // lo que había
  assert.strictEqual(permisosDemasiadoAbiertos(0o100640), true);
  assert.strictEqual(permisosDemasiadoAbiertos(null), false);
});

test('644 avisa con el chmod exacto, pero no frena', () => {
  const { avisos } = cargarCredencial({
    env: { [VAR_RUTA]: FUERA },
    existeEntrada: fsFalso(FUERA),
    leerArchivo: () =>
      JSON.stringify(credencialDe('firebase-adminsdk-x@otro.iam.gserviceaccount.com', 'otro')),
    modoDeArchivo: () => 0o100644,
    home: HOME,
  });

  assert.strictEqual(avisos.length, 1);
  assert.match(avisos[0], /chmod 600/);
  assert.match(avisos[0], /644/);
});

test('un JSON roto falla como ILEGIBLE y no como MODULE_NOT_FOUND', () => {
  const err = capturar(() =>
    cargarCredencial({
      env: { [VAR_RUTA]: FUERA },
      existeEntrada: fsFalso(FUERA),
      leerArchivo: () => '{ esto no es json',
      modoDeArchivo: () => 0o100600,
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'ILEGIBLE');
});

test('sin client_email se frena: no hay identidad que verificar', () => {
  const err = capturar(() =>
    cargarCredencial({
      env: { [VAR_RUTA]: FUERA },
      existeEntrada: fsFalso(FUERA),
      leerArchivo: () => JSON.stringify({ type: 'service_account', project_id: 'treino-dev' }),
      modoDeArchivo: () => 0o100600,
      home: HOME,
    }),
  );

  assert.strictEqual(err.codigo, 'SIN_CLIENT_EMAIL');
});
