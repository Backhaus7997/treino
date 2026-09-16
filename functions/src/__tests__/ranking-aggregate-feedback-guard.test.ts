/**
 * `soloCambioFeedbackCounts` — la guarda que impide que un comentario del
 * alumno lance un recompute completo de rankings.
 *
 * `rankingAggregateOnSession` escucha CUALQUIER escritura sobre el doc de
 * sesión y recomputaba sin condición: hasta 365 sesiones más los `setLogs` de
 * cada una. Al agregar `maintainSessionFeedbackCounters`, cada molestia o nota
 * pasó a escribir ese doc — y por lo tanto a disparar ese recompute. Lo
 * encontró Codex en el #1153.
 *
 * El riesgo de una guarda así es el OPUESTO al que parece: no es que saltee de
 * más, es que saltee un cambio que SÍ mueve el ranking. Por eso corta por "el
 * único que cambió fue feedbackCounts" y no por una allowlist de campos
 * relevantes, que se desactualiza en silencio. La mitad de estos tests existe
 * para pinear justamente eso.
 */

import { soloCambioFeedbackCounts } from "../ranking-aggregate";

const base = {
  uid: "a1",
  routineName: "Piernas",
  status: "finished",
  finishedAt: "2026-05-19T14:00:00Z",
  totalVolumeKg: 1800,
  durationMin: 45,
  wasFullyCompleted: true,
};

describe("soloCambioFeedbackCounts", () => {
  it("true cuando SÓLO cambió feedbackCounts", () => {
    expect(
      soloCambioFeedbackCounts(base, { ...base, feedbackCounts: { comment: 1 } }),
    ).toBe(true);
  });

  it("true también cuando el mapa cambia de un valor a otro", () => {
    expect(
      soloCambioFeedbackCounts(
        { ...base, feedbackCounts: { comment: 1 } },
        { ...base, feedbackCounts: { comment: 2, discomfort: 1 } },
      ),
    ).toBe(true);
  });

  it("false cuando NO cambió nada — no hay nada que saltear", () => {
    expect(soloCambioFeedbackCounts(base, { ...base })).toBe(false);
  });

  // ── Lo que NO se puede saltear. Cada uno mueve el ranking. ────────────────

  it.each([
    ["finishedAt", { finishedAt: "2026-05-19T15:00:00Z" }],
    ["status", { status: "active" }],
    ["totalVolumeKg", { totalVolumeKg: 2000 }],
    ["wasFullyCompleted", { wasFullyCompleted: false }],
    ["durationMin", { durationMin: 60 }],
  ])("false cuando además cambió %s", (_campo, cambio) => {
    expect(
      soloCambioFeedbackCounts(base, {
        ...base,
        ...cambio,
        feedbackCounts: { comment: 1 },
      }),
    ).toBe(false);
  });

  it("false cuando cambió otro campo SIN tocar feedbackCounts", () => {
    expect(
      soloCambioFeedbackCounts(base, { ...base, totalVolumeKg: 2000 }),
    ).toBe(false);
  });

  // Un campo NUEVO que nadie previó cuenta como "otra cosa cambió", así que se
  // recomputa. Es el default seguro: el costo de recomputar de más es plata; el
  // de saltear de menos es un ranking equivocado.
  it("false ante un campo desconocido — el default es recomputar", () => {
    expect(
      soloCambioFeedbackCounts(base, { ...base, campoDelFuturo: 42 }),
    ).toBe(false);
  });

  it("false cuando falta el before o el after — no se puede comparar", () => {
    expect(soloCambioFeedbackCounts(undefined, base)).toBe(false);
    expect(soloCambioFeedbackCounts(base, undefined)).toBe(false);
  });

  // El create y el delete pasan por este mismo trigger.
  it("false en un create (before vacío)", () => {
    expect(soloCambioFeedbackCounts({}, base)).toBe(false);
  });
});
