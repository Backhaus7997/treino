/**
 * El mail al PF que chocó un tope de su plan: ejercicios propios
 * (limite-ejercicios-pf.md §3 PR4), plantillas (limite-plantillas-pf.md §3
 * PR4), o alumnos (paywall Fase 7 — `syncTrainerLoad`/`promote-link.ts`).
 *
 * ── QUE CUIDA ESTE ARCHIVO ────────────────────────────────────────────────
 *
 * Las mismas cuatro cláusulas que `free-limit-mail.test.ts`, con la 3ª
 * adaptada: acá no hay "¿ya paga?" sino "¿sigue en el tope?", leído de
 * `planLimits.<clave>` / `<campo de uso>.count` para ejercicios/plantillas, y
 * del límite efectivo de `effective-limit.ts` + `weightedLoad` para alumnos.
 *
 *   1. Sin anotación → silencio.
 *   2. Anotación vieja → silencio.
 *   3. Ya no está en el tope (count < limit, o límite null/ausente) → silencio.
 *   4. Enfriamiento de 14 días, POR KIND → silencio.
 *
 * Las cuatro corren UNA VEZ POR TOPE homogéneo (`describe.each` sobre
 * ejercicios/plantillas, que comparten forma de fixture), porque son el
 * mismo módulo generalizado por `kind` (`CAMPOS_POR_KIND`) resolviendo la
 * MISMA lógica sobre datos distintos — un bug en un tope y no en el otro es
 * exactamente lo que ese `describe.each` está para agarrar. El kind
 * `students` lee de un lugar totalmente distinto (`subscription` +
 * `weightedLoad`, no `planLimits`), así que tiene su propio bloque más abajo.
 *
 * Sección aparte, "el enfriamiento es POR KIND", cubre lo que cambió en
 * #1267: el enfriamiento de 14 días dejó de ser compartido entre topes —
 * chocar uno ya NO silencia el mail de otro— con su compatibilidad para el
 * `trainerLimitMailAt` legado (un Timestamp suelto, no un mapa).
 */

import {
  decideTrainerLimitMail,
  enqueueTrainerLimitMail,
  registrarTopeDeAlumnos,
  incrementoDeAlumnos,
  esTopeDeAlumnos,
  VENTANA_MS,
  ENFRIAMIENTO_MS,
  CAMPO_TOPE_AT,
  CAMPO_TOPE_KIND,
  CAMPO_TOPE_INCREMENTO,
  CAMPO_TOPE_LINK_ID,
  CAMPO_MAIL_AT,
  TRAINER_LIMIT_PREF_KEY,
} from "../subscriptions/trainer-limit-mail";
import { ATHLETE_PROSPECT_PREF_KEY } from "../subscriptions/athlete-prospect-mail";
import { enqueueMail } from "../mail/enqueue-mail";
import { KINDS_DE_PUBLICIDAD } from "../mail/types";
import { renderMail, trainerWebCheckout, cupoLabel } from "../mail/templates";
import { HttpsError } from "firebase-functions/v2/https";
import type { App } from "firebase-admin/app";

jest.mock("../mail/enqueue-mail", () => ({
  ...jest.requireActual("../mail/enqueue-mail"),
  enqueueMail: jest.fn(async () => "queued-id"),
}));

/**
 * Fake de Firestore para `users/{uid}`, compartido entre el `runTransaction`
 * de la reserva y el chequeo de la cola tras un encolado fallido.
 *
 * `runTransactionMock` serializa las transacciones con un mutex: la SEGUNDA
 * no arranca (ni siquiera su primer `get`) hasta que la PRIMERA terminó
 * enteramente — misma garantía que da Firestore de verdad sobre el mismo
 * documento, y lo que hace falta para que el test de la carrera (más abajo)
 * pueda ver a la segunda transacción toparse con la reserva de la primera.
 *
 * `trainerLinksStore` es NUEVO (hallazgo P2 sobre #1267): simula
 * `trainer_links`, que `reservarEnfriamiento` ahora consulta DENTRO de la
 * transacción —vía `readTrainerLinks`, `promote-link.ts`— para el kind
 * `students`. `tx.get` distingue una ref de DOCUMENTO (`users/{uid}`) de una
 * ref de QUERY (`trainer_links.where(...)`) por la forma del `FakeRef`.
 */
let usersStore: Record<string, Record<string, unknown> | undefined> = {};
let trainerLinksStore: Record<
  string,
  Array<{ athleteId: string; status: string; entitlement?: string }>
> = {};
let colaExiste = false;
const colaGetMock = jest.fn(async () => ({ exists: colaExiste }));
const DELETE_SENTINEL = Symbol("FieldValue.delete()");

interface FakeDocRef {
  kind: "doc";
  uid: string;
}
interface FakeQueryRef {
  kind: "query";
  trainerId: string;
}
type FakeRef = FakeDocRef | FakeQueryRef;
interface FakeTx {
  get: (
    ref: FakeRef,
  ) => Promise<
    | { data: () => Record<string, unknown> | undefined }
    | { docs: Array<{ id: string; data: () => Record<string, unknown> }> }
  >;
  set: (ref: FakeDocRef, patch: Record<string, unknown>) => void;
  update: (ref: FakeDocRef, patch: Record<string, unknown>) => void;
}

let mutex: Promise<unknown> = Promise.resolve();
const runTransactionMock = jest.fn((fn: (tx: FakeTx) => Promise<unknown>) => {
  const tx: FakeTx = {
    get: async (ref) => {
      if (ref.kind === "query") {
        const links = trainerLinksStore[ref.trainerId] ?? [];
        return { docs: links.map((link, i) => ({ id: `link-${i}`, data: () => link })) };
      }
      return { data: () => usersStore[ref.uid] };
    },
    set: (ref, patch) => {
      usersStore[ref.uid] = { ...(usersStore[ref.uid] ?? {}), ...patch };
    },
    update: (ref, patch) => {
      const next = { ...(usersStore[ref.uid] ?? {}) };
      for (const [k, v] of Object.entries(patch)) {
        if (v === DELETE_SENTINEL) delete next[k];
        else next[k] = v;
      }
      usersStore[ref.uid] = next;
    },
  };
  const run = mutex.then(() => fn(tx));
  mutex = run.catch(() => undefined);
  return run;
});

/** Mismo merge + sentinel de borrado que usa el `tx.set` de arriba, pero para
 * escrituras SIN transacción (`registrarTopeDeAlumnos`, deliberadamente sin
 * `tx` — ver su docstring). */
function setDirecto(uid: string, patch: Record<string, unknown>) {
  const next = { ...(usersStore[uid] ?? {}) };
  for (const [k, v] of Object.entries(patch)) {
    if (v === DELETE_SENTINEL) delete next[k];
    else next[k] = v;
  }
  usersStore[uid] = next;
}

jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  FieldValue: { delete: () => DELETE_SENTINEL },
  getFirestore: () => ({
    collection: (name: string) => {
      if (name === "users") {
        return {
          doc: (uid: string) => ({
            kind: "doc",
            uid,
            set: (patch: Record<string, unknown>) => setDirecto(uid, patch),
          }),
        };
      }
      if (name === "trainer_links") {
        return {
          where: (_field: string, _op: string, trainerId: string) => ({
            kind: "query",
            trainerId,
          }),
        };
      }
      return { doc: () => ({ get: colaGetMock }) };
    },
    runTransaction: runTransactionMock,
  }),
}));

/** Popula `trainer_links` en vivo para un trainer — ver `trainerLinksStore`. */
function vinculos(
  trainerId: string,
  links: Array<{ athleteId: string; status: string; entitlement?: string }>,
) {
  trainerLinksStore[trainerId] = links;
}

const enqueueMock = enqueueMail as jest.MockedFunction<typeof enqueueMail>;
const APP = {} as App;
const AHORA = Date.UTC(2026, 8, 24, 8, 0, 0);

/** Un `Timestamp` de Firestore, sólo con lo que el módulo le pide. */
const ts = (ms: number) => ({ toMillis: () => ms });

/**
 * La tabla que maneja este archivo: un caso por tope HOMOGÉNEO (los que leen
 * `planLimits.<clave>` / `<campo de uso>.count`), con todo lo que
 * `CAMPOS_POR_KIND` resuelve internamente. `students` no entra acá — lee de
 * `subscription`/`weightedLoad`, no de `planLimits` — y tiene su propio
 * bloque más abajo.
 */
const TOPES = [
  {
    nombre: "ejercicios propios",
    tope: "customExercises",
    mailKind: "exercise-limit-reached",
    limitField: "planLimits",
    limitKey: "customExercises",
    usageField: "customExerciseUsage",
  },
  {
    nombre: "plantillas",
    tope: "templates",
    mailKind: "template-limit-reached",
    limitField: "planLimits",
    limitKey: "templates",
    usageField: "templateUsage",
  },
] as const;

/** El PF que chocó el tope hace una hora y sigue exactamente en él. */
function chocoRecien(t: (typeof TOPES)[number], limit = 20) {
  return {
    [CAMPO_TOPE_AT]: ts(AHORA - 60 * 60 * 1000),
    [CAMPO_TOPE_KIND]: t.tope,
    planLimits: { [t.limitKey]: limit },
    [t.usageField]: { count: limit },
  };
}

beforeEach(() => {
  enqueueMock.mockClear();
  colaGetMock.mockClear();
  runTransactionMock.mockClear();
  colaExiste = false;
  usersStore = {};
  trainerLinksStore = {};
  mutex = Promise.resolve();
});

describe.each(TOPES)("$nombre", (t) => {
  const CHOCO_RECIEN = chocoRecien(t);

  describe("⚠️ las cuatro cláusulas del silencio", () => {
    it("sin anotación no manda", () => {
      expect(
        decideTrainerLimitMail(
          { role: "trainer", planLimits: { [t.limitKey]: 20 } },
          AHORA,
          "t1",
        ),
      ).toBeNull();
    });

    it("⚠️ una anotación vieja no manda", () => {
      const viejo = { ...CHOCO_RECIEN, [CAMPO_TOPE_AT]: ts(AHORA - VENTANA_MS - 1) };
      expect(decideTrainerLimitMail(viejo, AHORA, "t1")).toBeNull();
    });

    it("⚠️ quien ya NO está en el tope (bajó el contador) no recibe la oferta", () => {
      const bajoElTope = {
        ...CHOCO_RECIEN,
        [t.usageField]: { count: 19 },
      };
      expect(decideTrainerLimitMail(bajoElTope, AHORA, "t1")).toBeNull();
    });

    it("⚠️ quien ya NO tiene tope (subió de plan, límite null) no recibe la oferta", () => {
      const sinTope = {
        ...CHOCO_RECIEN,
        planLimits: { [t.limitKey]: null },
      };
      expect(decideTrainerLimitMail(sinTope, AHORA, "t1")).toBeNull();
    });

    it("⚠️ un límite ausente tampoco manda — interruptor apagado o sin primer sync", () => {
      const sinPlanLimits = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: t.tope,
        [t.usageField]: { count: 999 },
      };
      expect(decideTrainerLimitMail(sinPlanLimits, AHORA, "t1")).toBeNull();
    });

    it("⚠️ el ENFRIAMIENTO: no se le escribe dos veces en catorce días", () => {
      const yaEscrito = {
        ...CHOCO_RECIEN,
        [CAMPO_MAIL_AT]: { [t.tope]: ts(AHORA - ENFRIAMIENTO_MS + 1) },
      };
      expect(decideTrainerLimitMail(yaEscrito, AHORA, "t1")).toBeNull();
    });

    it("pasado el enfriamiento sí vuelve a mandar", () => {
      const viejoMail = {
        ...CHOCO_RECIEN,
        [CAMPO_MAIL_AT]: { [t.tope]: ts(AHORA - ENFRIAMIENTO_MS - 1) },
      };
      expect(decideTrainerLimitMail(viejoMail, AHORA, "t1")).not.toBeNull();
    });
  });

  describe("cuando sí manda", () => {
    it("el tope tocado, el kind del mail y el límite viajan en el plan", () => {
      const plan = decideTrainerLimitMail(CHOCO_RECIEN, AHORA, "t1");
      expect(plan?.kind).toBe(t.mailKind);
      expect(plan?.tope).toBe(t.tope);
      expect(plan?.limit).toBe(20);
      expect(plan?.scope).toMatch(/^tope_/);
    });

    it("exactamente EN el tope (count == limit) manda — E6, no hace falta pasarse", () => {
      // El create que deja el contador en 20 pasa; el siguiente no. El mail
      // tiene que dispararse desde ahí, no sólo cuando ya se pasó.
      expect(decideTrainerLimitMail(CHOCO_RECIEN, AHORA, "t1")).not.toBeNull();
    });

    it("por ENCIMA del tope (bajó de plan) también manda", () => {
      const sobreElTope = {
        ...CHOCO_RECIEN,
        planLimits: { [t.limitKey]: 20 },
        [t.usageField]: { count: 35 },
      };
      expect(decideTrainerLimitMail(sobreElTope, AHORA, "t1")).not.toBeNull();
    });

    it("un límite corrupto (no numérico) no manda — mismo criterio fail-closed que la regla", () => {
      const corrupto = {
        ...CHOCO_RECIEN,
        planLimits: { [t.limitKey]: "20" },
      };
      expect(decideTrainerLimitMail(corrupto, AHORA, "t1")).toBeNull();
    });

    it("⚠️ lleva prefKey — es comunicación comercial", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(enqueueMock.mock.calls[0][1].prefKey).toBe(TRAINER_LIMIT_PREF_KEY);
      // Mismo valor que el del alumno — ver el encabezado del módulo.
      expect(TRAINER_LIMIT_PREF_KEY).toBe(ATHLETE_PROSPECT_PREF_KEY);
    });

    it("⚠️ el kind encolado está en KINDS_DE_PUBLICIDAD: sale con «Publicidad: » en el asunto", async () => {
      // Comercial + opt-out = Disp. DNPDP 4/2009, art. 2 (decisión del
      // 2026-10-02). Corre para los tres topes (`describe.each(TOPES)`): el
      // kind que se encola es el de cada uno.
      usersStore["t1"] = { ...CHOCO_RECIEN };
      await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(enqueueMock.mock.calls[0][1].kind).toBe(t.mailKind);
      expect(KINDS_DE_PUBLICIDAD).toContain(enqueueMock.mock.calls[0][1].kind);
    });

    it("⚠️ el CTA va al Coach Hub web, no al App Link de la app", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      await enqueueTrainerLimitMail(APP, "t1", AHORA);
      const url = String(enqueueMock.mock.calls[0][1].params.ctaUrl);
      expect(url).toBe(trainerWebCheckout());
      // No es el App Link: en el teléfono abre la app, y la app no vende.
      expect(url).not.toContain("/abrir/");
      expect(url).toContain("to=facturacion");
    });

    it("⚠️ el limite viaja como param para el template", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(enqueueMock.mock.calls[0][1].params.limit).toBe(20);
    });

    it("⚠️ reserva (anota) el enfriamiento ANTES de encolar, no después", async () => {
      // Antes: `enqueueTrainerLimitMail` encolaba y RECIÉN DESPUÉS anotaba el
      // enfriamiento. Se invirtió (#1264, hallazgo P2 de Codex) para cerrar
      // la carrera dentro del MISMO kind: ver "DOS CAMINOS" en el encabezado
      // del módulo. Este test verifica el orden nuevo directamente: en el
      // momento en que `enqueueMail` es invocado, la reserva ya tiene que
      // estar escrita en `users/{uid}`.
      usersStore["t1"] = { ...CHOCO_RECIEN };
      enqueueMock.mockImplementationOnce(async () => {
        const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as
          | Record<string, unknown>
          | undefined;
        expect(mailAt?.[t.tope]).toBeDefined();
        return "queued-id";
      });
      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan).not.toBeNull();
      expect(enqueueMock).toHaveBeenCalledTimes(1);
    });

    it("⚠️ si el encolado FALLÓ de verdad, deshace la reserva y tira (el barrido lo cuenta como fallido)", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      enqueueMock.mockResolvedValueOnce(null);
      colaExiste = false;
      await expect(enqueueTrainerLimitMail(APP, "t1", AHORA)).rejects.toThrow();
      // la reserva quedó deshecha: no hay enfriamiento anotado sobre un mail
      // que nunca salió.
      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as
        | Record<string, unknown>
        | undefined;
      expect(mailAt?.[t.tope]).toBeUndefined();
    });

    it("⚠️ si el rollback llega tarde —otra reserva más nueva ya pisó el campo— no la toca", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      enqueueMock.mockResolvedValueOnce(null);
      colaExiste = false;
      // Simula otra corrida completa (otro `nowMs`) reservando de nuevo
      // mientras ésta seguía en el aire, justo antes de que el rollback
      // corra su propia transacción.
      colaGetMock.mockImplementationOnce(async () => {
        const mailAtPrevio = (usersStore["t1"]?.[CAMPO_MAIL_AT] ?? {}) as Record<
          string,
          unknown
        >;
        usersStore["t1"] = {
          ...usersStore["t1"],
          [CAMPO_MAIL_AT]: { ...mailAtPrevio, [t.tope]: ts(AHORA + 1000) },
        };
        return { exists: false };
      });
      await expect(enqueueTrainerLimitMail(APP, "t1", AHORA)).rejects.toThrow();
      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as Record<
        string,
        { toMillis(): number }
      >;
      expect(mailAt[t.tope].toMillis()).toBe(AHORA + 1000);
    });

    it("si el mail YA estaba en la cola (reintento), la reserva queda anotada igual", async () => {
      usersStore["t1"] = { ...CHOCO_RECIEN };
      enqueueMock.mockResolvedValueOnce(null);
      colaExiste = true;
      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan).not.toBeNull();
      expect(colaGetMock).toHaveBeenCalledTimes(1);
      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as
        | Record<string, unknown>
        | undefined;
      expect(mailAt?.[t.tope]).toBeDefined();
    });
  });
});

describe("⚠️ la carrera dentro del MISMO kind", () => {
  // Antes de la reserva transaccional: dos triggers casi simultáneos sobre el
  // mismo PF y el mismo tope — por ejemplo el trigger AL TOQUE y el barrido
  // superpuestos por un reintento— podían decidir cada uno sobre su propio
  // snapshot, sin verse uno a otro, y las dos llamadas a `enqueueMail`
  // comparten `kind`+`scope`+`toUid`, así que la dedupe de la cola las
  // hubiera bloqueado en el nivel equivocado (después de reservar dos veces
  // el enfriamiento).
  //
  // Ahora `enqueueTrainerLimitMail` relee `users/{uid}` FRESCO dentro de una
  // transacción antes de decidir: las dos transacciones leen el MISMO
  // documento, y Firestore las serializa — la segunda ve la reserva de la
  // primera y sale por la cláusula 4 (enfriamiento).
  it("dos llamadas concurrentes sobre el mismo PF y el mismo tope, sin " +
    "enfriamiento previo, producen UN solo mail", async () => {
    usersStore["t1"] = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "templates",
      planLimits: { customExercises: 20, templates: 3 },
      customExerciseUsage: { count: 20 },
      templateUsage: { count: 3 },
    };

    const [a, b] = await Promise.all([
      enqueueTrainerLimitMail(APP, "t1", AHORA),
      enqueueTrainerLimitMail(APP, "t1", AHORA),
    ]);

    const planesEnviados = [a, b].filter((p) => p !== null);
    expect(planesEnviados).toHaveLength(1);
    expect(enqueueMock).toHaveBeenCalledTimes(1);
    const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as
      | Record<string, unknown>
      | undefined;
    expect(mailAt?.templates).toBeDefined();
  });
});

describe("⚠️ la tabla de kinds", () => {
  it("un PF que choca los DOS topes en la misma ventana elige el kind que anotó", () => {
    // El fixture trae planLimits y usage de los dos topes a la vez — lo que
    // pasaría en producción si un PF está en el tope de ejercicios Y de
    // plantillas — pero `trainerLimitHitKind` sólo puede decir UNO: el
    // último que rebotó. `CAMPOS_POR_KIND` tiene que mirar ESE campo, no
    // "cuál de los dos está peor".
    const chocoLosDos = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "templates",
      planLimits: { customExercises: 20, templates: 3 },
      customExerciseUsage: { count: 20 },
      templateUsage: { count: 3 },
    };
    const plan = decideTrainerLimitMail(chocoLosDos, AHORA, "t1");
    expect(plan?.kind).toBe("template-limit-reached");
    expect(plan?.limit).toBe(3);
  });

  // ⚠️ FALLA CERRADO, no adivina. Antes de generalizar por `kind` había un
  // único tope posible, así que "no sé cuál" y "es el único que existe" eran
  // lo mismo — el fallback viejo aprovechaba eso. Con más de uno dejó de
  // serlo: adivinar `customExercises` para un PF que en realidad chocó
  // `templates` o `students` manda un mail con una afirmación falsa concreta
  // (hallazgo de la revisión adversarial de Codex, hilo
  // `01a0d934-760f-7763-9948-ba9bb43fe98a`).
  it("un kind desconocido (dato viejo o corrupto) NO manda — no hay forma de saber qué tope mirar", () => {
    const kindRaro = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "un-tope-que-no-existe",
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 20 },
    };
    expect(decideTrainerLimitMail(kindRaro, AHORA, "t1")).toBeNull();
  });

  it("una anotación sin `kind` tampoco manda — mismo criterio fail-closed", () => {
    const sinKind = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      planLimits: { customExercises: 20 },
      customExerciseUsage: { count: 20 },
    };
    expect(decideTrainerLimitMail(sinKind, AHORA, "t1")).toBeNull();
  });

  it("un kind desconocido no manda aunque el PF SÍ esté en el tope de plantillas", () => {
    // Control negativo: si el kind sin reconocer igual mirara `templates`
    // por error (o cualquier otro campo), este fixture mandaría. No debería
    // mandar NADA sin un kind reconocido, sea cual sea el dato disponible.
    const kindRaroConDatosDeTemplates = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "un-tope-que-no-existe",
      planLimits: { templates: 3 },
      templateUsage: { count: 3 },
    };
    expect(decideTrainerLimitMail(kindRaroConDatosDeTemplates, AHORA, "t1")).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// SUSCRIPCIÓN INACTIVA → silencio, los TRES kinds — hallazgo de Codex sobre
// #1267 (P1). Ver el encabezado del módulo, cláusula 4 nueva, y
// `suscripcionInactiva` en `effective-limit.ts` para las reglas exactas.
// ---------------------------------------------------------------------------
describe("⚠️ suscripción inactiva → no se manda el upsell (los tres kinds)", () => {
  describe.each(TOPES)("$nombre", (t) => {
    const conSubscription = (subscription: Record<string, unknown>) => ({
      ...chocoRecien(t),
      subscription,
    });

    it("suscripción `paused` no manda", () => {
      expect(
        decideTrainerLimitMail(conSubscription({ tier: "plan2", status: "paused" }), AHORA, "t1"),
      ).toBeNull();
    });

    it("suscripción `active` sí manda — el caso normal no se rompió", () => {
      expect(
        decideTrainerLimitMail(conSubscription({ tier: "plan2", status: "active" }), AHORA, "t1"),
      ).not.toBeNull();
    });

    // Suscripción ILEGIBLE (`degraded` en `toSubscriptionState`): no se sabe
    // si el PF paga, así que no se le manda un upsell de tope. Hallazgo de
    // Codex sobre #1267 (tercera ronda).
    it("⚠️ `subscription` que no es un mapa no manda (falla cerrado)", () => {
      expect(decideTrainerLimitMail(conSubscription("roto" as unknown as Record<string, unknown>), AHORA, "t1")).toBeNull();
    });

    it("⚠️ `subscription` con un tier desconocido y status `active` no manda", () => {
      expect(
        decideTrainerLimitMail(conSubscription({ tier: "plan9", status: "active" }), AHORA, "t1"),
      ).toBeNull();
    });

    it("sin `subscription` (nunca se suscribió) sí manda — Free NO es inactiva", () => {
      // Ver `suscripcionInactiva`: sin mapa es el PF Free normal, el
      // destinatario correcto del upsell — no hay ningún cobro que
      // recuperarle.
      expect(decideTrainerLimitMail(chocoRecien(t), AHORA, "t1")).not.toBeNull();
    });
  });

  // El caso que originó el hallazgo (Codex, sobre #1267): un PF con un plan
  // pago pero la suscripción no al día chocando el tope de ALUMNOS. Cubre acá
  // las CUATRO variantes de "inactiva"/"activa" que resuelve
  // `suscripcionInactiva` — los otros dos kinds ya probaron `paused`/`active`
  // arriba, así que no hace falta repetir la matriz completa por kind.
  describe("alumnos", () => {
    const base = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "students",
    };

    it("suscripción `paused` no manda (aunque la carga en vivo siga en el tope REDUCIDO a Free)", () => {
      const doc = { ...base, subscription: { tier: "plan1", status: "paused" } };
      // limite efectivo con `paused` = Free (2). Si la cláusula nueva no
      // filtrara, esto mandaría igual (2 >= 2) — lo que prueba que es LA
      // CLÁUSULA DE INACTIVA la que bloquea, no la 3 (sigueEnElTope).
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2)).toBeNull();
    });

    it("suscripción `pending` no manda", () => {
      const doc = { ...base, subscription: { tier: "plan1", status: "pending" } };
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2)).toBeNull();
    });

    // ── EL PISO PREPAGO — hallazgo de Codex sobre #1267 (P2 de esta ronda) ──
    // `suscripcionInactiva` ya no mira sólo `status`: un `paused` con un piso
    // prepago vigente del MISMO plan sigue sostenido en ese plan pago, así
    // que SÍ puede chocar su tope legítimamente. Ver el docblock de
    // `suscripcionInactiva` en `effective-limit.ts`.
    it("`paused` CON piso prepago vigente del mismo plan sí manda — no es inactiva", () => {
      const doc = {
        ...base,
        subscription: {
          tier: "plan1",
          status: "paused",
          prepaidTier: "plan1",
          prepaidUntil: ts(AHORA + 1000),
        },
      };
      // El límite efectivo con el piso es el de plan1 (7) — carga en vivo 7
      // para estar exactamente en ESE tope.
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 7)).not.toBeNull();
    });

    it("`paused` con el piso ya VENCIDO no manda — mismo resultado que sin piso", () => {
      const doc = {
        ...base,
        subscription: {
          tier: "plan1",
          status: "paused",
          prepaidTier: "plan1",
          prepaidUntil: ts(AHORA - 1000),
        },
      };
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2)).toBeNull();
    });

    it("`cancelled` con período YA VENCIDO no manda", () => {
      const doc = {
        ...base,
        subscription: {
          tier: "plan1",
          status: "cancelled",
          currentPeriodEnd: ts(AHORA - 1000),
        },
      };
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2)).toBeNull();
    });

    it("`cancelled` con período TODAVÍA VIGENTE sí manda — no es CUALQUIER cancelled", () => {
      const doc = {
        ...base,
        subscription: {
          tier: "plan1",
          status: "cancelled",
          currentPeriodEnd: ts(AHORA + 1000),
        },
      };
      // Con `cancelled` vigente el límite efectivo sigue siendo el nominal
      // de plan1 (7) — carga en vivo 7 para estar exactamente en ESE tope.
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 7)).not.toBeNull();
    });

    it("suscripción `active` sí manda", () => {
      const doc = { ...base, subscription: { tier: "plan1", status: "active" } };
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 7)).not.toBeNull();
    });

    it("suscripción `grace` sí manda — conserva el límite pagado", () => {
      const doc = { ...base, subscription: { tier: "plan1", status: "grace" } };
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 7)).not.toBeNull();
    });

    it("sin `subscription` (Free, nunca se suscribió) sí manda", () => {
      expect(decideTrainerLimitMail(base, AHORA, "t1", undefined, 2)).not.toBeNull();
    });

    it("⚠️ de punta a punta: un PF `paused` con vínculos en vivo en el tope reducido no recibe el mail", async () => {
      // Mismo caso que arriba, pero pasando por `enqueueTrainerLimitMail` →
      // `reservarEnfriamiento`, con la carga en vivo saliendo de verdad de
      // `trainer_links` (no simulada a mano).
      usersStore["t1"] = {
        ...base,
        subscription: { tier: "plan1", status: "paused" },
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" },
        { athleteId: "a2", status: "active" },
      ]); // computeWeightedLoad = 2.0 == límite Free reducido

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan).toBeNull();
    });
  });
});

// ---------------------------------------------------------------------------
// El enfriamiento es POR KIND (#1267) — ver el encabezado del módulo.
// ---------------------------------------------------------------------------
describe("⚠️ el enfriamiento es POR KIND, no compartido", () => {
  it("chocar ejercicios y, dentro de los 14 días, plantillas — manda DOS mails, uno de cada uno", async () => {
    // t0: choca ejercicios, manda, reserva `trainerLimitMailAt.customExercises`.
    usersStore["t1"] = chocoRecien(TOPES[0]);
    const planEjercicios = await enqueueTrainerLimitMail(APP, "t1", AHORA);
    expect(planEjercicios?.kind).toBe("exercise-limit-reached");
    expect(enqueueMock).toHaveBeenCalledTimes(1);

    // t0 + 1 día: el MISMO PF choca plantillas. Si el enfriamiento siguiera
    // compartido, esto no mandaría nada — es justo lo que #1267 corrige.
    const unDiaDespues = AHORA + 24 * 60 * 60 * 1000;
    usersStore["t1"] = {
      ...usersStore["t1"],
      [CAMPO_TOPE_AT]: ts(unDiaDespues - 1000),
      [CAMPO_TOPE_KIND]: "templates",
      planLimits: {
        ...(usersStore["t1"]?.planLimits as Record<string, unknown>),
        templates: 3,
      },
      templateUsage: { count: 3 },
    };
    const planPlantillas = await enqueueTrainerLimitMail(APP, "t1", unDiaDespues);
    expect(planPlantillas?.kind).toBe("template-limit-reached");
    expect(enqueueMock).toHaveBeenCalledTimes(2);

    // Las dos reservas conviven en el mismo mapa.
    const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as Record<string, unknown>;
    expect(mailAt.customExercises).toBeDefined();
    expect(mailAt.templates).toBeDefined();
  });

  it("el MISMO kind dos veces dentro de los 14 días manda UN solo mail", async () => {
    usersStore["t1"] = chocoRecien(TOPES[0]);
    const primero = await enqueueTrainerLimitMail(APP, "t1", AHORA);
    expect(primero).not.toBeNull();

    const unDiaDespues = AHORA + 24 * 60 * 60 * 1000;
    usersStore["t1"] = {
      ...usersStore["t1"],
      [CAMPO_TOPE_AT]: ts(unDiaDespues - 1000),
    };
    const segundo = await enqueueTrainerLimitMail(APP, "t1", unDiaDespues);
    expect(segundo).toBeNull(); // clausula 4, mismo kind
    expect(enqueueMock).toHaveBeenCalledTimes(1);
  });

  describe("compatibilidad con el legado (un Timestamp suelto, no un mapa)", () => {
    it("un legado se lee como enfriamiento de customExercises", () => {
      const legado = {
        ...chocoRecien(TOPES[0]),
        [CAMPO_MAIL_AT]: ts(AHORA - ENFRIAMIENTO_MS + 1), // Timestamp SUELTO
      };
      expect(decideTrainerLimitMail(legado, AHORA, "t1")).toBeNull();
    });

    it("⚠️ el legado (compartido con ejercicios en su momento) SÍ bloquea el mail de plantillas", () => {
      // Hallazgo P2 de Codex sobre #1267, verificado contra `43888a21` (el
      // commit que generalizó este mail por kind y sumó `templates`): el
      // escalar viejo lo escribían los mails de EJERCICIOS Y DE PLANTILLAS
      // por igual, nunca fue "sólo de ejercicios". Tratarlo como propio de
      // un único kind bloqueaba el mail correcto (customExercises) y dejaba
      // pasar el equivocado (templates) con el MISMO dato viejo.
      const legadoConPlantillas = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "templates",
        planLimits: { templates: 3 },
        templateUsage: { count: 3 },
        [CAMPO_MAIL_AT]: ts(AHORA - 1000), // Timestamp SUELTO, recién escrito
      };
      expect(decideTrainerLimitMail(legadoConPlantillas, AHORA, "t1")).toBeNull();
    });

    it("el legado VENCIDO no bloquea nada, ni ejercicios ni plantillas", () => {
      const vencido = ts(AHORA - ENFRIAMIENTO_MS - 1);

      const conEjercicios = { ...chocoRecien(TOPES[0]), [CAMPO_MAIL_AT]: vencido };
      expect(decideTrainerLimitMail(conEjercicios, AHORA, "t1")).not.toBeNull();

      const conPlantillas = { ...chocoRecien(TOPES[1]), [CAMPO_MAIL_AT]: vencido };
      expect(decideTrainerLimitMail(conPlantillas, AHORA, "t1")).not.toBeNull();
    });

    it("⚠️ el legado NO bloquea el mail de alumnos", () => {
      const legadoConAlumnos = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        subscription: { tier: "plan1", status: "active" },
        [CAMPO_MAIL_AT]: ts(AHORA - 1000), // Timestamp SUELTO, recién escrito
      };
      // carga en vivo simulada = 7 (== límite plan1) — ver el bloque "alumnos".
      expect(
        decideTrainerLimitMail(legadoConAlumnos, AHORA, "t1", undefined, 7),
      ).not.toBeNull();
    });

    it("la próxima reserva migra el legado a mapa, preservando su valor en LAS DOS claves", async () => {
      // El legado tiene que estar VENCIDO acá: si estuviera reciente,
      // bloquearía este mismo mail de plantillas (ver el test de arriba) y
      // no se llegaría a reservar nada que inspeccionar.
      const legadoVencidoMs = AHORA - ENFRIAMIENTO_MS - 1;
      usersStore["t1"] = {
        ...chocoRecien(TOPES[1]), // choca PLANTILLAS ahora
        [CAMPO_MAIL_AT]: ts(legadoVencidoMs),
      };
      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("template-limit-reached");

      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as Record<
        string,
        { toMillis(): number }
      >;
      expect(typeof mailAt).toBe("object");
      // customExercises conserva el legado vencido — nadie chocó ESE tope ahora.
      expect(mailAt.customExercises.toMillis()).toBe(legadoVencidoMs);
      // templates tiene la reserva FRESCA de este mismo choque.
      expect(mailAt.templates.toMillis()).toBe(AHORA);
    });
  });

  describe("el rollback sólo toca la clave de SU kind", () => {
    it("si el encolado de plantillas falla, la reserva de ejercicios (ya anotada) queda intacta", async () => {
      usersStore["t1"] = {
        ...chocoRecien(TOPES[1]), // choca PLANTILLAS
        [CAMPO_MAIL_AT]: { customExercises: ts(AHORA - ENFRIAMIENTO_MS - 1) },
      };
      enqueueMock.mockResolvedValueOnce(null);
      colaExiste = false;

      await expect(enqueueTrainerLimitMail(APP, "t1", AHORA)).rejects.toThrow();

      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT] as Record<
        string,
        { toMillis(): number } | undefined
      >;
      // La de plantillas se deshizo (no quedó mail detrás)...
      expect(mailAt.templates).toBeUndefined();
      // ...pero la de ejercicios, que YA estaba ahí antes de esta corrida,
      // sigue exactamente igual.
      expect(mailAt.customExercises?.toMillis()).toBe(AHORA - ENFRIAMIENTO_MS - 1);
    });
  });
});

// ---------------------------------------------------------------------------
// El kind `students` — decide sobre `subscription` + la carga PONDERADA EN
// VIVO de `trainer_links`, NUNCA `weightedLoad` persistido (hallazgo de Codex
// sobre #1267, P2 — ver `leerLimiteDeAlumnos` en el módulo). El resto del
// flujo (reserva, encolado, rollback) es el MISMO código genérico que ya
// cubren los tests de arriba.
//
// Los describes de acá abajo, salvo el último, llaman a `decideTrainerLimitMail`
// DIRECTO (sin pasar por Firestore) y simulan la carga en vivo con su 5º
// parámetro — lo que `reservarEnfriamiento` le pasaría después de calcularla.
// El último describe SÍ pasa por `enqueueTrainerLimitMail`/`reservarEnfriamiento`
// de verdad, con `trainer_links` mockeados vía `vinculos(...)`.
// ---------------------------------------------------------------------------
describe("alumnos", () => {
  const CHOCO_RECIEN_ALUMNOS = {
    [CAMPO_TOPE_AT]: ts(AHORA - 60 * 60 * 1000),
    [CAMPO_TOPE_KIND]: "students",
    subscription: { tier: "plan1", status: "active" }, // TIER_WEIGHT_LIMITS.plan1 = 7
  };

  it("en el tope (carga en vivo >= límite efectivo) manda", () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN_ALUMNOS, AHORA, "t1", undefined, 7);
    expect(plan?.kind).toBe("student-limit-reached");
    expect(plan?.tope).toBe("students");
    expect(plan?.limit).toBe(7);
  });

  it("por debajo del tope no manda", () => {
    expect(decideTrainerLimitMail(CHOCO_RECIEN_ALUMNOS, AHORA, "t1", undefined, 6)).toBeNull();
  });

  it("límite null (plan3, sin tope) no manda", () => {
    const sinTope = {
      ...CHOCO_RECIEN_ALUMNOS,
      subscription: { tier: "plan3", status: "active" },
    };
    expect(decideTrainerLimitMail(sinTope, AHORA, "t1", undefined, 50)).toBeNull();
  });

  it("sin `subscription` (Free) usa el límite Free (2)", () => {
    const free = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "students",
    };
    const plan = decideTrainerLimitMail(free, AHORA, "t1", undefined, 2);
    expect(plan?.limit).toBe(2);
  });

  // ⚠️ Control del fail-closed que documenta `sigueEnElTope`: nunca debería
  // pasar en producción (`reservarEnfriamiento` siempre calcula la carga en
  // vivo para este kind), pero si el 5º parámetro no llega, no manda —igual
  // que un kind sin reconocer o un límite corrupto, en vez de adivinar.
  it("⚠️ sin carga en vivo (parámetro ausente) no manda — fail-closed", () => {
    expect(decideTrainerLimitMail(CHOCO_RECIEN_ALUMNOS, AHORA, "t1")).toBeNull();
  });

  // ── Hallazgo de Codex sobre #1267 (P1 de esa ronda): el gate real rechaza
  // por `projectedLoad > limit`, no por `carga >= limit` — la carga
  // ACEPTADA no es la que el intento rechazado hubiera dejado.
  // Ver `sigueEnElTope`, sección "1.".
  describe("con incremento — la misma desigualdad estricta que el gate", () => {
    const conIncremento = (incremento: number) => ({
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "students",
      // Sin `subscription`: límite Free = 2 (mismo fixture que arriba).
      [CAMPO_TOPE_INCREMENTO]: incremento,
    });

    it("carga 1,5 + incremento 1, límite 2 → manda (2,5 > 2)", () => {
      const plan = decideTrainerLimitMail(conIncremento(1), AHORA, "t1", undefined, 1.5);
      expect(plan?.kind).toBe("student-limit-reached");
      expect(plan?.limit).toBe(2);
    });

    it("carga 1 + incremento 1, límite 2 → NO manda (1 + 1 = 2, no > 2)", () => {
      expect(decideTrainerLimitMail(conIncremento(1), AHORA, "t1", undefined, 1)).toBeNull();
    });

    it("⚠️ si la carga FRESCA ya bajó del choque (el PF liberó lugar), no manda", () => {
      // El incremento quedó anotado contra la carga del momento del choque
      // (1,5), pero la carga en vivo se releyó fresca y hoy es 0,5 — el PF
      // pausó a alguien después. `sigueEnElTope` nunca guarda la carga vieja,
      // sólo el incremento: 0,5 + 1 = 1,5, no > 2.
      expect(decideTrainerLimitMail(conIncremento(1), AHORA, "t1", undefined, 0.5)).toBeNull();
    });
  });

  describe("sin incremento (choque legado, o `details` incompletos)", () => {
    it("cae al mismo criterio que los otros dos kinds: carga en vivo >= límite → manda", () => {
      const legado = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        // == límite Free (2), sin CAMPO_TOPE_INCREMENTO
      };
      expect(decideTrainerLimitMail(legado, AHORA, "t1", undefined, 2)).not.toBeNull();
    });

    it("por debajo del límite no manda, aunque un incremento hipotético lo hubiera pasado", () => {
      const legado = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        // < límite Free (2), sin incremento conocido
      };
      expect(decideTrainerLimitMail(legado, AHORA, "t1", undefined, 1.5)).toBeNull();
    });
  });

  // ---------------------------------------------------------------------
  // LA CARGA EN VIVO, NO PERSISTIDA — hallazgo de Codex sobre #1267 (P2).
  // El caso real que motiva el fix: `weightedLoad` queda desactualizado
  // mientras `linkLoadReconcile` (async, dispara por cada escritura de
  // `trainer_links`) todavía no corrió. Acá SÍ se pasa por
  // `enqueueTrainerLimitMail` → `reservarEnfriamiento`, que es quien calcula
  // la carga en vivo DENTRO de la transacción vía `readTrainerLinks` +
  // `computeWeightedLoad` (`promote-link.ts`/`weighted-load.ts`) — los
  // vínculos se simulan con `vinculos(...)`.
  // ---------------------------------------------------------------------
  describe("⚠️ la carga se recalcula EN VIVO — weightedLoad persistido queda ciego al reconciliador pendiente", () => {
    it("weightedLoad persistido 1, vínculos en vivo suman 2, incremento 1, límite 2 → manda", async () => {
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1,
        weightedLoad: 1, // desactualizado — el reconciliador no corrió todavía
        // Sin `subscription`: límite Free = 2.
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" },
        { athleteId: "a2", status: "active" },
      ]); // computeWeightedLoad = 2.0

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("student-limit-reached");
      expect(plan?.limit).toBe(2);
    });

    it("vínculos en vivo suman 1, incremento 1, límite 2 → NO manda (1 + 1 = 2, no > 2)", async () => {
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1,
        weightedLoad: 1,
      };
      vinculos("t1", [{ athleteId: "a1", status: "active" }]); // computeWeightedLoad = 1.0

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan).toBeNull();
    });

    it("⚠️ control: sin vínculos vivos, la carga es 0 — un weightedLoad persistido alto no lo tapa", () => {
      // Si el código TODAVÍA leyera `weightedLoad`, esto mandaría (11 >= 2).
      // Con la carga en vivo (0 vínculos = 0), no debe mandar nada.
      const soloWeightedLoad = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        weightedLoad: 11, // dato viejo — no tiene que importar
      };
      // La carga en vivo simulada (0, sin incremento) es lo que
      // `reservarEnfriamiento` le pasaría con `trainer_links` vacío.
      expect(decideTrainerLimitMail(soloWeightedLoad, AHORA, "t1", undefined, 0)).toBeNull();
    });
  });

  // ---------------------------------------------------------------------
  // EL LINK ID — no contar dos veces un vínculo que ya se activó. Hallazgo
  // de Codex sobre #1267 (P2 de esta ronda). Ver `sigueEnElTope`, sección
  // "3. EL LINK ID". Los ids que genera `vinculos(...)` son "link-0",
  // "link-1", ... en el orden del array (ver el mock de `trainer_links`
  // arriba del archivo) — por eso cada test comenta a qué id corresponde
  // cada entrada.
  // ---------------------------------------------------------------------
  describe("el linkId — no contar dos veces un vínculo que ya se activó", () => {
    it("reintento exitoso (el vínculo YA está `active`) → no manda", async () => {
      // Ejemplo del hallazgo: Free falla con carga 2, el PF libera un lugar,
      // reintenta y el MISMO vínculo se activa con éxito, volviendo a 2. Con
      // el criterio VIEJO (carga total + incremento) esto mandaría igual:
      // 2 + 1 = 3 > 2 — "no se pudo activar" siendo falso.
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1,
        [CAMPO_TOPE_LINK_ID]: "link-1", // el vínculo por el que chocó
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" }, // link-0
        { athleteId: "a2", status: "active" }, // link-1 — reintentó y se activó
      ]);

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan).toBeNull();
    });

    it("el vínculo sigue `pending` → manda si la proyección (sin él + incremento) supera el límite", async () => {
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1, // pending (0) → active (1) intentado
        [CAMPO_TOPE_LINK_ID]: "link-2",
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" }, // link-0
        { athleteId: "a2", status: "active" }, // link-1
        { athleteId: "a3", status: "pending" }, // link-2 — el que chocó, sigue pendiente
      ]); // carga sin él = 2 (pending pesa 0 de todos modos) + incremento 1 = 3 > 2

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("student-limit-reached");
    });

    it("choque legado sin linkId → comportamiento de ANTES de este fix (carga total + incremento)", async () => {
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1,
        // sin CAMPO_TOPE_LINK_ID — choque anotado antes de este fix
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" },
        { athleteId: "a2", status: "active" },
      ]); // carga total 2 + incremento 1 = 3 > 2 → manda, sin poder distinguir
      // si uno de los dos vínculos es el que reintentó con éxito.

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("student-limit-reached");
    });

    it("el vínculo ya no está entre los vivos (se terminó) → se trata como no-activo", async () => {
      usersStore["t1"] = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 1,
        [CAMPO_TOPE_LINK_ID]: "link-ausente", // no matchea ningún id vivo
      };
      vinculos("t1", [
        { athleteId: "a1", status: "active" },
        { athleteId: "a2", status: "active" },
      ]); // "sin él" = carga total igual (no está para excluir) = 2 + incremento 1 = 3 > 2

      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("student-limit-reached");
    });

    // ── LA LIMITACIÓN CONOCIDA, documentada en `sigueEnElTope` ──
    it("⚠️ el vínculo sigue `paused` SIN CAMBIOS: la fórmula conservadora puede no mandar donde el viejo sí", () => {
      // No se puede decir "cubierto" sobre esto (AGENTS.md §11.1): el
      // incremento es `1.0 - pesoDelMomento` (acá 0.5, paused), no el peso
      // completo hacia activo, así que "carga sin él + incremento" resta ese
      // 0.5 DOS VECES contra lo que el gate recalcularía ahora mismo (2.5).
      // Se acepta porque es MENOS preciso pero MÁS conservador — nunca manda
      // de más — mismo criterio que el resto del archivo.
      const doc = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        [CAMPO_TOPE_INCREMENTO]: 0.5, // paused (0,5) → active (1,0) intentado
      };
      // Simula lo que `reservarEnfriamiento` le pasaría: carga total 2,0
      // (activo 1,0 + pausado-ajeno 0,5 + este vínculo pausado 0,5), y el
      // vínculo NO está activo, con carga sin él = 1,5.
      const vinculoAlumnos = { activo: false, cargaSinElVinculo: 1.5 };
      // Fórmula nueva: 1,5 + 0,5 = 2,0, no > 2 (límite Free) → no manda.
      expect(
        decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2, vinculoAlumnos),
      ).toBeNull();
      // El criterio VIEJO (sin excluir el vínculo) SÍ mandaba acá: 2,0 (carga
      // total) + 0,5 = 2,5 > 2. Es la regresión aceptada a propósito.
      expect(decideTrainerLimitMail(doc, AHORA, "t1", undefined, 2)).not.toBeNull();
    });
  });
});

// ── Hallazgo de Codex sobre #1267 (P1, mitad "no anotar el choque") ──
describe("esTopeDeAlumnos", () => {
  it("⚠️ reason `plan-limit` — SÍ es el tope de alumnos", () => {
    const err = new HttpsError("resource-exhausted", "x", {
      reason: "plan-limit",
      tier: "plan1",
      limit: 7,
      currentLoad: 6.5,
      projectedLoad: 7.5,
    });
    expect(esTopeDeAlumnos(err)).toBe(true);
  });

  it("⚠️ reason `subscription-inactive` — NO es el tope de alumnos, es un problema de cobro", () => {
    // Antes de #1267 esto daba `true` y `acceptTrainerLink`/`resumeTrainerLink`
    // anotaban `trainerLimitHitKind: students` igual que con `plan-limit` —
    // un PF pausado que rebotaba recibía el mail de upsell.
    const err = new HttpsError("resource-exhausted", "x", {
      reason: "subscription-inactive",
      tier: "plan3",
      limit: 2,
      currentLoad: 2,
      projectedLoad: 3,
    });
    expect(esTopeDeAlumnos(err)).toBe(false);
  });

  it("sin `details.reason` (otro resource-exhausted, ej. cuota de Firestore), false", () => {
    expect(esTopeDeAlumnos(new HttpsError("resource-exhausted", "cuota"))).toBe(false);
  });

  it("un código que no es resource-exhausted, false", () => {
    const err = new HttpsError("failed-precondition", "x", { reason: "plan-limit" });
    expect(esTopeDeAlumnos(err)).toBe(false);
  });

  it("un error que no es HttpsError, false", () => {
    expect(esTopeDeAlumnos(new Error("otra cosa"))).toBe(false);
  });
});

describe("incrementoDeAlumnos", () => {
  it("projectedLoad - currentLoad de los details", () => {
    const err = new HttpsError("resource-exhausted", "x", {
      reason: "plan-limit",
      tier: "plan1",
      limit: 7,
      currentLoad: 6.5,
      projectedLoad: 7.5,
    });
    expect(incrementoDeAlumnos(err)).toBe(1);
  });

  it("sin currentLoad/projectedLoad numéricos, null — fail-closed", () => {
    const err = new HttpsError("resource-exhausted", "x", {
      reason: "plan-limit",
      tier: "plan1",
      limit: 7,
    });
    expect(incrementoDeAlumnos(err)).toBeNull();
  });

  it("un error que no es HttpsError, null", () => {
    expect(incrementoDeAlumnos(new Error("otra cosa"))).toBeNull();
  });
});

describe("registrarTopeDeAlumnos", () => {
  beforeEach(() => {
    usersStore = {};
  });

  it("guarda kind + at + el incremento + el linkId cuando se los pasan", async () => {
    await registrarTopeDeAlumnos(APP, "t1", AHORA, 1.5, "link-abc");
    expect(usersStore["t1"]).toMatchObject({
      [CAMPO_TOPE_KIND]: "students",
      [CAMPO_TOPE_INCREMENTO]: 1.5,
      [CAMPO_TOPE_LINK_ID]: "link-abc",
    });
    expect((usersStore["t1"]?.[CAMPO_TOPE_AT] as { toMillis(): number }).toMillis()).toBe(AHORA);
  });

  it("⚠️ sin incremento, BORRA cualquier valor de un choque anterior — no lo deja colgado", async () => {
    usersStore["t1"] = { [CAMPO_TOPE_INCREMENTO]: 3 }; // de un choque previo
    await registrarTopeDeAlumnos(APP, "t1", AHORA, null, "link-nuevo");
    expect(usersStore["t1"]?.[CAMPO_TOPE_INCREMENTO]).toBeUndefined();
  });

  // ── Hallazgo de Codex sobre #1267 (P2 de esta ronda) ──
  it("⚠️ sin linkId, BORRA cualquier id de un choque anterior — no lo deja colgado", async () => {
    usersStore["t1"] = { [CAMPO_TOPE_LINK_ID]: "link-viejo" }; // de un choque previo
    await registrarTopeDeAlumnos(APP, "t1", AHORA, null, null);
    expect(usersStore["t1"]?.[CAMPO_TOPE_LINK_ID]).toBeUndefined();
  });
});

describe("el texto", () => {
  describe("exercise-limit-reached", () => {
    const render = (limit: number) =>
      renderMail("exercise-limit-reached", {
        tope: "customExercises",
        limit,
        ctaUrl: trainerWebCheckout(),
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
        ctaUrl: trainerWebCheckout(),
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

    it("el CTA ofrece ver planes, con cuerpo", () => {
      const { html } = render(20);
      expect(html).toContain("VER LOS PLANES");
      expect(html).toMatch(/<p /);
    });

    it("lista sólo los planes con MÁS ejercicios propios, con su cupo y su precio", () => {
      // Al que chocó ejercicios le sirve saber cuántos ejercicios trae cada
      // plan, no cuántos alumnos.
      const desdeFree = render(20).text;
      expect(desdeFree).toContain("Si necesitás más lugar, estos planes tienen más:");
      expect(desdeFree).toMatch(/Plan 1 · 60 ejercicios propios · \$\s?12\.000 por mes/);
      expect(desdeFree).toContain("Plan 3 · ejercicios propios sin límite");

      const desdePlan1 = render(60).text;
      expect(desdePlan1).not.toContain("Plan 1 ·");
      expect(desdePlan1).toContain("Plan 2 · 120 ejercicios propios");
    });
  });

  describe("template-limit-reached", () => {
    const render = (limit: number) =>
      renderMail("template-limit-reached", {
        tope: "templates",
        limit,
        ctaUrl: trainerWebCheckout(),
      });

    it("dice el número del tope", () => {
      const { html, text } = render(3);
      expect(html).toContain("3 plantillas");
      expect(text).toContain("3 plantillas");
    });

    it("singular correcto en el borde: 1 plantilla", () => {
      const { html } = render(1);
      expect(html).toContain("1 plantilla");
      expect(html).not.toContain("1 plantillas");
    });

    it("⚠️ nunca interpola null — sin params, cae a la frase genérica", () => {
      const { html, text } = renderMail("template-limit-reached", {
        ctaUrl: trainerWebCheckout(),
      });
      expect(html).not.toContain("null");
      expect(text).not.toContain("null");
    });

    it("⚠️ dice que conserva todo y puede seguir usándolas — nunca 'perder' ni 'borrar' en negativo", () => {
      const { text } = render(3);
      expect(text.toLowerCase()).toContain("conservás");
      expect(text.toLowerCase()).toMatch(/editándolas/);
      expect(text.toLowerCase()).toMatch(/asignándolas/);
      expect(text.toLowerCase()).toMatch(/publicándolas/);
      expect(text.toLowerCase()).toMatch(/archivándolas/);
      // P5/E3: bajar de plan nunca borra ni bloquea lo que ya existe.
      expect(text.toLowerCase()).not.toMatch(/perdés|perdes|se borra tu|se eliminan tus/);
    });

    it("el CTA ofrece ver planes, con cuerpo", () => {
      const { html } = render(3);
      expect(html).toContain("VER LOS PLANES");
      expect(html).toMatch(/<p /);
    });

    it("lista los planes con más plantillas: hoy, los tres pagos sin límite", () => {
      const { text } = render(3);
      expect(text).toContain("Si necesitás más lugar, estos planes tienen más:");
      expect(text).toMatch(/Plan 1 · plantillas sin límite · \$\s?12\.000 por mes/);
      expect(text).toContain("Plan 3 · plantillas sin límite");
    });
  });

  describe("student-limit-reached", () => {
    const render = (limit: number) =>
      renderMail("student-limit-reached", {
        tope: "students",
        limit,
        ctaUrl: trainerWebCheckout(),
      });

    it("dice el número del tope, con el mismo formato que cupoLabel", () => {
      const { html, text } = render(7);
      expect(html).toContain(cupoLabel(7));
      expect(text).toContain(cupoLabel(7));
    });

    it("singular correcto en el borde: 1 alumno", () => {
      const { html } = render(1);
      expect(html).toContain("1 alumno");
      expect(html).not.toContain("1 alumnos");
    });

    it("⚠️ nunca interpola null — sin params, cae a la frase genérica", () => {
      const { html, text } = renderMail("student-limit-reached", {
        ctaUrl: trainerWebCheckout(),
      });
      expect(html).not.toContain("null");
      expect(text).not.toContain("null");
    });

    it("⚠️ dice que los alumnos actuales no pierden nada — nunca 'perder' ni 'borrar' en negativo", () => {
      const { text } = render(7);
      expect(text.toLowerCase()).toContain("no pierden nada");
      expect(text.toLowerCase()).not.toMatch(/se borra tu|se eliminan tus/);
    });

    it("el CTA ofrece ver planes, con cuerpo", () => {
      const { html } = render(7);
      expect(html).toContain("VER LOS PLANES");
      expect(html).toMatch(/<p /);
    });

    it("lista sólo los planes con MÁS alumnos que el suyo", () => {
      // Con 7 (Plan 1), ofrecerle el Plan 1 es mandarlo a elegir lo que ya tiene.
      const { text } = render(7);
      expect(text).toContain("Si querés seguir sumando, estos planes tienen más lugar:");
      expect(text).not.toContain("Plan 1 ·");
      expect(text).toMatch(/Plan 2 · 15 alumnos · \$\s?22\.000 por mes/);
      expect(text).toContain("Plan 3 · alumnos sin límite");
    });

    it("sin el dato del tope ofrece todos los pagos", () => {
      const { text } = renderMail("student-limit-reached", { ctaUrl: trainerWebCheckout() });
      expect(text).toContain("Plan 1 ·");
      expect(text).toContain("Plan 3 ·");
    });

    it("⚠️ con el plan sin tope no ofrece «más lugar»: vuelve a la frase de siempre", () => {
      // `limitParam` distingue «sin tope» (null) de «sin dato» (undefined).
      // Confundirlos le ofrecería planes a quien ya tiene el más grande.
      const { text } = renderMail("student-limit-reached", {
        limit: "sin-tope",
        ctaUrl: trainerWebCheckout(),
      });
      expect(text).not.toMatch(/Plan \d ·/);
      expect(text).toContain("Si querés seguir sumando, hay planes más grandes.");
    });
  });
});
