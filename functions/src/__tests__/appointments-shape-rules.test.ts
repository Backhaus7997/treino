/**
 * QA-SEC-014 (#781) — `appointments` era el ÚNICO documento escribible por un
 * tercero sin un solo límite de forma ni de tamaño.
 *
 * Medido contra el emulador antes del fix: una cuenta autenticada SIN ninguna
 * relación con el PF creaba un turno `confirmed` en la agenda de CUALQUIER PF
 * con 30 KB de texto arbitrario en `athleteDisplayName` y en `noteBefore`. Y no
 * se podía sacar — `allow delete: if false` (ADR-1, audit trail) y la
 * cancelación exige >24 h de anticipación—, así que un turno forjado con
 * `startsAt` dentro de las próximas 24 h o en el pasado quedaba FIJO en la
 * agenda hasta que alguien entrara con el Admin SDK.
 *
 * Es un hueco de INTEGRIDAD, no de confidencialidad: no filtra datos de
 * terceros. Escribe contenido arbitrario y permanente en la superficie de
 * trabajo del PF, con su nombre puesto por un desconocido. Ver `docs/security.md`
 * §4.9.
 *
 * ⚠️ Los `users/{uid}` se seedean con `withSecurityRulesDisabled` A PROPÓSITO,
 * por el mismo motivo que en `coach-role-gate-rules.test.ts`: el disyunto del
 * PF hace `get(users/{uid})`, y sobre un doc inexistente la evaluación FALLA —
 * un `assertFails` sin seed pasaría por el motivo equivocado, que es lo que
 * `docs/security.md` §1.8 prohíbe.
 *
 * ⚠️ SOBRE LAS FECHAS. `startsAt` se guarda como WALL-CLOCK UTC (ADR-7 /
 * QA-COA-003): la hora local del picker escrita en un DateTime marcado UTC, sin
 * conversión. En ART (UTC-3) eso deja el `startsAt` de una sesión inminente 3 h
 * POR DETRÁS de `request.time`. Por eso el piso de la regla es
 * `request.time - 24 h` y no `request.time`, y por eso acá hay un positivo
 * explícito con `startsAt` en el pasado reciente: es el caso que se pone rojo si
 * alguien "corrige" el piso a `> request.time` y rompe el alta de toda sesión
 * del mismo día, que es el flujo principal del PF.
 *
 * Run against the Firestore emulator (Java 21 required):
 *   npm --prefix functions run test:rules:emulator
 */

import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, updateDoc, setLogLevel, Timestamp } from "firebase/firestore";

const PROJECT_ID = "treino-rules-test-sec014";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "trainer-uid";
const ATHLETE = "athlete-uid";
/** Cuenta autenticada sin NINGUNA relación con el PF — el actor del ticket. */
const ATTACKER = "attacker-uid";

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

/** El payload del ticket: 30 KB de texto arbitrario. */
const BLOB = "x".repeat(30000);

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  setLogLevel("error");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", TRAINER), { uid: TRAINER, role: "trainer" });
    await setDoc(doc(db, "users", ATHLETE), { uid: ATHLETE, role: "athlete" });
    await setDoc(doc(db, "users", ATTACKER), { uid: ATTACKER, role: "athlete" });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function inMs(ms: number): Timestamp {
  return Timestamp.fromDate(new Date(Date.now() + ms));
}

/**
 * Forma EXACTA de `Appointment.toJson()` (appointment.g.dart), que es lo que
 * realmente viaja al wire — no el modelo ni lo que uno supone. `id` viaja en el
 * body porque el repositorio hace `set(appt.toJson())`.
 */
function appointment(
  id: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    id,
    trainerId: TRAINER,
    athleteId: ATHLETE,
    athleteDisplayName: "Juan Pérez",
    startsAt: inMs(48 * HOUR),
    durationMin: 60,
    status: "confirmed",
    cancelledAt: null,
    cancelledBy: null,
    cancellationLog: [],
    noteBefore: null,
    noteAfter: null,
    recurringId: null,
    paymentId: null,
    ...overrides,
  };
}

/** Siembra un turno saltándose las reglas (estado de partida para los updates). */
async function seed(id: string, overrides: Record<string, unknown> = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "appointments", id), appointment(id, overrides));
  });
}

// ───────────────────────────────────────────────────────────────────────────
// El ataque exacto del ticket.
// ───────────────────────────────────────────────────────────────────────────

describe("appointments — el vector del ticket (QA-SEC-014)", () => {
  it("DENIEGA 30 KB de texto arbitrario en la agenda de un PF desconocido", async () => {
    // El caso medido en el issue, palabra por palabra: cuenta sin relación
    // alguna con el PF, turno `confirmed`, 30 KB en el nombre y 30 KB en la
    // nota. Contra las reglas anteriores esto era ALLOW.
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), "appointments", "forged"),
        appointment("forged", {
          athleteId: ATTACKER,
          athleteDisplayName: BLOB,
          noteBefore: BLOB,
        })
      )
    );
  });

  it("DENIEGA el turno INCANCELABLE — `startsAt` dentro de la ventana de 24 h", async () => {
    // El agravante del ticket: dentro de las 24 h nadie lo cancela (la regla de
    // cancelación exige >24 h) y nadie lo borra (`delete: if false`). Que el
    // alta del atleta pida el MISMO margen que la cancelación es lo que hace
    // que todo lo que se puede crear nazca cancelable.
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), "appointments", "forged-soon"),
        appointment("forged-soon", {
          athleteId: ATTACKER,
          startsAt: inMs(2 * HOUR),
        })
      )
    );
  });

  it("DENIEGA el turno INCANCELABLE — `startsAt` en el pasado", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), "appointments", "forged-past"),
        appointment("forged-past", {
          athleteId: ATTACKER,
          startsAt: inMs(-30 * DAY),
        })
      )
    );
  });

  it("DENIEGA claves fuera de la forma — la basura arbitraria", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), "appointments", "junk"),
        appointment("junk", { basura: BLOB })
      )
    );
  });
});

// ───────────────────────────────────────────────────────────────────────────
// create — los caminos legítimos siguen vivos.
// ───────────────────────────────────────────────────────────────────────────

describe("appointments create — positivos (QA-SEC-014)", () => {
  it("permite al PF anotar una sesión de HOY, con `startsAt` detrás de request.time", async () => {
    // EL positivo que custodia la decisión de wall-clock (ver el ⚠️ del
    // encabezado). Con un piso `> request.time` este caso se pone rojo y con él
    // se cae el alta de toda sesión del mismo día en ART.
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "today"),
        appointment("today", { startsAt: inMs(-2 * HOUR) })
      )
    );
  });

  it("permite al PF anotar una sesión dentro de las próximas horas", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "soon"),
        appointment("soon", { startsAt: inMs(3 * HOUR) })
      )
    );
  });

  it("permite al PF una serie recurrente a 12 semanas de un inicio a 1 año", async () => {
    // El techo de 730 días tiene que dejar pasar el máximo legítimo: el picker
    // corta en `today + 365` y la recurrencia estira 12 semanas más (~449 días).
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "far"),
        appointment("far", { startsAt: inMs(449 * DAY), recurringId: "serie-1" })
      )
    );
  });

  it("permite el auto-booking del alumno a más de 24 h vista (disyunto legacy)", async () => {
    // Regresión de SCENARIO-CC-08: el disyunto del atleta sigue vivo, sólo que
    // acotado. Si esto se pone rojo, el fix se comió la feature.
    await assertSucceeds(
      setDoc(
        doc(dbAs(ATHLETE), "appointments", "selfbook"),
        appointment("selfbook", { athleteId: ATHLETE, startsAt: inMs(48 * HOUR) })
      )
    );
  });

  it("permite un `athleteDisplayName` de exactamente 200 caracteres", async () => {
    // El borde del cap. Sin este positivo, bajar el tope a la mitad pasaría
    // inadvertido.
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "edge200"),
        appointment("edge200", { athleteDisplayName: "x".repeat(200) })
      )
    );
  });
});

// ───────────────────────────────────────────────────────────────────────────
// create — negativos de forma, rango y campos de sistema.
// ───────────────────────────────────────────────────────────────────────────

describe("appointments create — negativos (QA-SEC-014)", () => {
  it("DENIEGA un `athleteDisplayName` de 201 caracteres", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "edge201"),
        appointment("edge201", { athleteDisplayName: "x".repeat(201) })
      )
    );
  });

  it("DENIEGA una `noteBefore` de más de 5000 caracteres", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "note-long"),
        appointment("note-long", { noteBefore: "x".repeat(5001) })
      )
    );
  });

  it("DENIEGA que el alumno adjunte notas en su propio alta", async () => {
    // Las notas son de coaching: las escribe el PF por el Path 3. Sacárselas al
    // disyunto abierto deja al atacante eligiendo sólo su propio nombre.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), "appointments", "selfnote"),
        appointment("selfnote", { athleteId: ATHLETE, noteBefore: "hola" })
      )
    );
  });

  it("DENIEGA que el PF anote una sesión de hace un mes", async () => {
    // El piso general (`request.time - 24 h`) necesita su propio guardián: los
    // negativos de turno-en-el-pasado del bloque anterior son del ATLETA, y a
    // ése lo tapa además su cláusula de >24 h vista. Sin este caso, borrar el
    // piso entero dejaba un solo test en rojo — lo mostró la verificación de
    // mutación (§1.8), no la lectura de la regla.
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "trainer-past"),
        appointment("trainer-past", { startsAt: inMs(-30 * DAY) })
      )
    );
  });

  it("DENIEGA un turno a más de 730 días", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "year9999"),
        appointment("year9999", { startsAt: inMs(800 * DAY) })
      )
    );
  });

  it("DENIEGA un turno incompleto — sin `athleteDisplayName` ni `durationMin`", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "appointments", "partial"), {
        id: "partial",
        trainerId: TRAINER,
        athleteId: ATHLETE,
        startsAt: inMs(48 * HOUR),
        status: "confirmed",
      })
    );
  });

  it("DENIEGA un `durationMin` que no es un entero positivo acotado", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "dur"),
        appointment("dur", { durationMin: -1 })
      )
    );
  });

  it("DENIEGA nacer ya cobrado — el `paymentId` forjado en el create", async () => {
    // Sin este pin, el `create` era el agujero por el que se salteaba el
    // set-once del Path 3: el turno nacía apuntando a un Payment ajeno.
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "prepaid"),
        appointment("prepaid", { paymentId: "payment-ajeno" })
      )
    );
  });

  it("DENIEGA nacer con rastro de cancelación", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "appointments", "precancelled"),
        appointment("precancelled", {
          cancelledBy: ATHLETE,
          cancellationLog: [{ byUid: ATHLETE, atMs: Date.now(), reason: BLOB }],
        })
      )
    );
  });

  it("DENIEGA reservar a nombre de OTRO alumno", async () => {
    // Regla preexistente (ninguna mutación de este change la toca): el disyunto
    // del atleta pide su propio uid y el del PF pide rol `trainer`.
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), "appointments", "impersonate"),
        appointment("impersonate", { athleteId: ATHLETE })
      )
    );
  });
});

// ───────────────────────────────────────────────────────────────────────────
// update — los tres caminos. Acotar sólo el `create` no cierra nada si el
// `update` deja meter lo mismo un segundo después.
// ───────────────────────────────────────────────────────────────────────────

describe("appointments update Path 1 — cancelar no es escribir (QA-SEC-014)", () => {
  beforeEach(async () => {
    await seed("appt1");
  });

  it("permite al alumno cancelar con más de 24 h", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), "appointments", "appt1"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: ATHLETE,
        cancellationLog: [{ byUid: ATHLETE, atMs: Date.now(), reason: "no puedo" }],
      })
    );
  });

  it("permite al PF cancelar con más de 24 h", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt1"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
        cancellationLog: [{ byUid: TRAINER, atMs: Date.now() }],
      })
    );
  });

  it("DENIEGA usar la cancelación como canal de escritura libre", async () => {
    // El mismo `update` que cancela podía reescribir `athleteDisplayName` con
    // 30 KB. El `create` acotado no sirve de nada si esto queda abierto.
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), "appointments", "appt1"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        athleteDisplayName: BLOB,
      })
    );
  });

  it("DENIEGA colgar notas por el camino de la cancelación", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), "appointments", "appt1"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        noteAfter: BLOB,
      })
    );
  });

  it("DENIEGA mover el turno mientras se cancela", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), "appointments", "appt1"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        startsAt: inMs(72 * HOUR),
      })
    );
  });

  it("DENIEGA que un tercero cancele un turno ajeno", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), "appointments", "appt1"), {
        status: "cancelled",
        cancelledBy: ATTACKER,
      })
    );
  });

  // LA decisión de diseño de este change, y por eso tiene test propio: el
  // Path 1 pinea POR VALOR en vez de exigir `hasOnly()`. Un `hasOnly()` acá
  // dejaría INCANCELABLE a todo turno forjado ANTES del fix — la regla que
  // cierra el agujero congelaría su propio residuo. El residuo tiene que
  // seguir siendo limpiable.
  it("deja CANCELABLE un turno forjado antes del fix, con claves de más", async () => {
    await seed("legacy", { basura: BLOB, athleteDisplayName: BLOB });
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), "appointments", "legacy"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
      })
    );
  });
});

describe("appointments update Path 2 — el flip ADR-1 (QA-SEC-014)", () => {
  beforeEach(async () => {
    await seed("freed", { status: "cancelled", cancelledBy: ATHLETE });
  });

  it("permite a un alumno nuevo tomar el slot liberado a más de 24 h", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATTACKER), "appointments", "freed"), {
        status: "confirmed",
        athleteId: ATTACKER,
        athleteDisplayName: "Pedro",
        cancelledAt: null,
        cancelledBy: null,
      })
    );
  });

  it("DENIEGA forjar el turno por el flip en vez de por el create", async () => {
    // Sin la validación de forma acá, el atacante movía el mismo ataque un
    // camino más allá y el fix no cerraba nada.
    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), "appointments", "freed"), {
        status: "confirmed",
        athleteId: ATTACKER,
        athleteDisplayName: BLOB,
      })
    );
  });

  it("DENIEGA el flip sobre un slot dentro de la ventana de 24 h", async () => {
    await seed("freed-soon", {
      status: "cancelled",
      cancelledBy: ATHLETE,
      startsAt: inMs(2 * HOUR),
    });
    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), "appointments", "freed-soon"), {
        status: "confirmed",
        athleteId: ATTACKER,
        athleteDisplayName: "Pedro",
      })
    );
  });

  it("DENIEGA mover el slot mientras se lo toma", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), "appointments", "freed"), {
        status: "confirmed",
        athleteId: ATTACKER,
        athleteDisplayName: "Pedro",
        startsAt: inMs(96 * HOUR),
      })
    );
  });
});

describe("appointments update Path 3 — el PF sobre su propio turno (QA-SEC-014)", () => {
  beforeEach(async () => {
    await seed("appt3");
  });

  it("permite al PF editar las notas de coaching", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt3"), {
        noteBefore: "Trabajar isquiotibiales",
        noteAfter: "Cerró con 3x8",
      })
    );
  });

  it("permite al PF enlazar el cobro (set-once de `paymentId`)", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt3"), {
        paymentId: "pay-1",
      })
    );
  });

  it("DENIEGA meter basura por el update del PF", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt3"), { basura: BLOB })
    );
  });

  it("DENIEGA una nota de coaching de 30 KB", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt3"), { noteAfter: BLOB })
    );
  });

  it("DENIEGA que el PF le reescriba el nombre al alumno", async () => {
    // El PF era el único que podía hacerlo, y no tiene ningún flujo que lo
    // necesite: los únicos writes legítimos de este camino son `updateNotes` y
    // `markBilled`/`billAppointment`.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), "appointments", "appt3"), {
        athleteDisplayName: "Otro nombre",
      })
    );
  });
});
