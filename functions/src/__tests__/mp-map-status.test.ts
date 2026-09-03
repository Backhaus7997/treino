/**
 * mp-map-status.test.ts — la traduccion de estados de Mercado Pago.
 * LOCAL, sin emulador y sin red: la funcion bajo prueba es pura.
 */

const warnSpy = jest.fn();
jest.mock("firebase-functions", () => ({
  logger: {
    warn: (...args: unknown[]) => warnSpy(...args),
    info: jest.fn(),
    error: jest.fn(),
  },
}));

import {
  MP_PREAPPROVAL_STATUSES,
  hayCobroPendiente,
  mapMpStatus,
} from "../subscriptions/mp/map-status";
import { SUBSCRIPTION_STATUSES } from "../subscriptions/effective-limit";

beforeEach(() => jest.clearAllMocks());

describe("mapMpStatus — el mapeo feliz", () => {
  it("authorized sin cobro pendiente es active", () => {
    expect(mapMpStatus({ raw: "authorized" })).toEqual({
      status: "active",
      degraded: false,
    });
  });

  it("pending, paused y cancelled pasan derecho", () => {
    expect(mapMpStatus({ raw: "pending" }).status).toBe("pending");
    expect(mapMpStatus({ raw: "paused" }).status).toBe("paused");
    expect(mapMpStatus({ raw: "cancelled" }).status).toBe("cancelled");
  });

  it("NINGUN estado conocido de MP degrada", () => {
    // Recorre la lista en runtime, no una copia escrita a mano: agregar un
    // estado a MP_PREAPPROVAL_STATUSES sin traducirlo rompe acá.
    for (const mp of MP_PREAPPROVAL_STATUSES) {
      const r = mapMpStatus({ raw: mp });
      expect(r.degraded).toBe(false);
      expect(SUBSCRIPTION_STATUSES).toContain(r.status);
    }
    expect(warnSpy).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// `grace` — la unica asimetria con MP, y la que mas facil se rompe.
//
// MP NO mueve `status` cuando un cobro rebota: deja la suscripcion en
// `authorized` y reintenta. Si esta rama se cae, un PF que no pago se ve
// EXACTAMENTE igual que uno al dia, y el sistema no se entera nunca.
// ---------------------------------------------------------------------------

describe("mapMpStatus — grace", () => {
  it("authorized CON cobro pendiente es grace, no active", () => {
    expect(mapMpStatus({ raw: "authorized", cobroPendiente: true })).toEqual({
      status: "grace",
      degraded: false,
    });
  });

  it("grace NO se contagia a los otros estados", () => {
    // Si MP ya dijo algo mas fuerte que "authorized", el historial de cobros no
    // lo puede pisar. Un `cancelled` con una cuota vieja impaga sigue siendo
    // cancelled: darle `grace` le devolveria el limite pago a alguien que se
    // dio de baja.
    for (const mp of ["pending", "paused", "cancelled"] as const) {
      expect(mapMpStatus({ raw: mp, cobroPendiente: true }).status).toBe(mp);
    }
  });

  it("grace da el limite PAGO — la asimetria apunta a no lastimar al alumno", () => {
    // No es un detalle de traduccion: es la politica. Mientras MP reintenta, el
    // PF conserva sus alumnos. Este test existe para que invertir la direccion
    // sea una decision y no un descuido.
    const { status } = mapMpStatus({ raw: "authorized", cobroPendiente: true });
    expect(status).toBe("grace");
    expect(status).not.toBe("paused");
    expect(status).not.toBe("cancelled");
  });
});

// ---------------------------------------------------------------------------
// Datos rotos. MP es un tercero: lo que devuelve NO es un tipo, es una promesa.
// ---------------------------------------------------------------------------

describe("mapMpStatus — entradas que no entendemos", () => {
  const basura: [string, unknown][] = [
    ["un estado que MP agregue mañana", "suspended"],
    ["mayusculas", "AUTHORIZED"],
    ["string vacio", ""],
    ["null", null],
    ["undefined", undefined],
    ["un numero", 1],
    ["un objeto", { status: "authorized" }],
    ["un array", ["authorized"]],
  ];

  for (const [caso, raw] of basura) {
    it(`degrada a pending con ${caso}`, () => {
      const r = mapMpStatus({ raw, trainerId: "t1" });
      expect(r).toEqual({ status: "pending", degraded: true });
    });
  }

  it("el warn lleva el trainerId y el valor recibido, o no sirve para nada", () => {
    // Un warn sin uid no localiza el documento roto entre cientos. Es la misma
    // leccion que dejo `subscription-state.ts`.
    mapMpStatus({ raw: "suspended", trainerId: "trainer-42" });

    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain("estado desconocido");
    expect(warnSpy.mock.calls[0][1]).toEqual(
      expect.objectContaining({
        trainerId: "trainer-42",
        received: "suspended",
      }),
    );
  });

  it("el fallback NO es active ni cancelled, y eso es la mitad del diseño", () => {
    // `active` le regalaria cupo a un estado que no entendemos.
    // `cancelled` le sacaria alumnos a alguien por un valor que quizas es
    // perfectamente valido y nuevo. `pending` frena trabajo nuevo sin revocar
    // nada: es el unico que le cobra la friccion al entrenador y no al alumno.
    const r = mapMpStatus({ raw: "loquesea" });
    expect(r.status).toBe("pending");
    expect(r.status).not.toBe("active");
    expect(r.status).not.toBe("cancelled");
  });

  it("un estado desconocido con cobro pendiente TAMPOCO da grace", () => {
    // `grace` da el limite pago. Concederlo por un estado que no entendemos
    // seria darle cupo gratis a cualquiera que MP reporte raro.
    expect(mapMpStatus({ raw: "???", cobroPendiente: true })).toEqual({
      status: "pending",
      degraded: true,
    });
  });
});

// ---------------------------------------------------------------------------
// `hayCobroPendiente` — la otra mitad de grace.
//
// Sin esto, la rama de `grace` de arriba nunca se activa en produccion: es la
// unica fuente que sabe si MP esta reintentando un cobro.
// ---------------------------------------------------------------------------

describe("hayCobroPendiente", () => {
  it("una cuota pendiente da true", () => {
    expect(hayCobroPendiente({ pending_charge_quantity: 1 })).toBe(true);
    expect(hayCobroPendiente({ pending_charge_quantity: 3 })).toBe(true);
  });

  it("cero pendientes da false", () => {
    expect(hayCobroPendiente({ pending_charge_quantity: 0 })).toBe(false);
  });

  it("mira la CANTIDAD, no el monto", () => {
    // Un monto de 0 es ambiguo: puede ser "no hay nada" o "hay una cuota de
    // importe cero". La cantidad contesta exactamente lo que se pregunta.
    expect(
      hayCobroPendiente({
        pending_charge_amount: 22000,
        pending_charge_quantity: 0,
      }),
    ).toBe(false);
  });

  it("NO usa `semaphore`, cuyo dominio no conocemos", () => {
    // Un campo cuyos valores no estan documentados no puede decidir si alguien
    // conserva sus alumnos.
    expect(hayCobroPendiente({ semaphore: "red" })).toBe(false);
  });

  const basura: [string, unknown][] = [
    ["undefined", undefined],
    ["null", null],
    ["un string", "1"],
    ["un numero", 1],
    ["objeto vacio", {}],
    ["cantidad como string", { pending_charge_quantity: "2" }],
    ["cantidad null", { pending_charge_quantity: null }],
    ["cantidad NaN", { pending_charge_quantity: Number.NaN }],
    ["cantidad negativa", { pending_charge_quantity: -1 }],
  ];

  for (const [caso, entrada] of basura) {
    it(`es conservadora con ${caso}: false, o sea active y no grace`, () => {
      expect(hayCobroPendiente(entrada)).toBe(false);
    });
  }

  it("las dos mitades se combinan: authorized + pendiente = grace", () => {
    // El unico test que ejercita el camino COMPLETO, que es como lo va a usar
    // el reconciliador.
    const summarized = { pending_charge_quantity: 1 };
    const r = mapMpStatus({
      raw: "authorized",
      cobroPendiente: hayCobroPendiente(summarized),
    });
    expect(r.status).toBe("grace");
  });
});
