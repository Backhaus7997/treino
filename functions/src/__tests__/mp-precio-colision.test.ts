/**
 * mp-precio-colision.test.ts — el guard que impide que dos planes distintos
 * cobren el mismo monto.
 *
 * Vive en un archivo propio porque prueba un THROW AL IMPORTAR, y para eso hay
 * que cargar `tier-mapping` con un precio de alumno falso. Hacerlo en
 * `mp-tier-mapping.test.ts` obligaria a que ese archivo no importara el modulo
 * de arriba, que es justo lo que todos sus otros tests necesitan.
 *
 * ── Que protege ──
 *
 * `lookupPlan` cae al monto cuando el documento de `mp_plans` no esta o no se
 * entiende. Si dos planes valen lo mismo, ese fallback le acredita a alguien un
 * plan que no compro — y el caso feo no es PF-contra-PF sino alumno-contra-PF:
 * un alumno que paga 22.000 al año recibiria el Plan 2 de entrenador, con su
 * cupo de 15 alumnos.
 *
 * El guard rompe el DEPLOY, no una request. Es a proposito: un throw al
 * importar frena el arranque de las functions y de los tests, ruidoso y
 * temprano, en vez de esperar a que alguien pague.
 */

jest.mock("firebase-functions", () => ({
  logger: { warn: jest.fn(), info: jest.fn(), error: jest.fn() },
}));

import { TIER_PRICES_ARS } from "../subscriptions/tier-config";

/** Carga `tier-mapping` de cero con este precio de alumno. */
function cargarCon(monthly: number): () => unknown {
  return () => {
    let modulo: unknown;
    jest.isolateModules(() => {
      jest.doMock("../subscriptions/athlete-plan-config", () => ({
        ATHLETE_PRICE_MONTHLY_ARS: monthly,
        ATHLETE_PRICES_ARS: { monthly, annual: monthly * 10 },
        athleteAmountFor: (cycle: string) =>
          cycle === "annual" ? monthly * 10 : monthly,
      }));
      // `require` y no `import`: `isolateModules` es SINCRONO, asi que un
      // import dinamico resolveria despues de que el registro de modulos ya
      // volvio a su estado normal y el mock no aplicaria.
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      modulo = require("../subscriptions/mp/tier-mapping");
    });
    return modulo;
  };
}

describe("BY_AMOUNT — la colision de montos impide cargar el modulo", () => {
  it("el anual del alumno igual al mensual del Plan 2 rompe el import", () => {
    // 2.200 × 10 = 22.000, que es `plan2/monthly`. Es el valor prohibido que
    // `athlete-plan-config.ts` nombra en su dartdoc; esto lo verifica.
    expect(TIER_PRICES_ARS.plan2.monthly).toBe(22000);

    expect(cargarCon(2200)).toThrow(/comparten el monto 22000/);
  });

  it("el mensual del alumno igual al mensual del Plan 1 rompe el import", () => {
    expect(TIER_PRICES_ARS.plan1.monthly).toBe(12000);

    expect(cargarCon(12000)).toThrow(/comparten el monto 12000/);
  });

  it("el error nombra a los DOS planes que chocan", () => {
    // Un mensaje que solo dijera «hay una colision» dejaria a quien lo lea
    // abriendo dos tablas de precios para encontrar cual. El deploy esta
    // roto: el mensaje tiene que alcanzar para arreglarlo.
    try {
      cargarCon(2200)();
      throw new Error("no tiro");
    } catch (e) {
      const msg = String((e as Error).message);
      expect(msg).toContain("plan2/monthly");
      expect(msg).toContain("alumno/annual");
      expect(msg).toContain("ATHLETE_PRICE_MONTHLY_ARS");
    }
  });

  it("un precio sin colision carga normal — el guard no es un falso positivo", () => {
    // El contrapeso. Sin esto, un guard que tirara SIEMPRE pasaria los tres
    // tests de arriba y nadie se enteraria hasta el proximo deploy.
    expect(cargarCon(3500)).not.toThrow();
  });
});
