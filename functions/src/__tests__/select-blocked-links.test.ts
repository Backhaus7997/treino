/**
 * select-blocked-links.test.ts — quien se bloquea cuando un PF queda por
 * encima de su limite (paywall Fase 7, downgrade). LOCAL — sin emulador.
 *
 * Pura decision, sin Firestore: dada la lista de vinculos y el limite
 * efectivo, devuelve a quien conservar y a quien bloquear.
 */

import { selectLinksToBlock, BlockableLink } from "../subscriptions/select-blocked-links";

const link = (o: Partial<BlockableLink> & { id: string }): BlockableLink => ({
  athleteId: `a-${o.id}`,
  status: "active",
  entitlement: "entitled",
  acceptedAtMs: 1000,
  ...o,
});

describe("selectLinksToBlock", () => {
  it("bajo el limite no bloquea a nadie", () => {
    const r = selectLinksToBlock(
      [link({ id: "L1" }), link({ id: "L2" })],
      7,
    );
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("justo en el limite no bloquea (7.0 <= 7)", () => {
    const links = Array.from({ length: 7 }, (_, i) =>
      link({ id: `L${i}`, acceptedAtMs: 1000 + i }));
    expect(selectLinksToBlock(links, 7).block).toEqual([]);
  });

  it("conserva los mas RECIENTES y bloquea el excedente", () => {
    // Free (2): 4 activos. Se conservan los 2 de acceptedAt mas alto.
    const links = [
      link({ id: "viejo1", acceptedAtMs: 100 }),
      link({ id: "viejo2", acceptedAtMs: 200 }),
      link({ id: "nuevo1", acceptedAtMs: 900 }),
      link({ id: "nuevo2", acceptedAtMs: 800 }),
    ];
    const r = selectLinksToBlock(links, 2);
    expect(r.block.sort()).toEqual(["viejo1", "viejo2"]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("los pausados pesan 0.5 y por eso entran mas", () => {
    // Limite 2: un activo (1.0) + dos pausados (0.5+0.5) = 2.0 exacto.
    const links = [
      link({ id: "act", acceptedAtMs: 900 }),
      link({ id: "pau1", status: "paused", acceptedAtMs: 800 }),
      link({ id: "pau2", status: "paused", acceptedAtMs: 700 }),
      link({ id: "sobra", acceptedAtMs: 100 }),
    ];
    const r = selectLinksToBlock(links, 2);
    expect(r.block).toEqual(["sobra"]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("NO reconsidera los que ya estaban bloqueados", () => {
    // Un blocked no cuenta para la carga y tampoco se re-reporta: bloquearlo
    // de nuevo generaria una escritura inutil en cada barrido.
    const links = [
      link({ id: "ya", entitlement: "blocked", acceptedAtMs: 100 }),
      link({ id: "act", acceptedAtMs: 900 }),
    ];
    const r = selectLinksToBlock(links, 2);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(1.0);
  });

  it("ignora terminated y pending (no pesan, no se bloquean)", () => {
    const links = [
      link({ id: "term", status: "terminated", acceptedAtMs: 100 }),
      link({ id: "pend", status: "pending", acceptedAtMs: 200 }),
      link({ id: "act", acceptedAtMs: 900 }),
    ];
    const r = selectLinksToBlock(links, 2);
    expect(r.block).toEqual([]);
  });

  it("dedupea por atleta: dos vinculos al mismo alumno cuentan una vez", () => {
    // Mismo criterio que computeWeightedLoad — si no, un alumno con un vinculo
    // duplicado consumiria doble cupo y bloquearia a otro sin motivo.
    const links = [
      link({ id: "d1", athleteId: "mismo", acceptedAtMs: 900 }),
      link({ id: "d2", athleteId: "mismo", status: "paused", acceptedAtMs: 800 }),
      link({ id: "otro", athleteId: "otro", acceptedAtMs: 700 }),
    ];
    const r = selectLinksToBlock(links, 2);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("desempata por id cuando acceptedAt coincide (determinista)", () => {
    // Sin desempate estable, dos barridos consecutivos podrian bloquear a
    // personas distintas con los mismos datos.
    const links = [
      link({ id: "b", acceptedAtMs: 500 }),
      link({ id: "a", acceptedAtMs: 500 }),
      link({ id: "c", acceptedAtMs: 500 }),
    ];
    const r1 = selectLinksToBlock(links, 1);
    const r2 = selectLinksToBlock([...links].reverse(), 1);
    expect(r1.block).toEqual(r2.block);
  });

  it("acceptedAt ausente se trata como el mas viejo", () => {
    const links = [
      link({ id: "sinFecha", acceptedAtMs: null }),
      link({ id: "conFecha", acceptedAtMs: 100 }),
    ];
    expect(selectLinksToBlock(links, 1).block).toEqual(["sinFecha"]);
  });
});
