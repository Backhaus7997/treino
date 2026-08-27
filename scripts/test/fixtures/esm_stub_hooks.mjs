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

export const URL_ADMIN_STUB = 'stub:firebase-admin';

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

export function resolve(specifier, context, nextResolve) {
  if (specifier === 'firebase-admin') {
    return { url: URL_ADMIN_STUB, shortCircuit: true };
  }
  return nextResolve(specifier, context);
}

export function load(url, context, nextLoad) {
  if (url === URL_ADMIN_STUB) {
    return { format: 'module', shortCircuit: true, source: FUENTE_ADMIN_STUB };
  }
  return nextLoad(url, context);
}
