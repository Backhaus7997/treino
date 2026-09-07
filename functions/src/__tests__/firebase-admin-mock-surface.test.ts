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
 * importa algún símbolo QUE NECESITA UNA APP. Si alguno no está mockeado en ese
 * archivo, falla y dice cuál.
 *
 * La lista de subpaths NO está escrita a mano: sale del código en cada corrida,
 * igual que en `scripts/test/firebase_admin_superficie.test.js`. Una lista a mano
 * se desactualiza y termina prometiendo una cobertura que no tiene — el patrón
 * del #826.
 *
 * ─── Por qué sólo los símbolos que necesitan app ────────────────────────────
 *
 * `FieldValue` y `Timestamp` son fábricas puras: andan sin app y devuelven el
 * mismo sentinel que el mock devolvería. Exigir que se mockeen sería ruido, y el
 * ruido en un gate es lo que lleva a que alguien lo silencie.
 *
 * Los de `SIMBOLOS_QUE_EXIGEN_APP` TIRAN cuando no hay app inicializada, y ese
 * throw es el que se convierte en verde al pasar por un catch-all. Esos son los
 * que importan.
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
function subpathsAlcanzados(desde: string[]): Map<string, Set<string>> {
  const alcanzados = new Map<string, Set<string>>();
  const vistos = new Set<string>();
  const pendientes = [...desde];

  while (pendientes.length > 0) {
    const actual = pendientes.pop() as string;
    if (vistos.has(actual)) continue;
    vistos.add(actual);

    const analisis = GRAFO.get(actual);
    if (!analisis) continue;

    for (const [subpath, nombres] of Object.entries(analisis.subpaths)) {
      const exigen = nombres.filter((n) => SIMBOLOS_QUE_EXIGEN_APP.has(n));
      if (exigen.length === 0) continue;
      if (!alcanzados.has(subpath)) alcanzados.set(subpath, new Set());
      exigen.forEach((n) => (alcanzados.get(subpath) as Set<string>).add(`${n} (${path.relative(SRC, actual)})`));
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

      const { relativos } = analizar(test);
      for (const [subpath, quienes] of subpathsAlcanzados(relativos)) {
        if (mockeados.has(subpath)) continue;
        violaciones.push(
          `${path.relative(TESTS, test)}\n` +
            `    mockea "firebase-admin" pero NO "${subpath}", del que su grafo importa:\n` +
            [...quienes].sort().map((q) => `      · ${q}`).join("\n"),
        );
      }
    }

    expect(violaciones.sort().join("\n\n")).toBe("");
  });
});
