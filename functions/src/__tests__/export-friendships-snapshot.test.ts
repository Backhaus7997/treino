/**
 * Unit tests for the pure payload builder behind the friendships snapshot.
 * No emulator / Firestore — just the shape and the fidelity guarantees.
 *
 * Este snapshot ES el mecanismo de reversibilidad de toda la migración a
 * `follows` (M-01): si el script de migración tuviera un bug destructivo, este
 * archivo es la única copia del mapeo original fuera de Firestore. Por eso los
 * tests de acá no miran "que ande" — miran que NO SE PIERDA NI SE TRANSFORME
 * NADA, incluidos los documentos que la migración después va a descartar.
 */

import { buildSnapshotPayload } from "../../scripts/export-friendships-snapshot";

const AT = "2026-08-04T12:00:00.000Z";

describe("buildSnapshotPayload", () => {
  it("devuelve la forma exacta { exportedAt, count, docs }", () => {
    const payload = buildSnapshotPayload(
      [
        { id: "a_b", data: { members: ["a", "b"], status: "accepted" } },
        { id: "c_d", data: { members: ["c", "d"], status: "pending" } },
      ],
      AT,
    );

    expect(payload).toEqual({
      exportedAt: AT,
      count: 2,
      docs: [
        { id: "a_b", data: { members: ["a", "b"], status: "accepted" } },
        { id: "c_d", data: { members: ["c", "d"], status: "pending" } },
      ],
    });
  });

  it("una colección vacía da count 0 y docs vacío, no null", () => {
    const payload = buildSnapshotPayload([], AT);

    expect(payload.count).toBe(0);
    expect(payload.docs).toEqual([]);
  });

  it("`count` siempre coincide con la cantidad de docs", () => {
    // Si estos dos se separan, la verificación de paridad de la migración
    // (M-06 ①) compara contra un número que no describe el archivo.
    for (const n of [0, 1, 7, 50]) {
      const docs = Array.from({ length: n }, (_, i) => ({
        id: `f${i}`,
        data: { members: [`u${i}`, "x"], status: "accepted" },
      }));
      expect(buildSnapshotPayload(docs, AT).count).toBe(n);
    }
  });

  it("copia el body crudo VERBATIM, sin normalizar ni descartar campos", () => {
    // El snapshot no puede opinar sobre la forma del dato: si el doc tiene
    // campos legacy o inesperados, se guardan igual. Son parte del original.
    const raw = {
      members: ["a", "b"],
      status: "accepted",
      requesterId: "a",
      createdAt: { _seconds: 1, _nanoseconds: 2 },
      campoLegacyQueNadieRecuerda: 42,
      nulo: null,
    };

    const payload = buildSnapshotPayload([{ id: "a_b", data: raw }], AT);

    expect(payload.docs[0].data).toEqual(raw);
  });

  it("INCLUYE los documentos malformados — el snapshot no filtra", () => {
    // La migración los excluye del `--apply` a propósito, pero el snapshot es
    // la única copia del original: filtrarlos acá los perdería para siempre.
    const malformados = [
      { id: "sin-requester", data: { members: ["a", "b"], status: "accepted" } },
      { id: "un-solo-miembro", data: { members: ["a"], requesterId: "a" } },
      { id: "sin-members", data: { requesterId: "a", status: "accepted" } },
      { id: "vacio", data: {} },
    ];

    const payload = buildSnapshotPayload(malformados, AT);

    expect(payload.count).toBe(4);
    expect(payload.docs.map((d) => d.id)).toEqual([
      "sin-requester",
      "un-solo-miembro",
      "sin-members",
      "vacio",
    ]);
  });

  it("preserva el orden de entrada", () => {
    const ids = ["z", "a", "m", "b"];
    const payload = buildSnapshotPayload(
      ids.map((id) => ({ id, data: { status: "accepted" } })),
      AT,
    );

    expect(payload.docs.map((d) => d.id)).toEqual(ids);
  });

  it("no muta la entrada", () => {
    const docs = [{ id: "a_b", data: { members: ["a", "b"] } }];
    const copia = JSON.parse(JSON.stringify(docs));

    buildSnapshotPayload(docs, AT);

    expect(docs).toEqual(copia);
  });

  it("el payload sobrevive un round-trip por JSON sin perder nada", () => {
    // Es literalmente lo que le va a pasar: se escribe a disco y se lee de
    // vuelta el día que haga falta revertir.
    const docs = [
      { id: "a_b", data: { members: ["a", "b"], status: "accepted", n: 0 } },
    ];

    const payload = buildSnapshotPayload(docs, AT);

    expect(JSON.parse(JSON.stringify(payload))).toEqual(payload);
  });
});
