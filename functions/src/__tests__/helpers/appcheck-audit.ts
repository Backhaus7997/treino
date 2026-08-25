/**
 * Inventario de callables desplegados y su atestacion, derivado del AST.
 *
 * POR QUE EXISTE
 * --------------
 * QA-SEC-016 (#783): el guard anterior tenia la lista de callables escrita a
 * mano. Se escribio con dos entradas, se desplegaron tres callables mas, y la
 * lista nunca crecio. El scanner quedo verde cubriendo 2 de 5 — afirmando una
 * propiedad que no verificaba, que es peor que no tener scanner.
 *
 * La unica forma de que una lista no se quede vieja es no escribirla. Este
 * modulo la DERIVA de `index.ts`: los callables desplegados son exactamente
 * los simbolos exportados ahi que resuelven a un `onCall`.
 *
 * POR QUE AST Y NO REGEX
 * ----------------------
 * El guard viejo hacia `src.match(/enforceAppCheck:\s*true/)` sobre el archivo
 * ENTERO. Dos defectos que un regex no puede evitar:
 *
 *   1. Un `// export { x } from "./y"` comentado parece un export.
 *   2. En un archivo con dos callables —uno atestado y otro no— el match del
 *      primero le da el visto bueno al segundo. `auth/request-auth-email.ts`
 *      ya exporta dos.
 *
 * El AST no tiene ninguno de los dos problemas: los comentarios no son nodos,
 * y las opciones de cada `onCall` son un objeto distinto.
 *
 * El modulo es puro — recibe el fuente de `index.ts` y un lector de modulos —
 * asi que el caso negativo del test lo puede correr contra un index sintetico
 * sin tocar el repo. Ver `appcheck-enforcement.test.ts`.
 */
import * as ts from "typescript";

/** Si el `onCall` exige atestacion en sus opciones. */
export type Attestation = "enforced" | "absent";

export interface DeployedCallable {
  /** Nombre con el que la funcion queda desplegada (el de `index.ts`). */
  exportedName: string;
  /** Nombre local del simbolo en su archivo fuente. */
  symbol: string;
  /** Ruta del archivo, relativa a `src/`, sin extension. */
  module: string;
  attestation: Attestation;
}

/**
 * Exencion declarada. Union discriminada a proposito: el compilador OBLIGA a
 * que una exencion `debt` traiga su condicion de salida. Una deuda sin
 * condicion de salida es una decision disfrazada, y la diferencia entre las
 * dos es justamente lo que #783 pide poder distinguir.
 */
export type Exemption =
  | { permanence: "decided"; reason: string }
  | { permanence: "debt"; reason: string; exitCondition: string };

export interface AuditInput {
  /** Fuente de `index.ts`. */
  indexSource: string;
  /**
   * Lee un modulo por su ruta relativa a `src/` sin extension, tal como
   * aparece en el `from "./..."`. Devuelve `undefined` si no existe.
   */
  readModule: (modulePath: string) => string | undefined;
}

function parse(fileName: string, source: string): ts.SourceFile {
  return ts.createSourceFile(fileName, source, ts.ScriptTarget.ES2020, true);
}

/**
 * Los `export { a, b as c } from "./mod"` de un fuente, ya sin los que estan
 * comentados: un comentario no llega a ser un nodo del AST.
 */
function readReExports(
  indexSource: string,
): Array<{ exportedName: string; symbol: string; module: string }> {
  const sf = parse("index.ts", indexSource);
  const out: Array<{ exportedName: string; symbol: string; module: string }> =
    [];

  for (const stmt of sf.statements) {
    if (!ts.isExportDeclaration(stmt)) continue;
    if (!stmt.moduleSpecifier || !ts.isStringLiteral(stmt.moduleSpecifier)) {
      continue;
    }
    const clause = stmt.exportClause;
    if (!clause || !ts.isNamedExports(clause)) continue;

    const module = stmt.moduleSpecifier.text.replace(/^\.\//, "");
    for (const el of clause.elements) {
      out.push({
        exportedName: el.name.text,
        symbol: (el.propertyName ?? el.name).text,
        module,
      });
    }
  }
  return out;
}

/** `functions.onCall(...)` o `onCall(...)` — no `onDocumentWritten`, etc. */
function isOnCall(expr: ts.Expression): expr is ts.CallExpression {
  if (!ts.isCallExpression(expr)) return false;
  const callee = expr.expression;
  if (ts.isIdentifier(callee)) return callee.text === "onCall";
  if (ts.isPropertyAccessExpression(callee)) {
    return callee.name.text === "onCall";
  }
  return false;
}

/**
 * `enforceAppCheck: true` en las opciones de ESTE `onCall` — no en cualquier
 * parte del archivo.
 *
 * Recorre las propiedades EN ORDEN y se queda con la ultima que decide, porque
 * en un object literal gana la ultima escritura. Dos consecuencias:
 *
 *   { ...base, enforceAppCheck: true }   -> enforced  (el explicito gana)
 *   { enforceAppCheck: true, ...base }   -> absent    (el spread puede pisarlo)
 *
 * El segundo caso es deliberadamente conservador: no podemos resolver el valor
 * efectivo de un spread sin type checker, asi que se falla cerrado. Un refactor
 * a `{ enforceAppCheck: true, ...runtimeOptions }` apagaria la atestacion en
 * runtime sin que se note; preferimos un rojo que obligue a escribirlo explicito.
 * Reportado por la review de Codex en el PR #805.
 */
function attestationOf(call: ts.CallExpression): Attestation {
  const options = call.arguments[0];
  if (!options || !ts.isObjectLiteralExpression(options)) return "absent";

  let attested = false;
  for (const prop of options.properties) {
    if (ts.isSpreadAssignment(prop)) {
      // No sabemos que trae: cualquier atestacion anterior deja de ser
      // demostrable.
      attested = false;
      continue;
    }
    if (!ts.isPropertyAssignment(prop)) continue;
    const key = ts.isIdentifier(prop.name) || ts.isStringLiteral(prop.name)
      ? prop.name.text
      : undefined;
    if (key !== "enforceAppCheck") continue;
    attested = prop.initializer.kind === ts.SyntaxKind.TrueKeyword;
  }
  return attested ? "enforced" : "absent";
}

/** Busca `export const <symbol> = <onCall>(...)` en un modulo ya parseado. */
function findCallable(
  moduleSource: string,
  moduleName: string,
  symbol: string,
): ts.CallExpression | undefined {
  const sf = parse(`${moduleName}.ts`, moduleSource);

  for (const stmt of sf.statements) {
    if (!ts.isVariableStatement(stmt)) continue;
    for (const decl of stmt.declarationList.declarations) {
      if (!ts.isIdentifier(decl.name) || decl.name.text !== symbol) continue;
      if (decl.initializer && isOnCall(decl.initializer)) {
        return decl.initializer;
      }
    }
  }
  return undefined;
}

/**
 * El inventario de callables DESPLEGADOS: los simbolos exportados por
 * `index.ts` que resuelven a un `onCall`. Los triggers (`onDocumentWritten`,
 * `onSchedule`, ...) quedan afuera solos, porque no son callables y no tienen
 * `enforceAppCheck` que discutir.
 */
export function collectDeployedCallables(
  input: AuditInput,
): DeployedCallable[] {
  const out: DeployedCallable[] = [];

  for (const ref of readReExports(input.indexSource)) {
    const source = input.readModule(ref.module);
    if (source === undefined) continue;

    const call = findCallable(source, ref.module, ref.symbol);
    if (!call) continue;

    out.push({
      exportedName: ref.exportedName,
      symbol: ref.symbol,
      module: ref.module,
      attestation: attestationOf(call),
    });
  }

  return out.sort((a, b) => a.exportedName.localeCompare(b.exportedName));
}

/**
 * La identidad con la que se keyea una exencion: `<modulo>:<simbolo>`.
 *
 * NO alcanza con el simbolo local. Keyeando solo por simbolo, un
 * `acceptTrainerLink` sin atestar declarado en OTRO modulo y exportado con otro
 * nombre publico hereda la exencion del original, aunque el motivo escrito
 * —"lo llama el Coach Hub web"— no tenga nada que ver con el. El par
 * modulo+simbolo identifica una definicion y una sola, asi que una exencion
 * ampara exactamente al codigo para el que se escribio. Reportado por la review
 * de Codex en el PR #805.
 */
export const callableKey = (
  c: Pick<DeployedCallable, "module" | "symbol">,
): string => `${c.module}:${c.symbol}`;

export interface AuditVerdict {
  /**
   * Callables desplegados sin atestacion y sin exencion declarada. Cualquier
   * entrada aca es una falla: el punto entero del registry es que agregar un
   * callable sin atestacion obligue a escribir POR QUE.
   */
  unguarded: DeployedCallable[];
  /**
   * Exenciones que ya no corresponden — el callable dejo de estar desplegado,
   * se movio de modulo, o volvio a exigir atestacion. Tambien fallan: un
   * registry que solo crece se pudre igual que la lista que vino a reemplazar,
   * y el dia que alguien restaure el flag queremos que el test le diga que
   * borre la exencion.
   */
  staleExemptions: string[];
}

export function auditAttestation(
  callables: DeployedCallable[],
  exemptions: Readonly<Record<string, Exemption>>,
): AuditVerdict {
  const unguarded = callables.filter(
    (c) => c.attestation === "absent" && !(callableKey(c) in exemptions),
  );

  const byKey = new Map(callables.map((c) => [callableKey(c), c]));
  const staleExemptions = Object.keys(exemptions)
    .filter((key) => {
      const c = byKey.get(key);
      return c === undefined || c.attestation === "enforced";
    })
    .sort();

  return { unguarded, staleExemptions };
}
