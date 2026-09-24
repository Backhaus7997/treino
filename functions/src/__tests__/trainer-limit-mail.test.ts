/**
 * El mail al PF que chocó el tope de ejercicios propios de su plan
 * (limite-ejercicios-pf.md §3 PR4).
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Las mismas cuatro cláusulas que `free-limit-mail.test.ts`, con la 3ª
 * adaptada: acá no hay "¿ya paga?" sino "¿sigue en el tope?", leído de
 * `planLimits.customExercises` / `customExerciseUsage.count` — los MISMOS
 * dos campos que lee `customExerciseQuotaOk` en `firestore.rules`.
 *
 *   1. Sin anotación → silencio.
 *   2. Anotación vieja → silencio.
 *   3. Ya no está en el tope (count < limit, o límite null/ausente) → silencio.
 *   4. Enfriamiento de 14 días → silencio.
 *
 * Cada una con su test, y cada test verificado POR MUTACIÓN.
 */

import {
  decideTrainerLimitMail,
  enqueueTrainerLimitMail,
  VENTANA_MS,
  ENFRIAMIENTO_MS,
  CAMPO_TOPE_AT,
  CAMPO_TOPE_KIND,
  CAMPO_MAIL_AT,
  TRAINER_LIMIT_PREF_KEY,
} from "../subscriptions/trainer-limit-mail";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import { renderMail, APP_ENTRY_TRAINER } from "../mail/templates";
import type { App } from "firebase-admin/app";

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => "queued-id"),
}));

const setMock = jest.fn(async () => undefined);
jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  getFirestore: () => ({
    collection: () => ({ doc: () => ({ set: setMock }) }),
  }),
}));

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 24, 8, 0, 0);

/** Un `Timestamp` de Firestore, sólo con lo que el módulo le pide. */
const ts = (ms: number) => ({ toMillis: () => ms });

/** El PF que chocó el tope hace una hora y sigue exactamente en él. */
const CHOCO_RECIEN = {
  [CAMPO_TOPE_AT]: ts(AHORA - 60 * 60 * 1000),
  [CAMPO_TOPE_KIND]: "customExercises",
  planLimits: { customExercises: 20 },
  customExerciseUsage: { count: 20 },
};

beforeEach(() => {
  enqueueMock.mockClear();
  setMock.mockClear();
});

describe("⚠️ las cuatro cláusulas del silencio", () => {
  it("sin anotación no manda", () => {
    expect(
      decideTrainerLimitMail(
        { role: "trainer", planLimits: { customExercises: 20 } },
        AHORA,
      ),
    ).toBeNull();
  });

  it("⚠️ una anotación vieja no manda", () => {
    const viejo = { ...CHOCO_RECIEN, [CAMPO_TOPE_AT]: ts(AHORA - VENTANA_MS - 1) };
    expect(decideTrainerLimitMail(viejo, AHORA)).toBeNull();
  });

  it("⚠️ quien ya NO está en el tope (bajó el contador) no recibe la oferta", () => {
    const bajoElTope = {
      ...CHOCO_RECIEN,
      customExerciseUsage: { count: 19 },
    };
    expect(decideTrainerLimitMail(bajoElTope, AHORA)).toBeNull();
  });

  it("⚠️ quien ya NO tiene tope (subió de plan, límite null) no recibe la oferta", () => {
    const sinTope = {
      ...CHOCO_RECIEN,
      planLimits: { customExercises: null },
    };
    expect(decideTrainerLimitMail(sinTope, AHORA)).toBeNull();
  });

  it("⚠️ un límite ausente tampoco manda — interruptor apagado o sin primer sync", () => {
    const sinPlanLimits = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      customExerciseUsage: { count: 999 },
    };
    expect(decideTrainerLimitMail(sinPlanLimits, AHORA)).toBeNull();
  });

  it("⚠️ el ENFRIAMIENTO: no se le escribe dos veces en catorce días", () => {
    const yaEscrito = {
      ...CHOCO_RECIEN,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS + 1),
    };
    expect(decideTrainerLimitMail(yaEscrito, AHORA)).toBeNull();
  });

  it("pasado el enfriamiento sí vuelve a mandar", () => {
    const viejoMail = {
      ...CHOCO_RECIEN,
      [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS - 1),
    };
    expect(decideTrainerLimitMail(viejoMail, AHORA)).not.toBeNull();
  });
});

describe("cuando sí manda", () => {
  it("el tope tocado y el límite viajan en el plan", () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA);
    expect(plan?.kind).toBe("exercise-limit-reached");
    expect(plan?.tope).toBe("customExercises");
    expect(plan?.limit).toBe(20);
    expect(plan?.scope).toMatch(/^tope_/);
  });

  it("exactamente EN el tope (count == limit) manda — E6, no hace falta pasarse", () => {
    // El create que deja el contador en 20 pasa; el siguiente no. El mail
    // tiene que dispararse desde ahí, no sólo cuando ya se pasó.
    expect(decideTrainerLimitMail(CHOCO_RECIEN, AHORA)).not.toBeNull();
  });

  it("por ENCIMA del tope (bajó de plan) también manda", () => {
    const sobreElTope = {
      ...CHOCO_RECIEN,
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 35 },
    };
    expect(decideTrainerLimitMail(sobreElTope, AHORA)).not.toBeNull();
  });

  it("una anotación sin `kind` no rompe: cae a un valor declarado", () => {
    const sinKind = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 20 },
    };
    expect(decideTrainerLimitMail(sinKind, AHORA)?.tope).toBe("desconocido");
  });

  it("un límite corrupto (no numérico) no manda — mismo criterio fail-closed que la regla", () => {
    const corrupto = {
      ...CHOCO_RECIEN,
      planLimits: { customExercises: "20" },
    };
    expect(decideTrainerLimitMail(corrupto, AHORA)).toBeNull();
  });

  it("⚠️ lleva prefKey — es comunicación comercial", async () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA)!;
    await enqueueTrainerLimitMail(APP, "t1", plan, AHORA);
    expect(enqueueMock.mock.calls[0][1].prefKey).toBe(TRAINER_LIMIT_PREF_KEY);
    // Mismo valor que el del alumno — ver el encabezado del módulo.
    expect(TRAINER_LIMIT_PREF_KEY).toBe(ATHLETE_PROSPECT_PREF_KEY);
  });

  it("⚠️ el CTA va a la entrada del PF con destino facturación", async () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA)!;
    await enqueueTrainerLimitMail(APP, "t1", plan, AHORA);
    const url = String(enqueueMock.mock.calls[0][1].params.ctaUrl);
    expect(url.startsWith(APP_ENTRY_TRAINER)).toBe(true);
    expect(url).toContain("to=facturacion");
  });

  it("⚠️ el limite viaja como param para el template", async () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA)!;
    await enqueueTrainerLimitMail(APP, "t1", plan, AHORA);
    expect(enqueueMock.mock.calls[0][1].params.limit).toBe(20);
  });

  it("⚠️ anota que se escribió, DESPUÉS de encolar", async () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA)!;
    await enqueueTrainerLimitMail(APP, "t1", plan, AHORA);
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    expect(setMock).toHaveBeenCalledTimes(1);
  });
});

describe("el texto", () => {
  const render = (limit: number) =>
    renderMail("exercise-limit-reached", {
      tope: "customExercises",
      limit,
      ctaUrl: `${APP_ENTRY_TRAINER}?to=facturacion`,
    });

  it("dice el número del tope", () => {
    const { html, text } = render(20);
    expect(html).toContain("20 ejercicios propios");
    expect(text).toContain("20 ejercicios propios");
  });

  it("singular correcto en el borde: 1 ejercicio propio", () => {
    const { html } = render(1);
    expect(html).toContain("1 ejercicio propio");
    expect(html).not.toContain("1 ejercicios propios");
  });

  it("⚠️ nunca interpola null — sin params, cae a la frase genérica", () => {
    const { html, text } = renderMail("exercise-limit-reached", {
      ctaUrl: `${APP_ENTRY_TRAINER}?to=facturacion`,
    });
    expect(html).not.toContain("null");
    expect(text).not.toContain("null");
  });

  it("⚠️ dice que conserva todo y puede editar/borrar — nunca 'perder' ni 'borrar' en negativo", () => {
    const { text } = render(20);
    expect(text.toLowerCase()).toContain("conservás");
    expect(text.toLowerCase()).toMatch(/editarlos/);
    expect(text.toLowerCase()).toMatch(/borrarlos/);
    // E3: bajar de plan nunca borra ni bloquea lo que ya existe.
    expect(text.toLowerCase()).not.toMatch(/perdés|perdes|se borra tu|se eliminan tus/);
  });

  it("el CTA ofrece ver planes, no un botón hero sin cuerpo", () => {
    const { html } = render(20);
    expect(html).toContain("VER LOS PLANES");
    // A diferencia de free-limit-reached, este SÍ lleva cuerpo — no es hero.
    expect(html).toMatch(/<p /);
  });
});
