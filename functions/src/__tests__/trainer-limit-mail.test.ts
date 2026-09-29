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
 * #1265: el enfriamiento de 14 días dejó de ser compartido entre topes —
 * chocar uno ya NO silencia el mail de otro— con su compatibilidad para el
 * `trainerLimitMailAt` legado (un Timestamp suelto, no un mapa).
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
import { renderMail, trainerWebCheckout, cupoLabel } from "../mail/templates";
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
 */
let usersStore: Record<string, Record<string, unknown> | undefined> = {};
let colaExiste = false;
const colaGetMock = jest.fn(async () => ({ exists: colaExiste }));
const DELETE_SENTINEL = Symbol("FieldValue.delete()");

interface FakeRef {
  uid: string;
}
interface FakeTx {
  get: (ref: FakeRef) => Promise<{ data: () => Record<string, unknown> | undefined }>;
  set: (ref: FakeRef, patch: Record<string, unknown>) => void;
  update: (ref: FakeRef, patch: Record<string, unknown>) => void;
}

let mutex: Promise<unknown> = Promise.resolve();
const runTransactionMock = jest.fn((fn: (tx: FakeTx) => Promise<unknown>) => {
  const tx: FakeTx = {
    get: async (ref) => ({ data: () => usersStore[ref.uid] }),
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

jest.mock("firebase-admin/firestore", () => ({
  ...jest.requireActual("firebase-admin/firestore"),
  FieldValue: { delete: () => DELETE_SENTINEL },
  getFirestore: () => ({
    collection: (name: string) =>
      name === "users"
        ? { doc: (uid: string) => ({ uid }) }
        : { doc: () => ({ get: colaGetMock }) },
    runTransaction: runTransactionMock,
  }),
}));

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
// El enfriamiento es POR KIND (#1265) — ver el encabezado del módulo.
// ---------------------------------------------------------------------------
describe("⚠️ el enfriamiento es POR KIND, no compartido", () => {
  it("chocar ejercicios y, dentro de los 14 días, plantillas — manda DOS mails, uno de cada uno", async () => {
    // t0: choca ejercicios, manda, reserva `trainerLimitMailAt.customExercises`.
    usersStore["t1"] = chocoRecien(TOPES[0]);
    const planEjercicios = await enqueueTrainerLimitMail(APP, "t1", AHORA);
    expect(planEjercicios?.kind).toBe("exercise-limit-reached");
    expect(enqueueMock).toHaveBeenCalledTimes(1);

    // t0 + 1 día: el MISMO PF choca plantillas. Si el enfriamiento siguiera
    // compartido, esto no mandaría nada — es justo lo que #1265 corrige.
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

    it("⚠️ el legado NO bloquea el mail de plantillas", () => {
      const legadoConPlantillas = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "templates",
        planLimits: { templates: 3 },
        templateUsage: { count: 3 },
        [CAMPO_MAIL_AT]: ts(AHORA - 1000), // Timestamp SUELTO, recién escrito
      };
      expect(decideTrainerLimitMail(legadoConPlantillas, AHORA, "t1")).not.toBeNull();
    });

    it("⚠️ el legado NO bloquea el mail de alumnos", () => {
      const legadoConAlumnos = {
        [CAMPO_TOPE_AT]: ts(AHORA - 1000),
        [CAMPO_TOPE_KIND]: "students",
        subscription: { tier: "plan1", status: "active" },
        weightedLoad: 7,
        [CAMPO_MAIL_AT]: ts(AHORA - 1000), // Timestamp SUELTO, recién escrito
      };
      expect(decideTrainerLimitMail(legadoConAlumnos, AHORA, "t1")).not.toBeNull();
    });

    it("la próxima reserva migra el legado a mapa, preservando su valor bajo customExercises", async () => {
      usersStore["t1"] = {
        ...chocoRecien(TOPES[1]), // choca PLANTILLAS ahora
        [CAMPO_MAIL_AT]: ts(AHORA - 5000), // legado: enfriamiento viejo de ejercicios
      };
      const plan = await enqueueTrainerLimitMail(APP, "t1", AHORA);
      expect(plan?.kind).toBe("template-limit-reached"); // el legado no lo bloqueó

      const mailAt = usersStore["t1"]?.[CAMPO_MAIL_AT];
      expect(typeof mailAt).toBe("object");
      expect((mailAt as Record<string, unknown>).customExercises).toBeDefined();
      expect((mailAt as Record<string, { toMillis(): number }>).customExercises.toMillis()).toBe(
        AHORA - 5000,
      );
      expect((mailAt as Record<string, unknown>).templates).toBeDefined();
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
// El kind `students` — decide sobre `subscription` + `weightedLoad`, no sobre
// `planLimits`. El resto del flujo (reserva, encolado, rollback) es el MISMO
// código genérico que ya cubren los tests de arriba.
// ---------------------------------------------------------------------------
describe("alumnos", () => {
  const CHOCO_RECIEN_ALUMNOS = {
    [CAMPO_TOPE_AT]: ts(AHORA - 60 * 60 * 1000),
    [CAMPO_TOPE_KIND]: "students",
    subscription: { tier: "plan1", status: "active" }, // TIER_WEIGHT_LIMITS.plan1 = 7
    weightedLoad: 7,
  };

  it("en el tope (weightedLoad >= límite efectivo) manda", () => {
    const plan = decideTrainerLimitMail(CHOCO_RECIEN_ALUMNOS, AHORA, "t1");
    expect(plan?.kind).toBe("student-limit-reached");
    expect(plan?.tope).toBe("students");
    expect(plan?.limit).toBe(7);
  });

  it("por debajo del tope no manda", () => {
    const porDebajo = { ...CHOCO_RECIEN_ALUMNOS, weightedLoad: 6 };
    expect(decideTrainerLimitMail(porDebajo, AHORA, "t1")).toBeNull();
  });

  it("límite null (plan3, sin tope) no manda", () => {
    const sinTope = {
      ...CHOCO_RECIEN_ALUMNOS,
      subscription: { tier: "plan3", status: "active" },
      weightedLoad: 50,
    };
    expect(decideTrainerLimitMail(sinTope, AHORA, "t1")).toBeNull();
  });

  it("sin `subscription` (Free) usa el límite Free (2)", () => {
    const free = {
      [CAMPO_TOPE_AT]: ts(AHORA - 1000),
      [CAMPO_TOPE_KIND]: "students",
      weightedLoad: 2,
    };
    const plan = decideTrainerLimitMail(free, AHORA, "t1");
    expect(plan?.limit).toBe(2);
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

    it("el CTA ofrece ver planes, no un botón hero sin cuerpo", () => {
      const { html } = render(20);
      expect(html).toContain("VER LOS PLANES");
      // A diferencia de free-limit-reached, este SÍ lleva cuerpo — no es hero.
      expect(html).toMatch(/<p /);
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

    it("el CTA ofrece ver planes, no un botón hero sin cuerpo", () => {
      const { html } = render(3);
      expect(html).toContain("VER LOS PLANES");
      // A diferencia de free-limit-reached, este SÍ lleva cuerpo — no es hero.
      expect(html).toMatch(/<p /);
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

    it("el CTA ofrece ver planes, no un botón hero sin cuerpo", () => {
      const { html } = render(7);
      expect(html).toContain("VER LOS PLANES");
      expect(html).toMatch(/<p /);
    });
  });
});
