/**
 * test/dedupe_setlogs_plan.test.js
 *
 * Los tests de la decisión de `backfill_dedupe_setlogs.js`.
 *
 *   node --test scripts/test/
 *
 * Por qué importan más que la mayoría: ese script BORRA DATOS DE PRODUCCIÓN.
 * Un error acá no ensucia la base, la destruye — y las salvaguardas que lo
 * evitan son la parte sutil, no el I/O.
 *
 * `node:test` y `node:assert`, sin dependencias nuevas: `scripts/` solo tiene
 * `firebase-admin`, y sumarle un runner por esto sería más de lo que hace falta.
 */

const test = require('node:test');
const assert = require('node:assert');

const {
  volumen,
  enConflicto,
  paraRespaldo,
  planSesion,
} = require('../lib/dedupe_setlogs_plan');

// ── Utilidades ────────────────────────────────────────────────────────────
//
// `createTimeMs` decide quién sobrevive: gana el MÁS VIEJO. Se pone explícito
// en cada doc para que ningún test dependa del orden del array.

let reloj = 0;
const serie = (id, campos, createTimeMs) => ({
  id,
  data: {
    exerciseId: 'press',
    setNumber: 1,
    reps: 10,
    weightKg: 50,
    ...campos,
  },
  createTimeMs: createTimeMs ?? (reloj += 1000),
});

const ids = (docs) => docs.map((d) => d.id);

// ── Los casos que NO se tocan ─────────────────────────────────────────────

test('una sesión sin series no es nada', () => {
  assert.deepStrictEqual(planSesion([], 0), { tipo: 'vacia' });
});

test('una sesión sana no se toca: idempotencia', () => {
  const docs = [
    serie('press__1', { setNumber: 1, weightKg: 50 }, 100),
    serie('press__2', { setNumber: 2, weightKg: 60 }, 200),
    serie('press__3', { setNumber: 3, weightKg: 70 }, 300),
  ];
  // 10×50 + 10×60 + 10×70 = 1800
  assert.deepStrictEqual(planSesion(docs, 1800), { tipo: 'sana' });
});

test('el volumen desajustado SIN duplicados se reporta y no se toca', () => {
  const docs = [
    serie('press__1', { setNumber: 1 }, 100),
    serie('press__2', { setNumber: 2 }, 200),
  ];
  const plan = planSesion(docs, 999);

  assert.strictEqual(plan.tipo, 'desajuste-sin-duplicados');
  assert.strictEqual(plan.volumenGuardado, 999);
  assert.strictEqual(plan.volumenReal, 1000);
  // Salvaguarda 4: tiene otras causas —sesión abandonada, cierre viejo— y
  // recalcularlo sería otra migración. Se mira, no se escribe.
  assert.strictEqual(plan.borrar, undefined);
});

// ── El caso para el que existe el script ──────────────────────────────────

test('duplicados cruzados: sobrevive el MÁS VIEJO y se recalcula el volumen', () => {
  // El teléfono escribió primero, con ids autogenerados; el reloj reintentó
  // después con los suyos determinísticos. Ninguno pudo deduplicar al otro.
  const docs = [
    serie('press__1', { setNumber: 1, weightKg: 50 }, 2000),
    serie('auto-aaa', { setNumber: 1, weightKg: 50 }, 1000),
    serie('press__2', { setNumber: 2, weightKg: 60 }, 2100),
    serie('auto-bbb', { setNumber: 2, weightKg: 60 }, 1100),
  ];
  // El campo dice 2200 porque lo escribió un cliente desde SU estado local:
  // el desajuste es la premisa del script, no una casualidad.
  const plan = planSesion(docs, 2200);

  assert.strictEqual(plan.tipo, 'limpiar');
  assert.deepStrictEqual(ids(plan.borrar).sort(), ['press__1', 'press__2']);
  assert.deepStrictEqual(ids(plan.sobrevivientes).sort(), ['auto-aaa', 'auto-bbb']);
  assert.strictEqual(plan.volumenReal, 1100); // 10×50 + 10×60
  assert.strictEqual(plan.volumenDifiere, true);
});

test('el orden de entrada no decide quién sobrevive: decide createTime', () => {
  const viejoPrimero = planSesion([
    serie('el-viejo', { setNumber: 1 }, 100),
    serie('el-nuevo', { setNumber: 1 }, 900),
  ], 0);
  const nuevoPrimero = planSesion([
    serie('el-nuevo', { setNumber: 1 }, 900),
    serie('el-viejo', { setNumber: 1 }, 100),
  ], 0);

  assert.deepStrictEqual(ids(viejoPrimero.borrar), ['el-nuevo']);
  assert.deepStrictEqual(ids(nuevoPrimero.borrar), ['el-nuevo']);
});

test('aplicar el plan deja una sesión sana: correrlo dos veces no escribe', () => {
  const docs = [
    serie('press__1', { setNumber: 1 }, 2000),
    serie('auto-aaa', { setNumber: 1 }, 1000),
  ];
  const primera = planSesion(docs, 777);
  assert.strictEqual(primera.tipo, 'limpiar');

  // Lo que quedaría en Firestore después de aplicar: los sobrevivientes y el
  // volumen recalculado.
  const segunda = planSesion(primera.sobrevivientes, primera.volumenReal);
  assert.deepStrictEqual(segunda, { tipo: 'sana' });
});

// ── Salvaguarda 2: conflictos ─────────────────────────────────────────────

test('reps/kilos/RPE distintos saltean la sesión entera', () => {
  for (const [campo, valor] of [['reps', 8], ['weightKg', 60], ['rpe', 9]]) {
    const plan = planSesion([
      serie('press__1', { setNumber: 1 }, 100),
      serie('auto-aaa', { setNumber: 1, [campo]: valor }, 200),
    ], 0);

    assert.strictEqual(plan.tipo, 'salteada', `${campo} distinto tiene que saltear`);
    assert.strictEqual(plan.motivo, 'reps/kilos/RPE distintos');
  }
});

test('completedAt y exerciseName distintos NO son conflicto', () => {
  // Difieren por definición: son dos escrituras, y el nombre es display.
  const plan = planSesion([
    serie('press__1', { setNumber: 1, completedAt: 'A', exerciseName: 'Press' }, 100),
    serie('auto-aaa', { setNumber: 1, completedAt: 'B', exerciseName: 'press banca' }, 200),
  ], 0);

  assert.strictEqual(plan.tipo, 'limpiar');
});

// ── Salvaguarda 3: documentos malformados ─────────────────────────────────

test('un documento sin exerciseId saltea la sesión entera', () => {
  const plan = planSesion([
    serie('press__1', { setNumber: 1 }, 100),
    { id: 'roto', data: { setNumber: 1, reps: 10, weightKg: 50 }, createTimeMs: 200 },
  ], 0);

  assert.strictEqual(plan.tipo, 'salteada');
  assert.strictEqual(plan.motivo, 'documento sin exerciseId/setNumber');
  assert.strictEqual(plan.detalle, 'roto');
});

test('un setNumber que no es número saltea la sesión entera', () => {
  // Sin identidad lógica comparable, agrupar por una clave `undefined`
  // juntaría series de EJERCICIOS DISTINTOS.
  const plan = planSesion([
    serie('raro', { setNumber: '1' }, 100),
  ], 0);

  assert.strictEqual(plan.tipo, 'salteada');
  assert.strictEqual(plan.motivo, 'documento sin exerciseId/setNumber');
});

// ── Salvaguarda 1: renumeración ───────────────────────────────────────────
//
// LA QUE HUBIERA DESTRUIDO DATOS. Ver el bloque de `planSesion`.

test('un id determinístico que ya no coincide con su setNumber saltea', () => {
  // El teléfono borró una serie y renumeró los sobrevivientes, incluido un
  // documento que había escrito el reloj: `press__3` quedó con setNumber 2.
  const plan = planSesion([
    serie('press__1', { setNumber: 1 }, 100),
    serie('press__3', { setNumber: 2 }, 300),
  ], 0);

  assert.strictEqual(plan.tipo, 'salteada');
  assert.strictEqual(plan.motivo, 'evidencia de renumeración');
  assert.match(plan.detalle, /press__3 tiene setNumber=2/);
});

test('una numeración con huecos saltea: 1,3 sin el 2', () => {
  const plan = planSesion([
    serie('auto-a', { setNumber: 1 }, 100),
    serie('auto-b', { setNumber: 3 }, 300),
  ], 0);

  assert.strictEqual(plan.tipo, 'salteada');
  assert.strictEqual(plan.motivo, 'evidencia de renumeración');
  assert.match(plan.detalle, /press:\[1,3\]/);
});

test('la numeración se evalúa POR EJERCICIO, no sobre la sesión entera', () => {
  // Dos ejercicios de dos series cada uno es denso en los dos. Mirándolo junto
  // —1,2,1,2— parecería roto y saltearía sesiones sanas.
  const plan = planSesion([
    serie('press__1', { exerciseId: 'press', setNumber: 1 }, 100),
    serie('press__2', { exerciseId: 'press', setNumber: 2 }, 200),
    serie('remo__1', { exerciseId: 'remo', setNumber: 1 }, 300),
    serie('remo__2', { exerciseId: 'remo', setNumber: 2 }, 400),
  ], 2000);

  assert.deepStrictEqual(plan, { tipo: 'sana' });
});

// ⚠️ HUECO MEDIDO, NO TEÓRICO — leer antes de correr el script con `--apply`.
//
// El comentario de la salvaguarda 1 dice que se saltea "cualquier sesión con
// evidencia de renumeración", y da este ejemplo textual: el reloj escribe
// W1(1) W2(2) W3(3), el teléfono duplica P1 P2 P3, el atleta borra la serie 2
// desde el celular y queda W1(1) P1(1) W2(2) W3(3) P3(2).
//
// En ese estado NINGUNA salvaguarda dispara:
//   - `renumerados` no ve nada: el reloj NUNCA renumera sus sombras, así que
//     `press__2` sigue con setNumber=2 y `press__3` con 3. Los ids del teléfono
//     son autogenerados y ni siquiera matchean el regex.
//   - `noDenso` no ve nada: la unión de setNumbers es {1,2,3}, densa.
//   - `enConflicto` no ve nada cuando las series son iguales — que es, textual,
//     "lo normal".
//
// Y el daño es exactamente el que el comentario dice evitar: se borra `auto-p3`
// —la serie 3 REAL, renumerada a 2— y sobrevive `press__2`, que es la serie que
// el atleta BORRÓ. El volumen sube de 1000 (las 2 series de verdad) a 1500.
//
// La salvaguarda 1 SÍ cubre la otra forma de renumeración (cuando el que se
// renumera es un documento de id determinístico), y la 2 cubre el caso de
// valores distintos. Este cruce —renumeración CON series idénticas— queda
// afuera de las dos.
//
// No se "arregla" acá: desde el estado final de los documentos esta sesión es
// INDISTINGUIBLE de una legítima donde el reloj escribió 4 series y el teléfono
// 3 (el caso real ZTjx8jVA6Ru5vCVLLy5x de más abajo, que es la mayor parte del
// valor del script). Cerrarlo pide una señal nueva —`completedAt`, que en un
// duplicado real difiere 1-6 segundos y acá difiere lo que tardó una serie— y
// eso es una decisión de política sobre un script que borra producción.
//
// Este test fija la conducta ACTUAL. Si alguien agrega la salvaguarda, se pone
// rojo y hay que actualizarlo a `salteada` — que es justo lo que se quiere.
test('⚠️ renumeración CON series idénticas: hoy NO se saltea, y resucita la serie borrada', () => {
  const plan = planSesion([
    serie('press__1', { setNumber: 1, weightKg: 50 }, 100),
    serie('auto-p1', { setNumber: 1, weightKg: 50 }, 110),
    serie('press__2', { setNumber: 2, weightKg: 50 }, 200),
    serie('press__3', { setNumber: 3, weightKg: 50 }, 300),
    serie('auto-p3', { setNumber: 2, weightKg: 50 }, 310),
  ], 1000);

  assert.strictEqual(plan.tipo, 'limpiar');
  // Se borra la serie 3 REAL del teléfono, no una copia.
  assert.deepStrictEqual(ids(plan.borrar), ['auto-p1', 'auto-p3']);
  // Y sobrevive `press__2`, la que el atleta borró.
  assert.ok(ids(plan.sobrevivientes).includes('press__2'));
  // El volumen sube: 3 series donde el atleta hizo 2.
  assert.strictEqual(plan.volumenGuardado, 1000);
  assert.strictEqual(plan.volumenReal, 1500);
});

test('la misma renumeración con pesos distintos SÍ se saltea, por conflicto', () => {
  // Es lo que salva el caso en la práctica cuando las series no son iguales:
  // la clave `__2` junta la serie 2 borrada (60kg) con la 3 real (70kg).
  const plan = planSesion([
    serie('press__1', { setNumber: 1, weightKg: 50 }, 100),
    serie('auto-p1', { setNumber: 1, weightKg: 50 }, 110),
    serie('press__2', { setNumber: 2, weightKg: 60 }, 200),
    serie('press__3', { setNumber: 3, weightKg: 70 }, 300),
    serie('auto-p3', { setNumber: 2, weightKg: 70 }, 310),
  ], 1000);

  assert.strictEqual(plan.tipo, 'salteada');
  assert.strictEqual(plan.motivo, 'reps/kilos/RPE distintos');
});

test('los duplicados no rompen la densidad: el set colapsa los repetidos', () => {
  const plan = planSesion([
    serie('press__1', { setNumber: 1 }, 200),
    serie('auto-a', { setNumber: 1 }, 100),
    serie('press__2', { setNumber: 2 }, 210),
    serie('auto-b', { setNumber: 2 }, 110),
  ], 0);

  assert.strictEqual(plan.tipo, 'limpiar');
});

// ── El caso real medido ───────────────────────────────────────────────────

test('la sesión ZTjx8jVA6Ru5vCVLLy5x: 3850 en documentos, 2200 reales, 1650 en el campo', () => {
  // Medida el 2026-08-12 en el emulador. El teléfono cerró con SUS 3 series sin
  // haber ingerido las 4 del reloj, así que el campo quedó abajo de todo.
  //
  // 4 series lógicas de 10×55 = 2200. El reloj escribió las 4 y el teléfono
  // duplicó 3 → 7 documentos, 3850 sumando todo.
  const docs = [
    serie('press__1', { setNumber: 1, weightKg: 55 }, 100),
    serie('press__2', { setNumber: 2, weightKg: 55 }, 200),
    serie('press__3', { setNumber: 3, weightKg: 55 }, 300),
    serie('press__4', { setNumber: 4, weightKg: 55 }, 400),
    serie('auto-a', { setNumber: 1, weightKg: 55 }, 500),
    serie('auto-b', { setNumber: 2, weightKg: 55 }, 600),
    serie('auto-c', { setNumber: 3, weightKg: 55 }, 700),
  ];

  assert.strictEqual(volumen(docs.map((d) => d.data)), 3850);

  const plan = planSesion(docs, 1650);
  assert.strictEqual(plan.tipo, 'limpiar');
  assert.strictEqual(plan.borrar.length, 3);
  assert.strictEqual(plan.volumenReal, 2200);
  assert.strictEqual(plan.volumenGuardado, 1650);
  // El campo sube, no baja: borrar documentos NO es lo que arregla los
  // rankings. Lo que leen `ranking-aggregate.ts` e Insights es este número.
  assert.strictEqual(plan.volumenDifiere, true);
});

// ── Las piezas sueltas ────────────────────────────────────────────────────

test('el volumen trata reps y kilos faltantes como cero, no como error', () => {
  // Peso corporal, o un plan sin kilos cargados. No se inventa un peso: mentir
  // el volumen es peor que subestimarlo.
  assert.strictEqual(volumen([{ reps: 10 }]), 0);
  assert.strictEqual(volumen([{ weightKg: 50 }]), 0);
  assert.strictEqual(volumen([{}]), 0);
  assert.strictEqual(volumen([]), 0);
});

test('el desajuste de volumen tolera el ruido de coma flotante', () => {
  const docs = [serie('press__1', { setNumber: 1, weightKg: 0.1 }, 100)];
  // 10 × 0.1 no da exactamente 1 en binario.
  assert.deepStrictEqual(planSesion(docs, 1), { tipo: 'sana' });
});

test('enConflicto trata rpe ausente y rpe nulo como lo mismo', () => {
  assert.strictEqual(enConflicto({ reps: 10, weightKg: 50 }, { reps: 10, weightKg: 50, rpe: null }), false);
  assert.strictEqual(enConflicto({ reps: 10, weightKg: 50 }, { reps: 10, weightKg: 50, rpe: 8 }), true);
});

test('el respaldo marca los Timestamp para que el restore pueda rehidratarlos', () => {
  // El contrato con `restore_dedupe_setlogs.js:72`. Reponer un
  // `{_seconds,_nanoseconds}` crudo dejaría la serie ILEGIBLE para la app: es
  // la diferencia entre poder deshacer y no poder.
  const fecha = new Date('2026-08-13T12:00:00.000Z');
  const marca = { esUnTimestamp: true };
  const aFecha = (v) => (v === marca ? fecha : null);

  const salida = paraRespaldo(
    { exerciseId: 'press', setNumber: 2, weightKg: 55, completedAt: marca },
    aFecha,
  );

  assert.deepStrictEqual(salida, {
    exerciseId: 'press',
    setNumber: 2,
    weightKg: 55,
    completedAt: { __timestamp__: '2026-08-13T12:00:00.000Z' },
  });
});

test('el respaldo no toca los campos que no son Timestamp', () => {
  const salida = paraRespaldo({ a: null, b: 0, c: false, d: '' }, () => null);
  assert.deepStrictEqual(salida, { a: null, b: 0, c: false, d: '' });
});
