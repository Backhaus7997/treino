/**
 * firestore-en-memoria.ts — un Firestore de mentira con transacciones OPTIMISTAS
 * de verdad, para los tests de los trámites que canjean un token.
 *
 * Cada documento lleva una versión; `runTransaction` reintenta si algo que leyó
 * cambió antes de commitear, que es lo que hace el servidor real. Sin eso, la
 * prueba de los dos clicks simultáneos pasaría por construcción.
 *
 * `control.fallaCola` hace que crear un documento en `mail_queue` tire, y se
 * puede prender y apagar a mitad de un test: es lo que permite probar que un
 * aviso perdido no se pierde en silencio y que el reintento lo recupera.
 *
 * (`mp-baja-por-mail.test.ts` tiene su propia copia de esto, de antes de que
 * hubiera un segundo consumidor. Se puede migrar a este archivo.)
 */

import type { App } from "firebase-admin/app";

export type Doc = Record<string, unknown>;
export type Store = Record<string, Record<string, Doc>>;

export interface ControlDeLaCola {
  /** Mientras sea `true`, crear un doc en `mail_queue` tira UNAVAILABLE. */
  fallaCola: boolean;
}

export function fakeApp(seed: Store = {}) {
  const store: Store = {};
  const version: Record<string, number> = {};
  const control: ControlDeLaCola = { fallaCola: false };
  /** Cada escritura, en orden: `col/id`. */
  const escritas: string[] = [];
  for (const [c, docs] of Object.entries(seed)) {
    store[c] = {};
    for (const [id, d] of Object.entries(docs)) store[c][id] = { ...d };
  }
  const key = (col: string, id: string) => `${col}/${id}`;
  const bump = (col: string, id: string) => {
    version[key(col, id)] = (version[key(col, id)] ?? 0) + 1;
  };
  const write = (col: string, id: string, d: Doc | undefined) => {
    store[col] = store[col] ?? {};
    if (d === undefined) delete store[col][id];
    else store[col][id] = d;
    bump(col, id);
    escritas.push(key(col, id));
  };
  const snapOf = (col: string, id: string) => {
    const d = store[col]?.[id];
    return { id, exists: d !== undefined, data: () => (d ? { ...d } : undefined) };
  };

  const docRef = (col: string, id: string) => ({
    id,
    __col: col,
    get: async () => snapOf(col, id),
    set: async (data: Doc) => {
      write(col, id, { ...(store[col]?.[id] ?? {}), ...data });
    },
    create: async (data: Doc) => {
      if (control.fallaCola && col === "mail_queue") throw new Error("UNAVAILABLE");
      if (store[col]?.[id] !== undefined) {
        throw Object.assign(new Error("ALREADY_EXISTS"), { code: 6 });
      }
      write(col, id, { ...data });
    },
    update: async (data: Doc) => {
      if (store[col]?.[id] === undefined) throw new Error("NOT_FOUND");
      write(col, id, { ...store[col][id], ...data });
    },
    delete: async () => write(col, id, undefined),
  });
  type Ref = ReturnType<typeof docRef>;

  const filtrada = (col: string, filtros: [string, unknown][]) => ({
    where: (campo: string, _op: string, valor: unknown) =>
      filtrada(col, [...filtros, [campo, valor]]),
    limit: () => filtrada(col, filtros),
    get: async () => {
      const docs = Object.entries(store[col] ?? {})
        .filter(([, d]) => filtros.every(([c, v]) => d[c] === v))
        .map(([id, d]) => ({ id, exists: true, data: () => d }));
      return { empty: docs.length === 0, docs, size: docs.length };
    },
  });

  const runTransaction = async <T>(fn: (tx: unknown) => Promise<T>): Promise<T> => {
    for (let intento = 0; intento < 10; intento++) {
      const leidas: Record<string, number> = {};
      // `undefined` = borrar el documento.
      const escrituras: [Ref, Doc | undefined][] = [];
      const tx = {
        get: async (ref: Ref) => {
          leidas[key(ref.__col, ref.id)] = version[key(ref.__col, ref.id)] ?? 0;
          // Un tick en el medio: deja que la otra transacción lea también.
          await new Promise((r) => setImmediate(r));
          return snapOf(ref.__col, ref.id);
        },
        update: (ref: Ref, data: Doc) => {
          escrituras.push([ref, data]);
        },
        // Siempre con merge: es como lo usan los tramites de este repo.
        set: (ref: Ref, data: Doc) => {
          escrituras.push([ref, data]);
        },
        delete: (ref: Ref) => {
          escrituras.push([ref, undefined]);
        },
      };
      const r = await fn(tx);
      const conflicto = Object.entries(leidas)
        .some(([k, v]) => (version[k] ?? 0) !== v);
      if (conflicto) continue;
      for (const [ref, data] of escrituras) {
        if (data === undefined) write(ref.__col, ref.id, undefined);
        else write(ref.__col, ref.id, { ...(store[ref.__col]?.[ref.id] ?? {}), ...data });
      }
      return r;
    }
    throw new Error("demasiados reintentos");
  };

  const app = {
    firestore: () => ({
      collection: (col: string) => ({
        doc: (id: string) => docRef(col, id),
        where: (campo: string, _op: string, valor: unknown) =>
          filtrada(col, [[campo, valor]]),
      }),
      runTransaction,
    }),
  } as unknown as App;
  return { app, store, escritas, control };
}
