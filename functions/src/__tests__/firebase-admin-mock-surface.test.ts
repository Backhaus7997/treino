/**
 * firebase-admin-mock-surface.test.ts
 *
 * EL TRINQUETE DEL MOCK: que ningún test que mockea `firebase-admin` pueda
 * quedarse mirando el SDK REAL por la puerta de al lado.
 *
 * ─── Por qué existe ─────────────────────────────────────────────────────────
 *
 * `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Un módulo de
 * producción que importe `firebase-admin/firestore` NO queda mockeado por eso,
 * y hoy ya pasa: `send-fcm.ts`, `add-alias.ts`, `places-search.ts`,
 * `mail/enqueue-mail.ts` y `mail/send-queued-mail.ts` importan `FieldValue` del
 * subpath mientras sus tests mockean sólo el specifier pelado.
 *
 * Con `FieldValue` es inocuo —es una fábrica pura, no necesita app—. Con
 * `getFirestore()` NO, y ahí está el problema, porque es exactamente lo que va a
 * pasar cuando corra `openspec/changes/firebase-admin-modular/`.
 *
 * ─── El modo de falla, que es un VERDE ──────────────────────────────────────
 *
 * Medido sobre esta suite:
 *
 *   · 39 aserciones por AUSENCIA (`not.toHaveBeenCalled`), 21 de ellas sobre
 *     `sendEachForMulticast` — o sea "no se mandó la notificación".
 *   · Los NUEVE archivos que hacen esa aserción no espían el logger
 *     (`warnSpy` / `errorSpy` / `spyOn(logger…)`: cero hits en los nueve).
 *   · Producción tiene `catch all → log + no rethrow` como política escrita:
 *     `review-aggregate.ts:144`, `link-aggregate.ts:119`,
 *     `template-rating-aggregate.ts:109`, `notify-wear-workout.ts:124`
 *     («Un aviso perdido no puede hacer fallar la escritura de la sesión»).
 *
 * Encadenado: un archivo migrado llama al `getFirestore()` REAL → tira porque no
 * hay app inicializada → el catch-all se lo traga y loguea → nunca se llega al
 * `sendEachForMulticast` → `expect(…).not.toHaveBeenCalled()` PASA.
 *
 * Verde, y no midió nada. Es el mismo punto ciego que en `scripts/` cierra
 * `subpath_stub_interception.test.js`, por otro camino.
 *
 * ─── Qué chequea ────────────────────────────────────────────────────────────
 *
 * Para cada test que mockea `firebase-admin`: recorre el grafo de imports de los
 * módulos de `src/` que ese test carga y junta los subpaths de los que se
 * importa un símbolo peligroso. Si alguno no está mockeado en ese archivo, falla
 * y dice cuál, por qué, y de qué archivo de producción viene.
 *
 * La lista de subpaths NO está escrita a mano: sale del código en cada corrida,
 * igual que en `scripts/test/firebase_admin_superficie.test.js`. Una lista a mano
 * se desactualiza y termina prometiendo una cobertura que no tiene — el patrón
 * del #826.
 *
 * ─── Qué cuenta como peligroso: DOS vectores ──────────────────────────────
 *
 * 1. **Necesita una app** (`SIMBOLOS_QUE_EXIGEN_APP`). Tiran si no hay app
 *    inicializada, y ese throw es el que un catch-all convierte en verde.
 *
 * 2. **El test lo falsea en su propio mock namespaced.** Si se tomó el trabajo
 *    de escribir un `FieldValue` de mentira, le importa; que producción lea el
 *    real es drift, con app o sin app.
 *
 * El vector 2 se agregó DESPUÉS y no por prolijidad: la primera versión de este
 * archivo sólo tenía el 1, argumentando que `FieldValue`/`Timestamp` son
 * fábricas puras. Al migrarlas (PR 3) se rompieron DOS suites
 * —`notify-monthly-report` y `promote-link`— con este gate en verde. Ver el
 * comentario de `cuerpoDelMockNamespaced`.
 *
 * Lo que NO se exige, para que el gate no sea ruido: los símbolos que son sólo
 * TIPOS (`App`, `DocumentData`, `Messaging`…). Se borran al compilar y no
 * pueden driftear. Con la regla estricta serían 24 violaciones en vez de las
 * reales; el ruido en un gate es lo que lleva a que alguien lo silencie.
 *
 * SI ESTE TEST SE PONE ROJO: no lo silencies ni saques el símbolo de la lista.
 * Agregá el `jest.mock("firebase-admin/<sub>", …)` que falta en el test que
 * nombra el error. El rojo es la pregunta "¿tu mock cubre lo que tu código
 * importa de verdad?".
 */

import * as fs from "fs";
import * as path from "path";

const SRC = path.resolve(__dirname, "..");
const TESTS = __dirname;

/**
 * Los que resuelven contra el registro de apps y TIRAN si no hay ninguna. Son el
 * vector: su throw es lo que un catch-all convierte en un verde silencioso.
 *
 * Quedan afuera a propósito `FieldValue`, `Timestamp`, `FieldPath`, `Filter`,
 * `cert` y `applicationDefault`: no tocan el registro y andan sin app.
 */
const SIMBOLOS_QUE_EXIGEN_APP = new Set([
  "getFirestore",
  "getAuth",
  "getStorage",
  "getMessaging",
  "getDatabase",
  "getApp",
]);

/**
 * EL SEGUNDO VECTOR, y lo encontró un test roto, no un razonamiento.
 *
 * La primera versión de este archivo sólo miraba `SIMBOLOS_QUE_EXIGEN_APP`,
 * con el argumento de que `FieldValue` y `Timestamp` son fábricas puras que
 * andan sin app. Eso es cierto y **no alcanza**: al migrar `functions/` a
 * `FieldValue` del subpath (PR 3), DOS suites se rompieron —
 * `notify-monthly-report` y `promote-link`— y este gate estaba verde.
 *
 * El mecanismo: esos tests falsean `firestore.FieldValue` en su propio
 * `jest.mock("firebase-admin", …)` —p. ej. `delete: () => Symbol("…")`— y su
 * Firestore de mentira reconoce ESE sentinel. Cuando producción empieza a
 * importar `FieldValue` del subpath, le llega el REAL, el fake no lo reconoce y
 * guarda el sentinel en vez de aplicarlo. No hace falta ninguna app para eso.
 *
 * O sea que la condición no es "necesita app": es **"el test se tomó el trabajo
 * de falsear este símbolo"**. Si lo falseó, le importa; que producción lea el
 * real es drift, con app o sin app.
 *
 * Se chequean las dos cosas. La de app cubre el símbolo que el test NO falsea
 * pero igual revienta; ésta cubre el que no revienta y miente.
 */
/**
 * Los dobles modulares se escriben con una línea que delega en
 * `helpers/modular-from-namespaced.ts`:
 *
 *     jest.mock("firebase-admin/app", () =>
 *       (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
  ).app());
 *
 * El factory ya no NOMBRA los símbolos, así que mirar su texto no alcanza: el
 * gate tiene que seguir esa indirección un nivel. Si no, el helper —que existe
 * justamente para que los 13 dobles no drifteen— apagaría el trinquete que los
 * vigila, y eso es peor que el problema que resuelve.
 */
const HELPER = "modular-from-namespaced";
const CUERPOS_DEL_HELPER: Record<string, string> = (() => {
  const ruta = path.join(TESTS, "helpers", `${HELPER}.ts`);
  if (!fs.existsSync(ruta)) return {};
  const fuente = fs.readFileSync(ruta, "utf8");
  const out: Record<string, string> = {};
  for (const m of fuente.matchAll(/export function (\w+)\([^)]*\)[^{]*\{([\s\S]*?)\n\}/g)) {
    out[m[1]] = m[2];
  }
  return out;
})();

/** Resuelve el cuerpo real de un mock, siguiendo el helper si delega en él. */
function cuerpoEfectivo(cuerpo: string): string {
  const m = cuerpo.match(new RegExp(`${HELPER}[\\s\\S]*?\\)\\.(\\w+)\\(`));
  if (!m) return cuerpo;
  const delHelper = CUERPOS_DEL_HELPER[m[1]];
  if (delHelper === undefined) {
    throw new Error(
      `El mock delega en ${HELPER}.${m[1]}(), que no existe en el helper. ` +
        "¿Se renombró la función y quedó un test apuntando al nombre viejo?",
    );
  }
  return delHelper;
}
function cuerpoDelMock(codigo: string, specifier: string): string {
  const inicio = codigo.indexOf(`jest.mock("${specifier}"`);
  if (inicio < 0) return "";
  let nivel = 0;
  for (let i = codigo.indexOf("(", inicio); i < codigo.length; i++) {
    if (codigo[i] === "(") nivel++;
    else if (codigo[i] === ")") {
      nivel--;
      if (nivel === 0) return codigo.slice(inicio, i + 1);
    }
  }
  return "";
}

/** `import … from "algo"` / `export … from "algo"`, con lo que se importa. */
const IMPORT = /(?:import|export)\s+([\s\S]*?)\s*from\s*["']([^"']+)["']/g;
/** `jest.mock("algo"` — sólo el specifier. */
const JEST_MOCK = /jest\.mock\(\s*["']([^"']+)["']/g;

function archivosTs(dir: string, dentroDeTests: boolean): string[] {
  const encontrados: string[] = [];
  for (const entrada of fs.readdirSync(dir, { withFileTypes: true })) {
    const completo = path.join(dir, entrada.name);
    if (entrada.isDirectory()) {
      const esTests = completo === TESTS;
      if (esTests !== dentroDeTests && esTests) continue;
      encontrados.push(...archivosTs(completo, dentroDeTests));
    } else if (entrada.name.endsWith(".ts")) {
      const esDeTests = completo.startsWith(TESTS);
      if (esDeTests === dentroDeTests) encontrados.push(completo);
    }
  }
  return encontrados;
}

type Analisis = {
  /** Imports relativos ya resueltos a rutas absolutas de `src/`. */
  relativos: string[];
  /** `{ 'firebase-admin/firestore': ['getFirestore', …] }` */
  subpaths: Record<string, string[]>;
};

function analizar(archivo: string): Analisis {
  const codigo = fs.readFileSync(archivo, "utf8");
  const relativos: string[] = [];
  const subpaths: Record<string, string[]> = {};

  for (const [, clausula, specifier] of codigo.matchAll(IMPORT)) {
    if (specifier.startsWith("firebase-admin/")) {
      const nombres = [...clausula.matchAll(/[A-Za-z_$][\w$]*/g)].map((m) => m[0]);
      subpaths[specifier] = [...(subpaths[specifier] ?? []), ...nombres];
      continue;
    }
    if (!specifier.startsWith(".")) continue;

    const base = path.resolve(path.dirname(archivo), specifier);
    for (const candidato of [`${base}.ts`, path.join(base, "index.ts")]) {
      if (fs.existsSync(candidato)) {
        relativos.push(candidato);
        break;
      }
    }
  }

  return { relativos, subpaths };
}

/** `src/` entero (sin tests), analizado una vez. */
const GRAFO = new Map<string, Analisis>(
  archivosTs(SRC, false).map((archivo) => [archivo, analizar(archivo)]),
);

/**
 * Cierre transitivo: qué subpaths con símbolos que exigen app alcanza un test a
 * través de los módulos de producción que carga.
 *
 * Transitivo y no un nivel: `send-fcm.ts` lo importan nueve tests, casi ninguno
 * directo. Mirar sólo el primer salto dejaría afuera justo los casos que
 * importan.
 */
function subpathsAlcanzados(desde: string[]): Map<string, Map<string, Set<string>>> {
  const alcanzados = new Map<string, Map<string, Set<string>>>();
  const vistos = new Set<string>();
  const pendientes = [...desde];

  while (pendientes.length > 0) {
    const actual = pendientes.pop() as string;
    if (vistos.has(actual)) continue;
    vistos.add(actual);

    const analisis = GRAFO.get(actual);
    if (!analisis) continue;

    for (const [subpath, nombres] of Object.entries(analisis.subpaths)) {
      if (!alcanzados.has(subpath)) alcanzados.set(subpath, new Map());
      const porNombre = alcanzados.get(subpath) as Map<string, Set<string>>;
      for (const nombre of nombres) {
        if (!porNombre.has(nombre)) porNombre.set(nombre, new Set());
        (porNombre.get(nombre) as Set<string>).add(path.relative(SRC, actual));
      }
    }

    pendientes.push(...analisis.relativos);
  }

  return alcanzados;
}

describe("la superficie mockeada de firebase-admin cubre lo que el código importa", () => {
  // El modo de falla que hay que descartar primero: un test que no mide nada y
  // sale verde. Misma lección que el stub ESM del #846.
  it("el escaneo encuentra módulos y tests (si no, esto pasaría en vacío)", () => {
    expect(GRAFO.size).toBeGreaterThanOrEqual(40);
    expect(archivosTs(TESTS, true).length).toBeGreaterThanOrEqual(40);

    // Y que el parser de subpaths realmente matchee: hoy hay 5 archivos de
    // producción importando de `firebase-admin/firestore`. Si esto da 0, la
    // regex dejó de andar y todo lo de abajo es decorativo.
    const conSubpath = [...GRAFO.values()].filter((a) => Object.keys(a.subpaths).length > 0);
    expect(conSubpath.length).toBeGreaterThanOrEqual(1);
  });

  it("ningún test mockea `firebase-admin` dejando un subpath con app al descubierto", () => {
    const violaciones: string[] = [];

    for (const test of archivosTs(TESTS, true)) {
      const codigo = fs.readFileSync(test, "utf8");
      const mockeados = new Set([...codigo.matchAll(JEST_MOCK)].map((m) => m[1]));
      if (!mockeados.has("firebase-admin")) continue;

      const cuerpoNs = cuerpoEfectivo(cuerpoDelMock(codigo, "firebase-admin"));
      const { relativos } = analizar(test);

      for (const [subpath, porNombre] of subpathsAlcanzados(relativos)) {
        // Mockear el subpath NO alcanza: el doble tiene que TRAER los símbolos que
        // producción le pide. Es un hueco real, no teórico — en el PR 4
        // `mp-reconcile.test.ts` ya mockeaba `firebase-admin/firestore` (con
        // `FieldValue`/`Timestamp`, del PR 3) cuando producción empezó a pedirle
        // `getFirestore`. El subpath estaba mockeado y el símbolo no existía.
        const cuerpoSub = mockeados.has(subpath) ? cuerpoEfectivo(cuerpoDelMock(codigo, subpath)) : null;

        const culpables: string[] = [];
        for (const [nombre, archivos] of porNombre) {
          // PRIMERO el filtro de peligrosidad. Al revés, el gate empieza a pedir
          // que se mockeen TIPOS (`DocumentData`, `DocumentReference`), que se
          // borran al compilar y no pueden driftear — ruido puro, y el ruido en un
          // gate es lo que lleva a que alguien lo silencie.
          const exigeApp = SIMBOLOS_QUE_EXIGEN_APP.has(nombre);
          // ¿Este test se tomó el trabajo de falsear este símbolo en su mock
          // namespaced? Entonces le importa, y leer el real es drift.
          const falseado = new RegExp(`\\b${nombre}\\b`).test(cuerpoNs);
          if (!exigeApp && !falseado) continue;

          // Con el subpath ya mockeado, lo único que falta es que ESTE símbolo
          // esté adentro del doble.
          if (cuerpoSub !== null) {
            if (new RegExp(`\\b${nombre}\\b`).test(cuerpoSub)) continue;
            culpables.push(
              `${nombre} — el mock de "${subpath}" existe pero no lo trae ← ${[...archivos].sort().join(", ")}`,
            );
            continue;
          }

          const motivo = exigeApp ? "necesita una app" : "lo falsea este mismo test";
          culpables.push(`${nombre} (${motivo}) ← ${[...archivos].sort().join(", ")}`);
        }
        if (culpables.length === 0) continue;

        const cabecera =
          cuerpoSub === null
            ? `    mockea "firebase-admin" pero NO "${subpath}", del que su grafo importa:`
            : `    mockea "${subpath}" pero su doble no cubre lo que el grafo importa:`;
        violaciones.push(
          `${path.relative(TESTS, test)}\n` +
            `${cabecera}\n` +
            culpables.sort().map((c) => `      · ${c}`).join("\n"),
        );
      }
    }

    expect(violaciones.sort().join("\n\n")).toBe("");
  });
});
