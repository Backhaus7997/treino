/**
 * lib/dedupe_setlogs_plan.js
 *
 * La DECISIÓN de `backfill_dedupe_setlogs.js`, sin Firestore.
 *
 * Por qué existe aparte: ese script BORRA DATOS DE PRODUCCIÓN y no tenía ni un
 * test —ni siquiera sobre emulador—. Era el riesgo vivo más grande del ciclo,
 * más que los 24 documentos que viene a limpiar: un error acá no ensucia la
 * base, la destruye, y las salvaguardas que lo evitan son justo la parte sutil
 * (ver la trampa de la RENUMERACIÓN, que resucitaría una serie borrada y haría
 * desaparecer una real).
 *
 * Lo caro de testear era el I/O, no la decisión. Separados, la decisión —que es
 * donde vive todo el riesgo— se mide en milisegundos y sin emulador, y el
 * script queda con lo único que no se puede evitar: leer, respaldar y escribir.
 *
 * Es el MISMO principio que `ios/TreinoWatch Watch App/ExerciseCursor.swift` y
 * `SetLogIdentity.swift` del lado del reloj: la regla pura afuera, medida en el
 * host.
 *
 * ⚠️ La conducta acá es la que el script YA tenía, movida sin cambiarla. Los
 * tests fijan lo que hace hoy; si algo de esto está mal, se arregla con el test
 * en rojo primero.
 *
 * ⚠️ HUECO CONOCIDO, MEDIDO AL ESCRIBIR LOS TESTS — decidir antes de `--apply`.
 *
 * La salvaguarda 1 NO cubre el ejemplo que ella misma documenta cuando las
 * series son idénticas: el reloj no renumera sus sombras, así que los ids
 * determinísticos siguen coincidiendo con su `setNumber` y la numeración queda
 * densa. Ahí se borra la serie real renumerada y sobrevive la que el atleta
 * borró. Ver el test `⚠️ renumeración CON series idénticas` en
 * `scripts/test/dedupe_setlogs_plan.test.js`, que lo deja fijado con números.
 *
 * Desde el estado final de los documentos ese caso es indistinguible de uno
 * legítimo, así que cerrarlo pide una señal nueva (`completedAt`) y es una
 * decisión de política, no un bugfix.
 */

/** La identidad lógica de una serie. La misma clave que usan los dos clientes. */
const claveLogica = (data) => `${data.exerciseId}__${data.setNumber}`;

/** Σ reps × kilos — la MISMA fórmula que `SessionState.totalVolumeKg`,
 *  `_sumVolume` de Home y `WorkoutCoordinator.totalVolume` del reloj. */
const volumen = (docs) =>
  docs.reduce((sum, d) => sum + (d.reps ?? 0) * (d.weightKg ?? 0), 0);

/** Si dos documentos de la misma serie dicen cosas distintas.
 *  Compara SOLO lo que cargó el atleta. `completedAt` difiere por definición
 *  (son dos escrituras) y `exerciseName` es un string de display. */
const enConflicto = (a, b) => (a.reps ?? 0) !== (b.reps ?? 0) ||
  (a.weightKg ?? 0) !== (b.weightKg ?? 0) ||
  (a.rpe ?? null) !== (b.rpe ?? null);

/**
 * Serializa un doc para el respaldo con los Timestamp marcados.
 *
 * El contrato con `restore_dedupe_setlogs.js:72` es la marca `__timestamp__`:
 * reponer un `{_seconds,_nanoseconds}` crudo dejaría la serie ILEGIBLE para la
 * app. Por eso se testea — es la diferencia entre poder deshacer y no poder.
 *
 * @param data      los campos del documento.
 * @param aFecha    cómo reconocer un Timestamp: devuelve el `Date` si lo es, y
 *                  algo falsy si no. Se inyecta para no arrastrar
 *                  `firebase-admin` hasta acá.
 */
const paraRespaldo = (data, aFecha) => {
  const out = {};
  for (const [k, val] of Object.entries(data)) {
    const fecha = aFecha(val);
    out[k] = fecha ? { __timestamp__: fecha.toISOString() } : val;
  }
  return out;
};

/**
 * Qué hacer con UNA sesión.
 *
 * @param docs  las series, ya normalizadas a
 *              `{ id, data, createTimeMs }`. `createTimeMs` decide quién
 *              sobrevive: gana el MÁS VIEJO.
 * @param volumenGuardado  el `totalVolumeKg` que tiene la sesión hoy.
 *
 * @returns uno de:
 *   - `{ tipo: 'vacia' }`                       — sin series, no hay nada que ver.
 *   - `{ tipo: 'salteada', motivo, detalle }`   — necesita mirada humana.
 *   - `{ tipo: 'sana' }`                        — sin duplicados y con el volumen bien.
 *   - `{ tipo: 'desajuste-sin-duplicados', volumenGuardado, volumenReal }`
 *                                               — se REPORTA y no se toca (salvaguarda 4).
 *   - `{ tipo: 'limpiar', borrar, sobrevivientes, volumenGuardado, volumenReal,
 *        volumenDifiere }`
 */
function planSesion(docs, volumenGuardado) {
  if (docs.length === 0) return { tipo: 'vacia' };

  // ── Salvaguarda 3: documentos malformados ──────────────────────────────
  // Sin `exerciseId` o sin `setNumber` no hay identidad lógica que comparar;
  // agruparlos por una clave `undefined` juntaría series de EJERCICIOS
  // DISTINTOS. Se saltea la sesión entera.
  const malformado = docs.find(({ data }) =>
    typeof data.exerciseId !== 'string' || !data.exerciseId ||
    typeof data.setNumber !== 'number');
  if (malformado) {
    return {
      tipo: 'salteada',
      motivo: 'documento sin exerciseId/setNumber',
      detalle: malformado.id,
    };
  }

  // ── Salvaguarda 1: evidencia de renumeración ───────────────────────────
  //
  // ES LA QUE HUBIERA DESTRUIDO DATOS. `SessionNotifier.removeSet` renumera
  // solo los sobrevivientes que están en su estado, y ese estado ya pasó por
  // `_dedupedLogs` — o sea que los documentos SOMBRA nunca se renumeran y
  // quedan con el número viejo.
  //
  // Ejemplo real: el reloj escribe W1(1) W2(2) W3(3) y el teléfono P1 P2 P3
  // duplicados; el atleta borra la serie 2 desde el celular y queda
  // W1(1) P1(1) W2(2) W3(3) P3(2). Agrupando por campos, la clave `__2` junta
  // W2 —la serie BORRADA— con P3 —la serie 3 real renumerada—, y como W2 es
  // más viejo sobreviviría W2 y se borraría P3: la serie que el atleta borró
  // vuelve al historial y la real desaparece, con el volumen subiendo.
  // `enConflicto` no lo ve cuando las series son iguales, que es lo normal.
  const renumerados = [];
  const porEjercicio = new Map();
  for (const { id, data } of docs) {
    const m = /^(.*)__(\d+)$/.exec(id);
    if (m && Number(m[2]) !== data.setNumber) {
      renumerados.push(`${id} tiene setNumber=${data.setNumber}`);
    }
    if (!porEjercicio.has(data.exerciseId)) {
      porEjercicio.set(data.exerciseId, new Set());
    }
    porEjercicio.get(data.exerciseId).add(data.setNumber);
  }
  const noDenso = [];
  for (const [ex, nums] of porEjercicio) {
    const orden = [...nums].sort((a, b) => a - b);
    const esperado = Array.from({ length: orden.length }, (_, i) => i + 1);
    if (orden.join(',') !== esperado.join(',')) noDenso.push(`${ex}:[${orden}]`);
  }
  if (renumerados.length > 0 || noDenso.length > 0) {
    return {
      tipo: 'salteada',
      motivo: 'evidencia de renumeración',
      detalle: [...renumerados, ...noDenso].join(' | '),
    };
  }

  // ── Agrupar por identidad lógica ───────────────────────────────────────
  const porClave = new Map();
  for (const d of docs) {
    const k = claveLogica(d.data);
    if (!porClave.has(k)) porClave.set(k, []);
    porClave.get(k).push(d);
  }
  // Gana el MÁS VIEJO: es el que escribió el cliente que llegó primero.
  for (const grupo of porClave.values()) {
    grupo.sort((a, b) => a.createTimeMs - b.createTimeMs);
  }

  // ── Salvaguarda 2: conflictos ──────────────────────────────────────────
  // Si dos documentos de la misma serie lógica traen reps, kilos o RPE
  // distintos, uno es una corrección del atleta y borrar el equivocado la
  // pierde. Se saltea la sesión entera.
  let conflicto = null;
  for (const [k, grupo] of porClave) {
    if (grupo.length < 2) continue;
    const base = grupo[0].data;
    for (const otro of grupo.slice(1)) {
      if (enConflicto(base, otro.data)) {
        conflicto = `${k}: ` + grupo
          .map((g) => `${g.id}(${g.data.reps}×${g.data.weightKg}kg` +
            `${g.data.rpe != null ? ` rpe${g.data.rpe}` : ''})`)
          .join(' vs ');
      }
    }
  }
  if (conflicto) {
    return {
      tipo: 'salteada',
      motivo: 'reps/kilos/RPE distintos',
      detalle: conflicto,
    };
  }

  const borrar = [];
  const sobrevivientes = [];
  for (const grupo of porClave.values()) {
    sobrevivientes.push(grupo[0]);
    borrar.push(...grupo.slice(1));
  }

  const volumenReal = volumen(sobrevivientes.map((d) => d.data));
  const volumenDifiere = Math.abs(volumenReal - volumenGuardado) > 0.001;

  // ── Salvaguarda 4: sin duplicados no se toca el volumen ────────────────
  // Un desajuste sin duplicados tiene otras causas —una sesión abandonada, un
  // cierre viejo— y recalcularlo sería otra migración, mucho más invasiva.
  if (borrar.length === 0) {
    return volumenDifiere
      ? { tipo: 'desajuste-sin-duplicados', volumenGuardado, volumenReal }
      : { tipo: 'sana' };
  }

  return {
    tipo: 'limpiar',
    borrar,
    sobrevivientes,
    volumenGuardado,
    volumenReal,
    volumenDifiere,
  };
}

module.exports = {
  claveLogica,
  volumen,
  enConflicto,
  paraRespaldo,
  planSesion,
};
