/**
 * test/fixtures/esm_stub_hooks.mjs
 *
 * La mitad ESM de `stub_firebase_admin.js`, en su propio archivo porque
 * `module.register()` EXIGE que los hooks vivan en un módulo aparte: los corre
 * en otro hilo.
 *
 * ─── Por qué `register()` y no `registerHooks()` (#846) ─────────────────────
 *
 * La primera versión de esta intercepción usaba `module.registerHooks()`, que
 * es síncrono y en el mismo hilo. Anda — en Node 22.15+. **El job
 * `scripts-test` de CI corre Node 20**, donde `registerHooks` no existe, y ahí
 * el preload moría con `TypeError: registerHooks is not a function`.
 *
 * Lo grave no era el rojo. Era que sin el hook el subproceso carga el
 * `firebase-admin` REAL, y los 42 tests de la compuerta pasan a medir NADA:
 * sus casos negativos prueban la AUSENCIA de `STUB_FIRESTORE_REACHED`, y ese
 * marcador también falta cuando el stub nunca se aplicó. Verde en Node 22,
 * decorativo en CI.
 *
 * `module.register()` existe desde Node 20.6 y sigue en 22 y 26 — o sea que es
 * el mismo camino en todas las versiones que corren esta suite, en vez de uno
 * que se degrada según dónde estés parado.
 *
 * Los hooks corren en un hilo aparte, pero el `source` que devuelve `load` se
 * COMPILA Y EVALÚA en el hilo principal. Por eso el módulo sintético puede
 * agarrar por `globalThis` el mismo `adminStub` que ve el lado CJS: un `.mjs`
 * mezcla los dos caminos (`createRequire` para `lib/`, `import` para
 * `firebase-admin`) y los dos tienen que contar la misma historia.
 *
 * ─── El marcador de intercepción es obligatorio ─────────────────────────────
 *
 * El módulo sintético anuncia `STUB_ESM_INTERCEPTED` por stderr apenas se
 * evalúa. Es la PRUEBA POSITIVA de que el import se interceptó: sin él, un
 * test que sólo mira "no apareció `STUB_FIRESTORE_REACHED`" no distingue "la
 * compuerta frenó" de "el stub no existió". Los tests lo exigen en cada
 * corrida, así que si esta intercepción se rompe de nuevo la suite GRITA en vez
 * de degradarse a verde vacío.
 */

import { createRequire } from 'node:module';

/**
 * Los NOMBRES que exporta cada subpath modelado. Se leen acá, en el hilo de los
 * hooks, porque un módulo ESM **no puede tener exports nombrados dinámicos**:
 * el identificador tiene que estar en el código que se compila.
 *
 * `firebase_admin_subpaths.js` es data pura y sin efectos justamente para poder
 * requerirlo desde este hilo sin re-ejecutar el preload. El OBJETO, en cambio,
 * sigue viniendo del hilo principal por `globalThis` — nombres de un lado,
 * instancia del otro, una sola fuente para cada cosa. Ver el encabezado de ese
 * archivo.
 */
const require = createRequire(import.meta.url);
const NOMBRES_POR_SUBPATH = require('./firebase_admin_subpaths.js').nombresDeSubpaths();

export const URL_ADMIN_STUB = 'stub:firebase-admin';

/** `stub:firebase-admin/firestore`, `stub:firebase-admin/app`, … */
const PREFIJO_SUBPATH = 'stub:firebase-admin/';

/**
 * El módulo sintético. Si el preload CJS no corrió, no hay stub que devolver:
 * tira en vez de exportar `undefined`, que sería la misma degradación
 * silenciosa con otro disfraz.
 */
const FUENTE_ADMIN_STUB = `
const stub = globalThis.__STUB_FIREBASE_ADMIN__;
if (!stub) {
  throw new Error(
    'STUB_ESM_SIN_PRELOAD: se interceptó el import de firebase-admin pero no hay ' +
      'stub en globalThis. ¿Corriste el script sin --require fixtures/stub_firebase_admin.js?',
  );
}
process.stderr.write('STUB_ESM_INTERCEPTED\\n');
export default stub;
`;

/**
 * El módulo sintético de un subpath modular.
 *
 * El objeto sale de `globalThis` —o sea, del hilo principal, la MISMA instancia
 * que ve el lado CJS— y los `export const` se generan con los nombres que trae
 * `firebase_admin_subpaths.js`. `__STUB_FIREBASE_ADMIN_SUBPATH__` ya emite
 * `STUB_SUBPATH_INTERCEPTED` por stderr, así que la prueba positiva vale para
 * los dos caminos sin duplicar nada.
 *
 * Un subpath que el doble intercepta pero no modela no tiene nombres, así que
 * un `import { getAuth } from 'firebase-admin/auth'` falla al LINKEAR, antes de
 * evaluar. Es ruidoso, que es lo único que se le pide: el modo de falla que hay
 * que impedir es el silencioso, no el feo.
 */
function fuenteDeSubpath(subpath) {
  const nombres = NOMBRES_POR_SUBPATH[subpath] || [];
  return `
const puerta = globalThis.__STUB_FIREBASE_ADMIN_SUBPATH__;
if (!puerta) {
  throw new Error(
    'STUB_ESM_SIN_PRELOAD: se interceptó el import de ${subpath} pero no hay stub en ' +
      'globalThis. ¿Corriste el script sin --require fixtures/stub_firebase_admin.js?',
  );
}
const mod = puerta(${JSON.stringify(subpath)});
export default mod;
${nombres.map((n) => `export const ${n} = mod.${n};`).join('\n')}
`;
}

export function resolve(specifier, context, nextResolve) {
  if (specifier === 'firebase-admin') {
    return { url: URL_ADMIN_STUB, shortCircuit: true };
  }
  // Misma regla que el lado CJS: TODO `firebase-admin/<algo>`, sin allowlist.
  // El specifier exacto era el agujero — ver el bloque de los subpaths en
  // `stub_firebase_admin.js`.
  if (specifier.startsWith('firebase-admin/')) {
    return { url: `stub:${specifier}`, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}

export function load(url, context, nextLoad) {
  if (url === URL_ADMIN_STUB) {
    return { format: 'module', shortCircuit: true, source: FUENTE_ADMIN_STUB };
  }
  if (url.startsWith(PREFIJO_SUBPATH)) {
    const subpath = url.slice('stub:'.length);
    return { format: 'module', shortCircuit: true, source: fuenteDeSubpath(subpath) };
  }
  return nextLoad(url, context);
}
