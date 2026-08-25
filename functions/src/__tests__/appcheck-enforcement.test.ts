/**
 * QA-SEC-006 / QA-SEC-016 — guard estatico: todo callable DESPLEGADO tiene que
 * exigir App Check, o tener una exencion declarada con motivo.
 *
 * El enforcement de App Check no se puede testear con firebase-functions-test
 * (vive en la capa de transporte, no en el handler), asi que esto es una
 * asercion a nivel fuente.
 *
 * QUE CAMBIO EN #783
 * ------------------
 * La version anterior tenia la lista de callables ESCRITA A MANO. Nacio con
 * dos entradas, se desplegaron tres callables mas, y la lista nunca crecio: el
 * scanner quedo verde cubriendo 2 de 5. Un test que afirma una propiedad que
 * no verifica es peor que no tener test, porque ademas apaga la sospecha.
 *
 * Ahora la lista se DERIVA de `index.ts` via AST (ver `helpers/appcheck-audit`)
 * y no se puede quedar vieja. Lo unico escrito a mano es el registry de
 * exenciones de abajo, y esta al reves: agregar un callable sin atestacion y
 * sin exencion pone el test en ROJO. El default es fallar.
 *
 * LAS TRES PROPIEDADES QUE SOSTIENE
 * ---------------------------------
 *   1. Todo callable desplegado esta atestado O exento con motivo escrito.
 *   2. Ninguna exencion sobrevive a su causa (si el flag vuelve, la exencion
 *      tiene que irse — el registry no puede solo crecer).
 *   3. El set desplegado es exactamente el esperado. Si la resolucion del AST
 *      se rompe, la lista se ENCOGE en silencio y todo lo demas pasa; el
 *      assert de set convierte esa falla muda en un rojo.
 */
import { readFileSync } from "fs";
import { join } from "path";
import {
  auditAttestation,
  callableKey,
  collectDeployedCallables,
  type AuditVerdict,
  type DeployedCallable,
  type Exemption,
} from "./helpers/appcheck-audit";

const SRC = join(__dirname, "..");

const readModule = (modulePath: string): string | undefined => {
  try {
    return readFileSync(join(SRC, `${modulePath}.ts`), "utf8");
  } catch {
    return undefined;
  }
};

/**
 * Exenciones, keyeadas por `<modulo>:<simbolo>` (ver `callableKey`).
 *
 * La clave NO es el simbolo solo: asi una exencion ampara exactamente a la
 * definicion para la que se escribio, y un homonimo en otro modulo no hereda
 * un motivo que no le corresponde.
 *
 * Cada motivo vive TAMBIEN en el archivo del callable, con todo el detalle.
 * Aca va la version corta y, sobre todo, la clasificacion: `decided` es un
 * trade-off que tomamos, `debt` es algo que queremos revertir. La union
 * discriminada obliga a que un `debt` traiga condicion de salida — una deuda
 * sin condicion de salida es una decision disfrazada.
 */
const EXEMPTIONS: Readonly<Record<string, Exemption>> = {
  "subscriptions/accept-trainer-link:acceptTrainerLink": {
    permanence: "decided",
    reason:
      "Lo llama el Coach Hub web, que no activa App Check (main_coach_hub.dart " +
      "no tiene una sola referencia a FirebaseAppCheck, y main.dart lo saltea " +
      "con `if (!kIsWeb)`). Con el flag puesto, cada accept desde la web —que " +
      "es donde el PF realmente trabaja— seria rechazado. Es el bug que arreglo " +
      "el PR #704. Sigue validando request.auth, que el caller sea el trainer " +
      "del vinculo, y el estado de origen. Ver accept-trainer-link.ts:82.",
  },
  "subscriptions/resume-trainer-link:resumeTrainerLink": {
    permanence: "decided",
    reason:
      "Mismo caso y mismo PR #704 que acceptTrainerLink: se llama desde el " +
      "Coach Hub web. Gatear solo accept no alcanza —pause baja el peso de 1.0 " +
      "a 0.5— asi que las dos transiciones que suben peso van juntas, con o sin " +
      "atestacion. Ver resume-trainer-link.ts:77.",
  },
  "mint-watch-credential:mintWatchCredential": {
    permanence: "debt",
    reason:
      "Apagado el 2026-08-18 por decision del dueno: el cliente mandaba un " +
      "token que el server no podia decodificar, el reloj nunca recibia " +
      "credencial y quedaba en 'vinculando' para siempre, con el error tragado " +
      "en un catch. Sigue exigiendo request.auth y el uid sale unicamente del " +
      "token verificado. Ver mint-watch-credential.ts:94.",
    exitCondition:
      "Que el cliente emita atestacion valida en las DOS plataformas. Medido " +
      "sobre los logs de este callable el 2026-08-25 (ver PR de #783): iPhone " +
      "fisico 8 tokens VALID / 2 INVALID, Android 1 VALID / 8 INVALID (el " +
      "ultimo el 2026-08-24). O sea que App Attest en iOS ya funciona casi " +
      "siempre y el que falta es Play Integrity en Android. Antes de restaurar " +
      "el flag, volver a correr ese conteo sobre " +
      "jsonPayload.verifications.app y pedir cero INVALID por plataforma.",
  },
};

/**
 * El set desplegado hoy. No es un conteo suelto: si la resolucion del AST se
 * rompiera, el inventario se vaciaria y TODOS los demas asserts pasarian —
 * cero callables sin atestacion es trivialmente cierto sobre una lista vacia.
 * Pinear el set convierte ese modo de falla mudo en un rojo ruidoso.
 */
const EXPECTED_DEPLOYED = [
  "acceptTrainerLink",
  "addAlias",
  "deleteAccount",
  "mintWatchCredential",
  "resumeTrainerLink",
] as const;

const describeCallable = (c: DeployedCallable) =>
  `${c.exportedName} (${c.module}.ts → ${c.symbol})`;

/**
 * La asercion de fondo, extraida para que el caso negativo de mas abajo pueda
 * demostrar que ESTA MISMA falla — y no solo que el analizador marca algo.
 */
function assertEveryCallableIsGuarded(verdict: AuditVerdict): void {
  expect(verdict.unguarded.map(describeCallable)).toEqual([]);
  expect(verdict.staleExemptions).toEqual([]);
}

describe("QA-SEC-006/016: atestacion en los callables desplegados", () => {
  const deployed = collectDeployedCallables({
    indexSource: readFileSync(join(SRC, "index.ts"), "utf8"),
    readModule,
  });

  it("el set desplegado es exactamente el esperado", () => {
    expect(deployed.map((c) => c.exportedName)).toEqual([
      ...EXPECTED_DEPLOYED,
    ]);
  });

  it("cada callable esta atestado o exento con motivo declarado", () => {
    assertEveryCallableIsGuarded(auditAttestation(deployed, EXEMPTIONS));
  });

  it.each([...EXPECTED_DEPLOYED])(
    "%s: atestacion y exencion son mutuamente excluyentes",
    (exportedName) => {
      const c = deployed.find((x) => x.exportedName === exportedName);
      expect(c).toBeDefined();
      const exempt = callableKey(c!) in EXEMPTIONS;
      expect(c!.attestation === "enforced").toBe(!exempt);
    },
  );

  it("toda exencion de tipo `debt` declara su condicion de salida", () => {
    // El compilador ya lo obliga via la union discriminada; esto lo sostiene
    // tambien en runtime, para que un `as Exemption` de apuro no lo saltee.
    const debts = Object.entries(EXEMPTIONS).filter(
      ([, e]) => e.permanence === "debt",
    );
    expect(debts.length).toBeGreaterThan(0);
    for (const [symbol, e] of debts) {
      expect(
        e.permanence === "debt" ? e.exitCondition : "",
      ).toEqual(expect.stringMatching(/\S/));
      expect(symbol in EXEMPTIONS).toBe(true);
    }
  });

  it("no hay exenciones para callables que no estan desplegados", () => {
    const keys = new Set(deployed.map(callableKey));
    expect(Object.keys(EXEMPTIONS).filter((k) => !keys.has(k))).toEqual([]);
  });
});

/**
 * El caso negativo. Sin esto, el guard afirma que falla sin haberlo mostrado
 * nunca — que es exactamente el defecto que #783 vino a arreglar.
 *
 * Corre el MISMO analizador y la MISMA asercion contra un index sintetico, asi
 * que no toca el repo ni despliega nada.
 */
describe("QA-SEC-016: el guard falla cuando tiene que fallar", () => {
  const fixture = (indexSource: string, modules: Record<string, string>) =>
    collectDeployedCallables({
      indexSource,
      readModule: (m) => modules[m],
    });

  /**
   * Un mundo sintetico que ESPEJA el inventario real de hoy: mismos simbolos,
   * misma atestacion. No lee los archivos del repo, y esa es toda la gracia.
   *
   * La primera version de estos fixtures si los leia, y la verificacion por
   * mutación la reventó: al sacarle el flag a `delete-account.ts` caian
   * tambien los tres tests de este bloque, que no tienen nada que ver. Un
   * caso negativo que se cae junto con el positivo no distingue nada. Estos
   * tests juzgan la LOGICA del guard; los de arriba juzgan el estado del repo.
   *
   * El test de deriva de mas abajo mantiene los dos en sincronia.
   */
  const BASELINE = [
    { module: "delete-account", symbol: "deleteAccountHandler", as: "deleteAccount", attested: true },
    { module: "add-alias", symbol: "addAlias", as: "addAlias", attested: true },
    {
      module: "subscriptions/accept-trainer-link",
      symbol: "acceptTrainerLink",
      as: "acceptTrainerLink",
      attested: false,
    },
    {
      module: "subscriptions/resume-trainer-link",
      symbol: "resumeTrainerLink",
      as: "resumeTrainerLink",
      attested: false,
    },
    { module: "mint-watch-credential", symbol: "mintWatchCredential", as: "mintWatchCredential", attested: false },
  ];

  // Los modulos son los reales para que las claves del registry apliquen, pero
  // las FUENTES son sinteticas: `world()` nunca lee del disco.

  const onCallSource = (symbol: string, attested: boolean) =>
    `export const ${symbol} = functions.onCall(\n` +
    `  { region: "southamerica-east1"${attested ? ", enforceAppCheck: true" : ""} },\n` +
    "  async () => ({ ok: true }),\n" +
    ");";

  /** El mundo base, opcionalmente con modulos extra o pisados. */
  const world = (
    extraExports: string[] = [],
    extraModules: Record<string, string> = {},
  ) => {
    const modules: Record<string, string> = {};
    const exports: string[] = [];
    for (const c of BASELINE) {
      modules[c.module] = onCallSource(c.symbol, c.attested);
      exports.push(`export { ${c.symbol} as ${c.as} } from "./${c.module}";`);
    }
    return collectDeployedCallables({
      indexSource: [...exports, ...extraExports].join("\n"),
      readModule: (m) => extraModules[m] ?? modules[m],
    });
  };

  it("el mundo base tiene los mismos callables que el real (guard de deriva)", () => {
    // Si alguien despliega un sexto callable, este test avisa que el mundo
    // sintetico quedo viejo — antes de que los casos negativos empiecen a
    // probar algo que ya no se parece al repo.
    //
    // Compara el SET de callables, no su atestacion, a proposito: de quien
    // exige App Check y quien no ya se ocupan los tests de arriba. Si esto
    // mirara tambien la atestacion, sacarle el flag a un callable haria caer
    // este test ademas de los que corresponden, y un rojo de mas en un lugar
    // que no es —"el mundo base quedo viejo" cuando en realidad se cayo una
    // atestacion— manda a mirar el archivo equivocado.
    const real = collectDeployedCallables({
      indexSource: readFileSync(join(SRC, "index.ts"), "utf8"),
      readModule,
    });
    expect(world().map((c) => `${callableKey(c)} as ${c.exportedName}`)).toEqual(
      real.map((c) => `${callableKey(c)} as ${c.exportedName}`),
    );
  });

  it("un callable sin atestacion y sin exencion pone la suite en rojo", () => {
    const deployed = world(
      ["export { sneakyHandler as sneaky } from \"./sneaky\";"],
      { sneaky: onCallSource("sneakyHandler", false) },
    );

    expect(deployed).toContainEqual({
      exportedName: "sneaky",
      symbol: "sneakyHandler",
      module: "sneaky",
      attestation: "absent",
    });

    const verdict = auditAttestation(deployed, EXEMPTIONS);
    expect(verdict.unguarded.map((c) => c.exportedName)).toEqual(["sneaky"]);
    expect(verdict.staleExemptions).toEqual([]);
    expect(() => assertEveryCallableIsGuarded(verdict)).toThrow();
  });

  it("el mismo callable CON atestacion pasa", () => {
    const deployed = world(
      ["export { sneakyHandler as sneaky } from \"./sneaky\";"],
      { sneaky: onCallSource("sneakyHandler", true) },
    );

    expect(
      deployed.find((c) => c.exportedName === "sneaky")?.attestation,
    ).toBe("enforced");
    expect(() =>
      assertEveryCallableIsGuarded(auditAttestation(deployed, EXEMPTIONS)),
    ).not.toThrow();
  });

  it("una exencion que sobrevivio a su causa tambien falla", () => {
    // El flag volvio a acceptTrainerLink, pero nadie borro su exencion.
    const deployed = world([], {
      "subscriptions/accept-trainer-link": onCallSource("acceptTrainerLink", true),
    });

    const verdict = auditAttestation(deployed, EXEMPTIONS);
    expect(verdict.unguarded).toEqual([]);
    expect(verdict.staleExemptions).toEqual([
      "subscriptions/accept-trainer-link:acceptTrainerLink",
    ]);
    expect(() => assertEveryCallableIsGuarded(verdict)).toThrow();
  });

  it("un export comentado no cuenta como desplegado", () => {
    // Defecto 1 del guard viejo: para un regex, un `// export {...}` es un
    // export. `resolveGymPlace` y los dos callables de auth viven asi.
    const deployed = fixture(
      "// export { sneakyHandler as sneaky } from \"./sneaky\";",
      { sneaky: "export const sneakyHandler = functions.onCall({}, () => 1);" },
    );
    expect(deployed).toEqual([]);
  });

  it("en un archivo con dos callables, cada uno se juzga por separado", () => {
    // Defecto 2 del guard viejo: `src.match(/enforceAppCheck:\s*true/)` sobre
    // el archivo entero le daba el visto bueno al segundo callable con la
    // atestacion del primero. `auth/request-auth-email.ts` ya exporta dos.
    const deployed = fixture(
      "export { attested, bare } from \"./pair\";",
      {
        pair:
          "export const attested = functions.onCall(\n" +
          "  { enforceAppCheck: true },\n" +
          "  async () => 1,\n" +
          ");\n" +
          "export const bare = functions.onCall({}, async () => 2);",
      },
    );

    expect(
      deployed.map((c) => [c.exportedName, c.attestation]),
    ).toEqual([
      ["attested", "enforced"],
      ["bare", "absent"],
    ]);
  });

  it("un trigger que no es onCall no entra al inventario", () => {
    const deployed = fixture(
      "export { onWrite } from \"./trigger\";",
      {
        trigger:
          "export const onWrite = functions.onDocumentWritten(\"x/{id}\", () => 1);",
      },
    );
    expect(deployed).toEqual([]);
  });

  it("un homonimo en otro modulo NO hereda la exencion", () => {
    // Hallazgo P2 de la review de Codex en el PR #805. Con las exenciones
    // keyeadas solo por simbolo, este callable —mismo nombre local, otro
    // modulo, otro nombre publico— pasaba amparado por un motivo escrito para
    // el Coach Hub web, que no tiene nada que ver con el.
    const deployed = world(
      ["export { acceptTrainerLink as promoteLink } from \"./impostor\";"],
      { impostor: onCallSource("acceptTrainerLink", false) },
    );

    const verdict = auditAttestation(deployed, EXEMPTIONS);
    expect(verdict.unguarded.map((c) => c.exportedName)).toEqual([
      "promoteLink",
    ]);
    expect(() => assertEveryCallableIsGuarded(verdict)).toThrow();

    // Y la demostracion de que la clave vieja lo dejaba pasar: con el registry
    // keyeado por simbolo pelado, el impostor NO aparece como unguarded.
    const bySymbolOnly = Object.fromEntries(
      Object.keys(EXEMPTIONS).map((k) => [k.split(":")[1], true]),
    );
    expect(
      deployed
        .filter((c) => c.attestation === "absent" && !(c.symbol in bySymbolOnly))
        .map((c) => c.exportedName),
    ).not.toContain("promoteLink");
  });

  it("mover un callable de modulo deja su exencion obsoleta", () => {
    // La contracara: la exencion sigue apuntando al modulo viejo, asi que hay
    // que reescribirla (y reconfirmar que el motivo sigue valiendo).
    const moved = collectDeployedCallables({
      indexSource:
        "export { acceptTrainerLink } from \"./subscriptions/promote\";",
      readModule: (m) =>
        m === "subscriptions/promote"
          ? onCallSource("acceptTrainerLink", false)
          : undefined,
    });

    const verdict = auditAttestation(moved, EXEMPTIONS);
    expect(verdict.unguarded.map(callableKey)).toEqual([
      "subscriptions/promote:acceptTrainerLink",
    ]);
    expect(verdict.staleExemptions).toContain(
      "subscriptions/accept-trainer-link:acceptTrainerLink",
    );
  });

  it("un spread DESPUES del flag no cuenta como atestado", () => {
    // Hallazgo P2 de la review de Codex en el PR #805: el spread puede pisar
    // `enforceAppCheck` en runtime y el scanner no puede resolverlo sin type
    // checker. Se falla cerrado.
    const deployed = world(["export { sneakyHandler as sneaky } from \"./s\";"], {
      s:
        "export const sneakyHandler = functions.onCall(\n" +
        "  { enforceAppCheck: true, ...runtimeOptions },\n" +
        "  async () => 1,\n" +
        ");",
    });

    expect(
      deployed.find((c) => c.exportedName === "sneaky")?.attestation,
    ).toBe("absent");
    expect(() =>
      assertEveryCallableIsGuarded(auditAttestation(deployed, EXEMPTIONS)),
    ).toThrow();
  });

  it("un spread ANTES del flag si cuenta como atestado", () => {
    // Aca el explicito es la ultima escritura, asi que el valor efectivo es
    // demostrable. Ser conservador tambien en este caso daria rojos falsos.
    const deployed = world(["export { sneakyHandler as sneaky } from \"./s\";"], {
      s:
        "export const sneakyHandler = functions.onCall(\n" +
        "  { ...runtimeOptions, enforceAppCheck: true },\n" +
        "  async () => 1,\n" +
        ");",
    });

    expect(
      deployed.find((c) => c.exportedName === "sneaky")?.attestation,
    ).toBe("enforced");
    expect(() =>
      assertEveryCallableIsGuarded(auditAttestation(deployed, EXEMPTIONS)),
    ).not.toThrow();
  });

  it("`enforceAppCheck: false` explicito cuenta como ausente", () => {
    const deployed = fixture(
      "export { off } from \"./off\";",
      {
        off:
          "export const off = functions.onCall(\n" +
          "  { enforceAppCheck: false },\n" +
          "  async () => 1,\n" +
          ");",
      },
    );
    expect(deployed[0].attestation).toBe("absent");
  });
});

/**
 * Los callables SHELVED. No estan desplegados, asi que no entran al inventario
 * derivado — pero el dia que alguien los exporte tienen que llegar atestados,
 * y eso hay que vigilarlo desde antes.
 */
describe("QA-SEC-006: callables shelved", () => {
  const index = () => readFileSync(join(SRC, "index.ts"), "utf8");

  it.each(["requestPasswordReset", "requestEmailVerification"])(
    "%s exige App Check apenas se exporte",
    (symbol) => {
      const deployed = collectDeployedCallables({
        indexSource: index(),
        readModule,
      });
      const live = deployed.find((c) => c.symbol === symbol);

      // Shelved o no, el archivo ya tiene que declarar la atestacion.
      // `requestPasswordReset` es el UNICO callable del repo invocable sin
      // sesion, y cada llamada le manda un mail a un tercero: sin atestacion
      // es un amplificador de spam apuntable.
      const src = readModule("auth/request-auth-email") ?? "";
      expect(src).toMatch(/enforceAppCheck:\s*true/);

      if (live) {
        // Ya se exporto: pasa a ser desplegado y lo juzga el inventario de
        // arriba, no este bloque.
        expect(live.attestation).toBe("enforced");
      }
    },
  );

  it("resolveGymPlace sigue shelved (o, si se activa, exige App Check)", () => {
    const deployed = collectDeployedCallables({
      indexSource: index(),
      readModule,
    });
    const live = deployed.find((c) => c.symbol === "resolveGymPlace");

    // Sigue shelved: no tiene superficie de ataque y no hay nada que exigirle.
    // El dia que se exporte pasa a ser desplegado y entra al inventario de
    // arriba, que le va a pedir atestacion o exencion escrita.
    expect(live).toBeUndefined();
  });
});
