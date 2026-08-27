/**
 * QA-SEC-014 (#781) — el `create` de `appointments` no validaba nada del
 * documento.
 *
 * Sin `keys().hasOnly()`, sin cap en ningún campo de texto y sin rango en
 * `startsAt`, cualquier autenticado escribía un turno `confirmed` en la agenda
 * de **cualquier** PF con 30 KB de texto arbitrario. Y no se podía sacar:
 * `allow delete: if false`, y la cancelación exige >24 h de anticipación, así
 * que un turno forjado con `startsAt` cercano o pasado quedaba fijo en la
 * agenda. Ver `docs/security.md` §4.9.
 *
 * Era la única colección escribible por un tercero del archivo sin cota de
 * texto — `athlete_notes` <5000, `follow_up_entries` <5000, `nutrition_plans`
 * <200, `payments` <=200, `measurements` <=2000.
 *
 * ⚠️ `startsAt` es **wall-clock UTC**, no un instante real (ADR-7 /
 * QA-COA-003): en ART (UTC−3) el valor guardado queda 3 h ANTES del instante
 * real. Por eso el rango de la regla tiene un día de tolerancia hacia atrás, y
 * por eso el caso `acepta un turno dentro de las próximas horas` existe: se
 * pone rojo si alguien "endurece" el rango a `> request.time`, que denegaría
 * toda reserva cercana.
 *
 * Fuera de alcance a propósito: el auto-booking (Slice C lo dejó intacto) y
 * exigir `trainer_links`, que es cambio de producto.
 *
 * ─── #831 ────────────────────────────────────────────────────────────────────
 * El residuo del ticket: el mismo daño con el payload mudado a
 * `cancellationLog`, que llegaba a un turno CONFIRMADO en tres escrituras.
 *
 * Se cerró SACANDO el camino, no acotándolo: el flip `cancelled → confirmed`
 * de ADR-1 ya no está en las reglas. Su única implementación —`book()`— no
 * tiene llamadores en `lib/`, y los dos creadores vivos usan auto-id, así que
 * nunca pasaron por ahí. Los casos que asserteaban el flip se CONVIRTIERON a
 * DENY en vez de borrarse, para que reintroducirlo se ponga rojo.
 *
 * Los otros dos bloques cubren el Path 1, que era el vecino que hacía evadible
 * cualquier gate del flip: `cancelledBy` firmado por el actor, y los pines de
 * `athleteId` / `trainerId` / `startsAt` / `durationMin`. Ninguno de los dos
 * tenía UN SOLO caso antes — por eso la tabla de mutación de #823 no vio la
 * evasión.
 *
 * Fuera de alcance, anotado en el ticket: mover la escritura del log a una
 * Cloud Function y el campo `reason` de
 * `functions/src/cascade/appointments.ts`.
 *
 * ─── #831, cuarta pasada — la MATRIZ campo × camino ──────────────────────────
 * El mismo patrón volvió una cuarta vez, y esta vez lo introdujo el fix de la
 * tercera: el Path 1 pinea `cancelledBy` contra el actor y el Path 2 —el camino
 * de al lado, en el mismo commit— no lo miraba. Dos escrituras, las dos ALLOW,
 * y un turno cancelado firmado por quien no canceló.
 *
 * Lo encontró dar vuelta la pregunta: en vez de "¿quién más escribe el campo
 * del que depende esta regla?", "para cada uno de los 14 campos de la
 * allowlist, ¿qué le puede hacer CADA camino?". La matriz completa, con la
 * justificación de cada celda que queda escribible, está en `docs/security.md`
 * §4.9. Los bloques del final de este archivo son sus casos: las 11 celdas que
 * estaban abiertas, los dos gates que no tenían cobertura de mutación
 * (`startsAt is timestamp` y el bound de crecimiento del log) y los 13 mapas
 * literales de los escritores reales, que antes se verificaban a mano.
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
import {
  arrayUnion,
  deleteField,
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  serverTimestamp,
  setLogLevel,
  Timestamp,
  where,
} from "firebase/firestore";

const PROJECT_ID = "treino-rules-test-sec014";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const ATHLETE = "athlete-uid";
const TRAINER = "trainer-uid";
// #831: el atacante de la cadena A1→A3 — una cuenta `athlete` sin NINGUNA
// relación con el PF víctima, que es justamente lo que hace grave al hallazgo.
const ATTACKER = "attacker-uid";
const VICTIM_PF = "victim-pf-uid";
// PF que reserva por el camino `createByTrainer` — necesita rol para el
// disyunto del trainer, así que se seedea su `users/{uid}` en beforeEach.
const TRAINER_BOOKER = "trainer-booker-uid";
const COL = "appointments";

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
    await setDoc(doc(ctx.firestore(), "users", TRAINER_BOOKER), {
      uid: TRAINER_BOOKER,
      role: "trainer",
    });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

function inDays(days: number): Timestamp {
  return Timestamp.fromMillis(Date.now() + days * 86400000);
}

/** Turno válido — forma exacta de `Appointment.toJson()` (14 claves). */
function appointment(
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    id: "appt-1",
    trainerId: TRAINER,
    athleteId: ATHLETE,
    athleteDisplayName: "Juan Pérez",
    startsAt: inDays(3),
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

describe("appointments create — forma y cotas (QA-SEC-014)", () => {
  it("permite al atleta reservar su propio turno", async () => {
    // Ancla de no-vacuidad: el auto-booking sigue vivo, que es lo que Slice C
    // dejó explícitamente intacto.
    await assertSucceeds(
      setDoc(doc(dbAs(ATHLETE), COL, "appt-1"), appointment())
    );
  });

  it("acepta un turno cercano guardado como wall-clock ART — el caso que rompe un rango ingenuo", async () => {
    // ⚠️ Este caso tiene que MODELAR el corrimiento, no escribir un futuro
    // real. La primera versión usaba `Date.now() + 1h` y era decoración: ese
    // valor pasa igual con `> request.time`, así que la mutación que endurece
    // el borde no lo ponía rojo. Lo destapó la verificación por mutación.
    //
    // ADR-7 / QA-COA-003: `startsAt` se guarda como wall-clock UTC. En ART
    // (UTC−3) una sesión a 2 h vista se persiste como `instante_real − 3 h`,
    // o sea **1 hora ANTES de ahora** en tiempo real. Ese es el valor que la
    // app escribe de verdad, y el que un `> request.time` denegaría.
    const wallClockArtIn2h = Timestamp.fromMillis(
      Date.now() + 2 * 3600000 - 3 * 3600000
    );
    await assertSucceeds(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-soon"),
        appointment({ id: "appt-soon", startsAt: wallClockArtIn2h })
      )
    );
  });

  it("DENIEGA 30 KB de texto en athleteDisplayName", async () => {
    // El vector del ticket: acoso con el nombre puesto por un desconocido.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-2"),
        appointment({ id: "appt-2", athleteDisplayName: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA 30 KB de texto en noteBefore", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-3"),
        appointment({ id: "appt-3", noteBefore: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA campos fuera de la forma", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-4"),
        appointment({ id: "appt-4", basura: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA un turno en el pasado lejano — el que no se puede cancelar ni borrar", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-5"),
        appointment({ id: "appt-5", startsAt: inDays(-30) })
      )
    );
  });

  it("acepta el horizonte REAL del PF: 365 días + 12 semanas de recurrencia", async () => {
    // ⚠️ El caso que el primer intento rompía. Yo había puesto el tope en 60
    // días generalizando el guard de 28 de `AppointmentRepository.book…`, que
    // aplica SÓLO al auto-booking del atleta. `createByTrainer` no tiene
    // guard, y las dos UIs de sesión del PF ofrecen
    // `lastDate: today.add(Duration(days: 365))`; con la recurrencia
    // (`_kWeekOptions = [2, 4, 8, 12]`) el último turno del lote cae a ~449
    // días. Y como el lote es un batch atómico, el tope de 60 habría
    // rechazado **la serie entera**, no sólo las fechas lejanas.
    //
    // Lo marcó el bot de review. Este caso se pone rojo si alguien vuelve a
    // apretar el borde superior sin mirar el camino del PF.
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "appt-lejos"),
        appointment({
          id: "appt-lejos",
          athleteId: "otro-atleta",
          trainerId: TRAINER_BOOKER,
          startsAt: inDays(365 + 12 * 7),
        })
      )
    );
  });

  it("DENIEGA un turno absurdamente lejano en el futuro", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-6"),
        appointment({ id: "appt-6", startsAt: inDays(600) })
      )
    );
  });

  it("DENIEGA sembrar cancellationLog en el create", async () => {
    // Un turno nuevo no tiene cancelaciones: el modelo lo crea con
    // `@Default([])`. Exigirlo vacío cierra el inflado por esta vía, que es
    // más fuerte que acotar el largo — las reglas no pueden mirar el tamaño
    // de cada elemento de una lista.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-log"),
        appointment({
          id: "appt-log",
          cancellationLog: [
            { byUid: ATHLETE, atMs: 1, reason: "x".repeat(30000) },
          ],
        })
      )
    );
  });

  it("DENIEGA un durationMin fuera de rango", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-7"),
        appointment({ id: "appt-7", durationMin: 100000 })
      )
    );
  });

  it("DENIEGA un cancellationLog inflado", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-8"),
        appointment({
          id: "appt-8",
          cancellationLog: Array.from({ length: 500 }, (_, i) => ({
            byUid: ATHLETE,
            atMs: i,
            reason: "x".repeat(100),
          })),
        })
      )
    );
  });

  it("DENIEGA un turno incompleto", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), COL, "appt-9"), {
        id: "appt-9",
        trainerId: TRAINER,
        athleteId: ATHLETE,
        status: "confirmed",
      })
    );
  });

  it("DENIEGA reservar a nombre de OTRO atleta", async () => {
    // Preexistente: lo cierra el disyunto de ownership, no este change.
    await assertFails(
      setDoc(
        doc(dbAs("tercero"), COL, "appt-10"),
        appointment({ id: "appt-10" })
      )
    );
  });
});

describe("appointments update — la cota también aplica (QA-SEC-014)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-u"),
        appointment({ id: "appt-u", startsAt: inDays(5) })
      );
      await setDoc(doc(ctx.firestore(), "users", TRAINER), {
        uid: TRAINER,
        role: "trainer",
      });
    });
  });

  // ⚠️ Estos dos casos viajan sobre el Path 1 (cancelación por un miembro con
  // >24 h) A PROPÓSITO, y la primera versión no lo hacía.
  //
  // Escritos como un update suelto de `noteBefore` desde el atleta, pasaban en
  // verde **por el motivo equivocado**: no los denegaba la cota de forma sino
  // la estructura de paths —un atleta cambiando notas no matchea NINGÚN
  // camino—. La mutación lo destapó: sacar `appointmentUpdateShapeOk()` no
  // ponía rojo a nadie.
  //
  // Para que el negativo custodie lo que dice, el update tiene que ser uno que
  // SIN la cota sería válido. De ahí el `status: 'cancelled'` acompañando la
  // basura.
  //
  // ⚠️ #831 (sexta pasada) — y VOLVIÓ a quedar verde por el motivo equivocado,
  // por el fix de la pasada anterior. El Path 1 pinea `cancelledBy` contra el
  // actor desde #831; este update no lo manda, así que el doc mergeado queda
  // con `cancelledBy: null != ATHLETE` y el camino NO matchea. Medido: con
  // `optStrMaxLen(noteBefore, 5000)` BORRADO del update, este caso seguía
  // verde. La cancelación tiene que estar FIRMADA para que lo único que
  // separe el ALLOW del DENY sea la cota.
  it("DENIEGA engordar el turno colgándose de una cancelación válida", async () => {
    // Sin cota en el update, el cap del create se esquiva creando un turno
    // chico y engordándolo un segundo después por un camino legítimo.
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        noteBefore: "x".repeat(30000),
      })
    );
  });

  it("DENIEGA agregar claves nuevas colgándose de una cancelación válida", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), {
        status: "cancelled",
        basura: "x".repeat(30000),
      })
    );
  });

  it("permite al miembro cancelar con más de 24 h", async () => {
    // Ancla de no-vacuidad del Path 1: la cota de forma no puede romper la
    // cancelación, que es el único camino de salida que tiene un turno.
    //
    // ⚠️ #831: el `cancelledBy` NO es decoración. El Path 1 ahora lo pinea
    // contra `auth.uid`, así que este update tiene que modelar lo que
    // `AppointmentRepository.cancel()` manda de verdad
    // (`'cancelledBy': actorUid`), no un mínimo inventado. Es la misma lección
    // que ya está escrita arriba: un caso que no modela la escritura real
    // custodia otra cosa.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });
});

/**
 * QA-SEC-014 residual (#831) — el flip `cancelled → confirmed` se REMOVIÓ.
 *
 * Este bloque asserteaba que el flip de ADR-1 andaba. Ahora assertea que NO
 * existe. Los casos no se borraron a propósito: un camino que se remueve
 * necesita tests que se pongan ROJOS si alguien lo reintroduce sin pensarlo —
 * borrarlos deja el hueco sin custodia.
 *
 * Por qué se removió, en corto (el largo está sobre el `allow update`):
 * #781 cerró el vector literal —30 KB de texto libre al crear—. Lo que quedó
 * abierto fue el mismo daño con el payload mudado a `cancellationLog`: el
 * `create` exige el log vacío, el `update` lo deja crecer de a uno, y el flip
 * lo devolvía a `confirmed`, o sea al stream VIVO de `watchForTrainer`. La
 * pasada anterior endureció el flip con `athleteId != resource.data.athleteId`;
 * el review mostró que ese gate se EVADE, porque el Path 1 no pineaba
 * `athleteId` y el atacante lo movía en la cancelación. En vez de seguir
 * blindando el camino se lo sacó: si no existe, no hay nada que evadir.
 *
 * Que estaba muerto no es corazonada, está verificado en tres puntos: la única
 * implementación es `AppointmentRepository.book()`; `book()` no tiene NINGÚN
 * llamador en `lib/` (sólo dos tests unitarios con mock, que no tocan reglas);
 * y los dos creadores vivos —`createByTrainer` / `createRecurringByTrainer`—
 * usan `_appointments.doc()`, o sea AUTO-ID: estrenan documento siempre, nunca
 * caen sobre uno cancelado, y por eso pasan por `allow create`.
 *
 * ⚠️ Honestidad sobre la mutación: después del borrado, los casos de abajo
 * mueren todos por el MISMO motivo —ningún camino matchea—, así que ya no se
 * matan de a uno como cuando cada uno custodiaba un `&&` distinto del flip. Es
 * lo que pasa cuando la mitigación es SACAR el código en vez de acotarlo, y es
 * preferible: lo que queda no es un gate que haya que mantener afinado, es
 * ausencia. Lo que estos casos custodian ahora es esa ausencia.
 */
describe("appointments update — el flip cancelled→confirmed ya no existe (#831)", () => {
  const CHAIN = "appt-cadena";

  it("DENIEGA la cadena completa A1→A2→A3 (create → cancelar inflando → re-confirmar)", async () => {
    // La cadena EXACTA medida contra el emulador en el ticket, con la cuenta
    // atacante y el PF víctima que no se conocen de ningún lado.
    const attackerDb = dbAs(ATTACKER);
    const ref = doc(attackerDb, COL, CHAIN);

    // A1 — el turno nace limpio: pasa el `cancellationLog.size() == 0` de #823.
    await assertSucceeds(
      setDoc(
        ref,
        appointment({
          id: CHAIN,
          trainerId: VICTIM_PF,
          athleteId: ATTACKER,
          athleteDisplayName: "Bob",
          startsAt: inDays(2),
        })
      )
    );

    // A2 — Path 1. Sigue permitido y TIENE que seguirlo: cancelar es la única
    // salida de un turno, y el inflado dentro de un doc `cancelled` es el
    // residuo de 1 MiB ya anotado (ninguna query de `lib/` lo deserializa).
    // Si este paso se pusiera rojo, el fix estaría cerrando el camino
    // equivocado.
    await assertSucceeds(
      updateDoc(ref, {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: ATTACKER,
        cancellationLog: arrayUnion({
          byUid: ATTACKER,
          atMs: Date.now(),
          reason: "x".repeat(30000),
        }),
      })
    );

    // A3 — el paso que duele. Pasaba en verde y dejaba
    // status=confirmed · logEntries=1 · reasonLen=30000 en la agenda del PF.
    //
    // ⚠️ Antes de #831 lo cerraba —parcialmente— un `athleteId !=` colgado del
    // flip. Ahora NO lo cierra ningún gate: lo cierra que el camino no exista.
    // El `allow update` tiene sólo cancelación y edición del PF, y ATTACKER no
    // es el PF de este turno.
    await assertFails(
      updateDoc(ref, {
        status: "confirmed",
        athleteId: ATTACKER,
        cancelledAt: null,
        cancelledBy: null,
      })
    );

    // Y el doc queda donde tiene que quedar: cancelado, o sea fuera del stream
    // de `watchForTrainer`. Se lee con reglas desactivadas porque el assert es
    // sobre el ESTADO, no sobre el permiso de lectura.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), COL, CHAIN));
      expect(snap.data()?.status).toBe("cancelled");
    });
  });

  it("DENIEGA el texto de las notas volviendo a un turno confirmado", async () => {
    // La misma cadena con el payload en `noteBefore` / `noteAfter` en vez del
    // log. El Path 1 NO pinea las notas —una cancelación puede escribirlas,
    // acotadas a 5000 por la forma— así que A2 pasa. Lo que cierra el daño no
    // es un cap más chico: es que ese texto ya no tiene CÓMO llegar a un
    // documento `confirmed`. Sin el flip, `cancelled` es TERMINAL para el
    // cliente, y las tres queries de `lib/` filtran `status == 'confirmed'`.
    const ref = doc(dbAs(ATTACKER), COL, "appt-notas");

    await assertSucceeds(
      setDoc(
        ref,
        appointment({
          id: "appt-notas",
          trainerId: VICTIM_PF,
          athleteId: ATTACKER,
          startsAt: inDays(2),
        })
      )
    );

    await assertSucceeds(
      updateDoc(ref, {
        status: "cancelled",
        cancelledBy: ATTACKER,
        noteBefore: "x".repeat(5000),
        noteAfter: "y".repeat(5000),
      })
    );

    await assertFails(
      updateDoc(ref, { status: "confirmed", athleteId: ATTACKER })
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), COL, "appt-notas"));
      expect(snap.data()?.status).toBe("cancelled");
    });
  });

  it("DENIEGA el flip que ANTES era legítimo — el camino se removió a propósito", async () => {
    // ⚠️ Este caso era un `assertSucceeds`: el ancla de no-vacuidad del flip.
    // Se CONVIRTIÓ, no se borró, y el `assertFails` es el punto del change. El
    // update modela literal el mapa de `AppointmentRepository.book()` —única
    // implementación del flip— y ahora rebota.
    //
    // No rompe nada vivo porque `book()` no tiene llamadores en `lib/`. Si
    // algún día vuelve el auto-booking, este caso es el que avisa que hay que
    // decidir la regla DE NUEVO: con `trainer_links` o una CF, no con otro
    // `&&` colgado de un camino que el vecino puede evadir.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-flip"),
        appointment({
          id: "appt-flip",
          status: "cancelled",
          startsAt: inDays(6),
          cancelledAt: Timestamp.now(),
          cancelledBy: TRAINER,
          cancellationLog: [
            { byUid: TRAINER, atMs: 1, reason: "cancelado por el profe" },
          ],
        })
      );
    });

    await assertFails(
      updateDoc(doc(dbAs("nuevo-atleta"), COL, "appt-flip"), {
        status: "confirmed",
        athleteId: "nuevo-atleta",
        athleteDisplayName: "Nuevo Atleta",
        cancelledAt: null,
        cancelledBy: null,
      })
    );
  });

  it("DENIEGA que el mismo atleta se re-confirme el turno que canceló", async () => {
    // Antes lo denegaba el `athleteId != resource.data.athleteId` del flip.
    // Ahora lo deniega la ausencia del camino. El caso queda igual: cambia el
    // MOTIVO, no lo que tiene que pasar.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-mismo"),
        appointment({
          id: "appt-mismo",
          status: "cancelled",
          athleteId: ATTACKER,
          trainerId: VICTIM_PF,
          startsAt: inDays(6),
        })
      );
    });

    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), COL, "appt-mismo"), {
        status: "confirmed",
        athleteId: ATTACKER,
        cancelledAt: null,
        cancelledBy: null,
      })
    );
  });

  it("DENIEGA agregar una entrada al log en el mismo flip", async () => {
    // La variante en UNA sola escritura: colgar el payload del propio flip,
    // sin cancelar primero. Antes la mataba el pin del `cancellationLog`; hoy
    // la mata que no haya flip.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-flip2"),
        appointment({
          id: "appt-flip2",
          status: "cancelled",
          startsAt: inDays(6),
          cancellationLog: [],
        })
      );
    });

    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), COL, "appt-flip2"), {
        status: "confirmed",
        athleteId: ATTACKER,
        cancellationLog: arrayUnion({
          byUid: ATTACKER,
          atMs: Date.now(),
          reason: "x".repeat(30000),
        }),
      })
    );
  });

  it("DENIEGA vaciar el log en el flip", async () => {
    // Borrar la auditoría tampoco entra. Antes por el `==` del pin, hoy por la
    // ausencia del camino.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-flip3"),
        appointment({
          id: "appt-flip3",
          status: "cancelled",
          startsAt: inDays(6),
          cancellationLog: [
            { byUid: TRAINER, atMs: 1, reason: "cancelado por el profe" },
          ],
        })
      );
    });

    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), COL, "appt-flip3"), {
        status: "confirmed",
        athleteId: ATTACKER,
        cancellationLog: [],
      })
    );
  });
});

/**
 * QA-SEC-014 residual (#831) — `cancelledBy` en el Path 1.
 *
 * Tampoco tenía tests. El camino sólo pedía "sos alguno de los dos miembros",
 * así que cualquiera de los dos podía firmar la cancelación con el uid del
 * OTRO — y con `delete: if false` y el log append-only, esa atribución falsa
 * queda fija.
 */
describe("appointments update — la cancelación se firma sola (#831)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, "appt-firma"),
        appointment({ id: "appt-firma", startsAt: inDays(5) })
      );
    });
  });

  it("permite al atleta cancelar firmando con su propio uid", async () => {
    // Ancla: es exactamente lo que manda `cancel()` — status + cancelledAt +
    // cancelledBy + la entrada del log.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-firma"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      })
    );
  });

  it("permite al PF cancelar firmando con su propio uid", async () => {
    // El caso real de producción: las cuatro superficies que llaman a
    // `cancel()` son del PF y sacan el `actorUid` de `currentUidProvider`.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "appt-firma"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
      })
    );
  });

  it("DENIEGA al atleta atribuirle la cancelación al PF", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-firma"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
      })
    );
  });

  it("DENIEGA al PF atribuirle la cancelación al atleta", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "appt-firma"), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: ATHLETE,
      })
    );
  });
});

/**
 * #831 — los pines del Path 1: `athleteId`, `trainerId`, `startsAt` y
 * `durationMin`.
 *
 * El camino no tocaba ninguno de los cuatro, y NO TOCAR NO ES PROHIBIR:
 * `request.resource.data` es el documento MERGEADO, así que una cancelación
 * podía reescribirlos de paso. Ninguno tenía un solo caso antes de #831.
 *
 * Este bloque es el que el review pidió aparte del borrado del flip, y con
 * razón: no se cae con él. Tres de los cuatro pines matan cosas que el flip
 * nunca tocó.
 *
 * Cada `it` mueve UN campo y deja el resto exactamente como lo manda
 * `AppointmentRepository.cancel()`, así que el único motivo de denegación
 * posible es su propio pin. Un negativo que pasa por otra razón no avisa
 * nunca — la lección que ya está escrita más arriba en este mismo archivo.
 */
describe("appointments update — la cancelación no reescribe el turno (#831)", () => {
  const PIN = "appt-pin";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, PIN),
        appointment({ id: PIN, startsAt: inDays(5) })
      );
    });
  });

  /** Lo que `cancel()` manda de verdad; cada caso le suma UN campo movido. */
  function cancelPayload(
    extra: Record<string, unknown> = {}
  ): Record<string, unknown> {
    return {
      status: "cancelled",
      cancelledAt: Timestamp.now(),
      cancelledBy: ATHLETE,
      cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      ...extra,
    };
  }

  it("permite la cancelación real, sin ningún campo movido", async () => {
    // Ancla de no-vacuidad de los cuatro pines juntos. Si se pone roja, los
    // pines están rompiendo la cancelación — que es el ÚNICO camino de salida
    // que tiene un turno, y romperlo sería peor que el bug.
    //
    // No es redundante con el ancla del bloque de `cancelledBy`: aquélla
    // custodia que el pin del actor no rompa nada, ésta que los cuatro nuevos
    // tampoco.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, PIN), cancelPayload())
    );
  });

  it("DENIEGA mover athleteId en la cancelación — el paso A2 que evadía el flip", async () => {
    // Éste es el que destapó el review. Con el flip todavía vivo, mover
    // `athleteId` acá dejaba el doc con un athleteId distinto del atacante, y
    // el `athleteId != resource.data.athleteId` del flip se cumplía SOLO en el
    // paso siguiente: el gate se evadía sin tocarlo.
    //
    // El flip ya no está, pero el pin se queda porque cierra algo propio: sin
    // él la cancelación aterriza sobre OTRO atleta, y con `delete: if false`
    // esa atribución queda fija.
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, PIN),
        cancelPayload({ athleteId: ATTACKER })
      )
    );
  });

  it("DENIEGA mover trainerId en la cancelación", async () => {
    // Sin el pin, un miembro muda el turno a la agenda de un TERCER PF que
    // nunca lo vio.
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, PIN),
        cancelPayload({ trainerId: VICTIM_PF })
      )
    );
  });

  it("DENIEGA mover startsAt en la cancelación — el turno imborrable por otra puerta", async () => {
    // El gate de 24 h lee `resource.data.startsAt`, o sea el valor VIEJO. Sin
    // el pin, la cancelación pasa el gate con el horario de antes y guarda
    // otro. Un turno movido al pasado no se puede cancelar nunca más (el gate
    // exige >24 h) ni borrar (`delete: if false`): es el turno imborrable de
    // #781, entrando por otro lado.
    //
    // ⚠️ `appointmentUpdateShapeOk()` NO tiene rango de `startsAt` —a
    // propósito, para no romper las notas post-sesión del PF—, así que acá el
    // único que puede denegar es el pin.
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, PIN),
        cancelPayload({ startsAt: inDays(-30) })
      )
    );
  });

  it("DENIEGA cambiar durationMin en la cancelación", async () => {
    // 90 y no 100000 A PROPÓSITO: 90 pasa el rango de la forma, así que lo
    // único que puede denegar es el pin. Con un valor fuera de rango el caso
    // seguiría verde aunque alguien sacara el pin, que es exactamente el
    // negativo-que-no-avisa contra el que este archivo viene advirtiendo.
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, PIN),
        cancelPayload({ durationMin: 90 })
      )
    );
  });
});

/**
 * #831 — el tipo y el rango de `durationMin` en el `update`.
 *
 * `keys().hasOnly()` acota QUÉ claves entran, no de qué tipo son ni con qué
 * valor: hasta #831 el update no miraba `durationMin` para NADA. El PF podía
 * dejar la sesión en 100000 minutos —un bloque que tapa el día entero de su
 * propia agenda— o directamente en un string, y el modelo lo deserializa como
 * int: `Appointment.fromJson` revienta.
 *
 * ⚠️ Estos dos casos viajan sobre el camino del PF (Path 2) A PROPÓSITO. Por
 * el Path 1 no servirían: ahí `durationMin` está PINEADO, así que un valor
 * absurdo se cae por el pin y el chequeo de forma nunca se evalúa — el negativo
 * pasaría en verde con el `is int` borrado. El Path 2 no pinea `durationMin`
 * (el PF puede corregir la duración de su sesión), y por eso es el único lugar
 * donde la cota de forma es lo ÚNICO que queda en pie.
 *
 * Honestidad sobre el resto de los chequeos de tipo que #831 agregó
 * (`athleteId`, `trainerId`, `startsAt`): NO tienen caso propio, y no por
 * olvido — no se puede escribir uno. Los DOS caminos que quedan pinean los
 * tres campos contra `resource.data`, así que cualquier valor de tipo
 * equivocado se cae antes por el pin. Sacar esos `is string` / `is timestamp`
 * mata 0 tests, y está anotado así en la tabla de mutación de `security.md` en
 * vez de disimulado. Se quedan igual porque el invariante no debería depender
 * de que TODO camino futuro se acuerde de pinear — que es literalmente cómo se
 * coló la premisa falsa que este change vino a corregir.
 */
describe("appointments update — durationMin tiene tipo y rango (#831)", () => {
  const DUR = "appt-dur";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, DUR),
        appointment({ id: DUR, startsAt: inDays(5) })
      );
    });
  });

  it("permite al PF editar las notas de su propia sesión", async () => {
    // Ancla de no-vacuidad del Path 2: es el uso normal de la feature, y los
    // dos negativos de abajo son este mismo update con `durationMin` de más.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, DUR), {
        noteAfter: "Cerró la sesión con 3x8 en press banca.",
      })
    );
  });

  it("DENIEGA un durationMin fuera de rango en el update", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, DUR), {
        noteAfter: "ok",
        durationMin: 100000,
      })
    );
  });

  it("DENIEGA un durationMin que no es int en el update", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, DUR), {
        noteAfter: "ok",
        durationMin: "sesenta",
      })
    );
  });
});

/**
 * #831 (segunda pasada) — `paymentId` también se pinea en el Path 1.
 *
 * Es la MISMA dependencia circular que este change vino a cerrar, sobre el
 * campo money-critical. El Path 2 tiene un gate **set-once** (`null` → string
 * no vacío, o re-afirmar el MISMO valor): un cliente nunca puede reapuntar el
 * cobro a otro Payment. Pero el Path 1 no miraba `paymentId`, y NO TOCAR NO ES
 * PROHIBIR: `request.resource.data` es el documento MERGEADO.
 *
 * Con eso, el set-once se evadía en DOS pasos sin tocarlo nunca: cancelar
 * limpiando `paymentId` (Path 1) y re-linkear después (Path 2, que ve un
 * `null` y lo trata como primera facturación). Blindar un camino cuyo vecino
 * escribe la misma variable es perseguir el vector, no cerrarlo — exactamente
 * lo que ya había pasado con el gate del flip y `athleteId`.
 *
 * El pin no rompe nada, y sale de leer los escritores: `cancel()` y
 * `cancelFutureSeries()` mandan updates PARCIALES de {status, cancelledAt,
 * cancelledBy, cancellationLog}. `paymentId` no viaja, así que el merge lo deja
 * idéntico a `resource.data` y la igualdad se cumple sola.
 */
describe("appointments update — la cancelación no toca el cobro (#831)", () => {
  const BILLED = "appt-billed";
  const UNBILLED = "appt-unbilled";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, BILLED),
        appointment({ id: BILLED, startsAt: inDays(5), paymentId: "pay-real" })
      );
      await setDoc(
        doc(ctx.firestore(), COL, UNBILLED),
        appointment({ id: UNBILLED, startsAt: inDays(5) })
      );
    });
  });

  function cancelPayload(
    extra: Record<string, unknown> = {}
  ): Record<string, unknown> {
    return {
      status: "cancelled",
      cancelledAt: Timestamp.now(),
      cancelledBy: ATHLETE,
      cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      ...extra,
    };
  }

  it("permite cancelar un turno YA cobrado — el pin no rompe la salida", async () => {
    // Ancla de no-vacuidad. Si se pone roja, el pin le sacó a un turno
    // facturado su único camino de salida (`delete: if false`), que sería peor
    // que el bug.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, BILLED), cancelPayload())
    );
  });

  it("DENIEGA limpiar paymentId en la cancelación", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, BILLED),
        cancelPayload({ paymentId: null })
      )
    );
  });

  it("DENIEGA reapuntar paymentId a otro Payment en la cancelación", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, BILLED),
        cancelPayload({ paymentId: "pay-FORJADO" })
      )
    );
  });

  it("DENIEGA inventar un paymentId sobre un turno NO cobrado", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, UNBILLED),
        cancelPayload({ paymentId: "pay-FORJADO" })
      )
    );
  });

  it("DENIEGA el bypass de dos pasos del set-once: limpiar cancelando, re-linkear después", async () => {
    // El que importa. El set-once del Path 2 funciona —`DENY markBilled() a
    // OTRO paymentId` ya está cubierto—, pero se evadía sin tocarlo: paso 1
    // por el Path 1, paso 2 por el Path 2 viendo un `null` recién fabricado.
    //
    // El paso 1 tiene que morir acá. Si alguna vez pasa, el paso 2 de abajo
    // deja el cobro reapuntado y el assert lo delata.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, BILLED), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
        paymentId: null,
      })
    );

    // Y el cobro sigue apuntando al Payment real.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), COL, BILLED));
      expect(snap.data()?.paymentId).toBe("pay-real");
    });
  });
});

/**
 * #831 (segunda pasada) — el rango de `durationMin` va contra el valor que se
 * ESCRIBE, no contra el documento heredado.
 *
 * `appointmentUpdateShapeOk()` corre sobre el documento MERGEADO. Un rango
 * incondicional ahí no valida la escritura: valida el DOCUMENTO. Un turno viejo
 * con `durationMin` fuera de rango, o guardado como double, quedaba sin poder
 * cancelarse ni anotarse NUNCA más — y `delete: if false`. Es exactamente la
 * familia "turno imborrable" que #781 vino a cerrar, reintroducida por el fix.
 *
 * No se puede saber si esos documentos existen: `treino-dev` ES producción
 * (#826) y no se le corren queries. Así que se asume que pueden existir.
 *
 * Condicionar el chequeo a que el campo CAMBIE no pierde nada: el Path 1 pinea
 * `durationMin` contra `resource.data`, y el Path 2 sólo puede escribirlo
 * dentro del rango. El valor no puede EMPEORAR. Validar el del doc viejo no
 * agregaba seguridad y sí rompía datos existentes.
 */
describe("appointments update — un turno legacy fuera de rango se sigue pudiendo cerrar (#831)", () => {
  const LEGACY_BIG = "appt-legacy-900";
  const LEGACY_DOUBLE = "appt-legacy-double";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_BIG),
        appointment({ id: LEGACY_BIG, startsAt: inDays(5), durationMin: 900 })
      );
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_DOUBLE),
        appointment({
          id: LEGACY_DOUBLE,
          startsAt: inDays(5),
          durationMin: 60.5,
        })
      );
    });
  });

  it("permite al PF anotar un turno legacy con durationMin = 900", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_BIG), {
        noteAfter: "Sesión vieja, la anoto igual.",
      })
    );
  });

  it("permite al PF anotar un turno legacy con durationMin double", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_DOUBLE), {
        noteAfter: "Sesión vieja, la anoto igual.",
      })
    );
  });

  it("permite cancelar un turno legacy con durationMin = 900 — sin esto es imborrable", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, LEGACY_BIG), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      })
    );
  });

  it("DENIEGA que el update MUEVA el durationMin del legacy a otro valor fuera de rango", async () => {
    // El rango no se relaja: deja de mirar el valor HEREDADO, sigue mirando el
    // que se escribe. Si este caso se pone verde, la condición se aflojó de más
    // y el Path 2 puede volver a tapar el día entero de la agenda.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_BIG), {
        noteAfter: "ok",
        durationMin: 100000,
      })
    );
  });
});

/**
 * #831 (cuarta pasada) — la MATRIZ campo × camino.
 *
 * Las tres pasadas anteriores buscaron vectores: se elegía un campo del que
 * dependía una regla y se rastreaba quién más lo escribía. Así se cerró el
 * flip, después `athleteId`, después `paymentId`. Y el patrón volvió igual una
 * cuarta vez, esta vez introducido por el fix de la tercera: el Path 1 pinea
 * `cancelledBy` contra el actor, y el Path 2 —el camino de al lado, en el mismo
 * commit— no lo miraba.
 *
 * La pregunta que lo encuentra no es "¿quién escribe el campo del que depende
 * esta regla?" sino **"para cada uno de los 14 campos de la allowlist, ¿qué le
 * puede hacer CADA camino?"**. La primera se recorre buscando lo que ya sabés;
 * la segunda tiene 28 celdas y ninguna se puede saltear. La matriz completa,
 * con la justificación de cada celda escribible, está en `docs/security.md`
 * §4.9.
 *
 * Lo que la matriz encontró y estos casos custodian:
 *  · Path 2 no miraba `cancelledBy`, `cancelledAt`, `cancellationLog`, `id` ni
 *    `recurringId` — cinco celdas, las cinco medidas en ALLOW.
 *  · Path 1 no miraba `id`, `athleteDisplayName` ni `recurringId`.
 *  · `id` y `cancelledAt` no tenían NI tipo NI cota en NINGUNA de las dos
 *    funciones de forma: un `create` con 30 KB adentro de cualquiera de los dos
 *    daba ALLOW. Era el inflado de #781 por una puerta que la allowlist
 *    dejaba abierta.
 */
describe("appointments update — el Path 2 no firma cancelaciones ajenas (#831)", () => {
  const CONFIRMED = "appt-p2-confirmed";
  const CANCELLED = "appt-p2-cancelled";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, CONFIRMED),
        appointment({
          id: CONFIRMED,
          startsAt: inDays(5),
          recurringId: "serie-real",
        })
      );
      await setDoc(
        doc(ctx.firestore(), COL, CANCELLED),
        appointment({
          id: CANCELLED,
          startsAt: inDays(5),
          status: "cancelled",
          cancelledAt: Timestamp.fromMillis(Date.now() - 3600000),
          cancelledBy: TRAINER,
          cancellationLog: [{ byUid: TRAINER, atMs: Date.now() - 3600000 }],
        })
      );
    });
  });

  it("DENIEGA al PF firmar con el uid del atleta por el Path 2", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), { cancelledBy: ATHLETE })
    );
  });

  it("DENIEGA la CADENA de dos pasos: cancelar firmando bien, reescribir la firma después", async () => {
    // El caso del ticket, medido end-to-end. El paso A pasa por el Path 1 y
    // cumple el pin de `cancelledBy` contra el actor. El paso B viene por el
    // Path 2, que no cancelaba nada y por eso ni miraba el campo: dos ALLOW y
    // un documento `cancelled` firmado por quien no canceló, imborrable.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), {
        status: "cancelled",
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
      })
    );

    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), { cancelledBy: ATHLETE })
    );

    // Y la firma sigue siendo la del que canceló de verdad.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await getDoc(doc(ctx.firestore(), COL, CONFIRMED));
      expect(snap.data()?.cancelledBy).toBe(TRAINER);
    });
  });

  it("DENIEGA reescribir la firma de un turno YA cancelado", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CANCELLED), { cancelledBy: ATHLETE })
    );
  });

  it("DENIEGA al PF reescribir cancelledAt", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), {
        cancelledAt: Timestamp.fromMillis(Date.now() - 999 * 86400000),
      })
    );
  });

  it("DENIEGA al PF colgarle una entrada forjada al cancellationLog", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), {
        cancellationLog: arrayUnion({
          byUid: ATHLETE,
          atMs: Date.now(),
          reason: "forjado",
        }),
      })
    );
  });

  it("re-cancelar un turno YA cancelado sigue siendo Path 1, y sigue exigiendo firma propia", async () => {
    // Medido, y va escrito porque la matriz lo destapó: el `status ==
    // 'cancelled'` del Path 1 mira el documento MERGEADO, así que sobre un doc
    // ya cancelado el camino SIGUE disponible. Un miembro puede re-cancelar:
    // mueve `cancelledAt` y suma una entrada al log.
    //
    // Se deja abierto a propósito —la justificación está en la matriz de
    // §4.9—: la atribución no se puede forjar (`cancelledBy` pineado contra el
    // actor), el crecimiento del log está acotado a +1 por escritura y a 50, y
    // cerrarlo con `resource.data.status != 'cancelled'` convertiría un doble
    // submit de `cancel()` en un error visible sin cerrar el residuo de
    // inflado, que ya se puede meter en la PRIMERA cancelación.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, CANCELLED), {
        cancelledAt: Timestamp.now(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
      })
    );

    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CANCELLED), {
        cancelledAt: Timestamp.now(),
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      })
    );
  });

  it("DENIEGA al PF mover recurringId — el campo por el que consulta cancelFutureSeries", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), {
        recurringId: "serie-de-otro",
      })
    );
  });

  it("DENIEGA al PF reescribir id", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), { id: "otro-turno" })
    );
  });

  it("permite al PF corregir la duración y el nombre — las dos celdas que la matriz deja escribibles", async () => {
    // Ancla de no-vacuidad de las celdas `escribible-acotado` del Path 2. Si
    // alguien "endurece" la matriz pineando de más, esto se pone rojo y
    // obliga a justificarlo: el PF es dueño de su agenda.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, CONFIRMED), {
        durationMin: 45,
        athleteDisplayName: "Juan P.",
        noteAfter: "buena sesión",
      })
    );
  });
});

/**
 * #831 (cuarta pasada) — las tres celdas que le faltaban al Path 1, y los dos
 * gates del `cancellationLog` que no tenían ningún test.
 *
 * El bound de crecimiento (`size() <= resource + 1`) y el tope de 50 en el
 * update estaban los dos sin cobertura de mutación: se podían borrar y ninguna
 * suite se ponía roja. Un gate que se puede revertir en silencio es un gate
 * que no está.
 */
describe("appointments update — la cancelación no reescribe el resto del turno (#831)", () => {
  const SERIE = "appt-serie";
  const FULL_LOG = "appt-log-lleno";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, SERIE),
        appointment({
          id: SERIE,
          startsAt: inDays(5),
          recurringId: "serie-real",
        })
      );
      await setDoc(
        doc(ctx.firestore(), COL, FULL_LOG),
        appointment({
          id: FULL_LOG,
          startsAt: inDays(5),
          cancellationLog: Array.from({ length: 50 }, (_, i) => ({
            byUid: ATHLETE,
            atMs: i,
          })),
        })
      );
    });
  });

  function cancelPayload(
    extra: Record<string, unknown> = {}
  ): Record<string, unknown> {
    return {
      status: "cancelled",
      cancelledAt: Timestamp.now(),
      cancelledBy: ATHLETE,
      cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      ...extra,
    };
  }

  it("permite cancelar una ocurrencia de una serie sin tocar recurringId", async () => {
    // Ancla de no-vacuidad: `cancelFutureSeries()` cancela ocurrencia por
    // ocurrencia y NO manda `recurringId`. Si esto se pone rojo, el pin le
    // rompió la salida a la serie entera.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, SERIE), cancelPayload())
    );
  });

  it("DENIEGA mover recurringId en la cancelación", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, SERIE),
        cancelPayload({ recurringId: "serie-de-otro" })
      )
    );
  });

  it("DENIEGA renombrar al atleta en la cancelación", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, SERIE),
        cancelPayload({ athleteDisplayName: "X".repeat(200) })
      )
    );
  });

  it("DENIEGA reescribir id en la cancelación", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, SERIE), cancelPayload({ id: "otro" }))
    );
  });

  it("DENIEGA 30 KB adentro de cancelledAt — el inflado por el campo sin cota", async () => {
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, SERIE),
        cancelPayload({ cancelledAt: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA meter DOS entradas al log en una sola escritura", async () => {
    // Mata el bound de crecimiento. Sin él, `arrayUnion` de a uno es una
    // convención del cliente, no una regla: el log se llenaba de un saque.
    await assertFails(
      updateDoc(
        doc(dbAs(ATHLETE), COL, SERIE),
        cancelPayload({
          cancellationLog: [
            { byUid: ATHLETE, atMs: 1 },
            { byUid: ATHLETE, atMs: 2 },
          ],
        })
      )
    );
  });

  it("DENIEGA la entrada 51 — el tope del log también aplica al update", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, FULL_LOG), cancelPayload())
    );
  });
});

/**
 * #831 (cuarta pasada) — `id` y `cancelledAt` en el `create`.
 *
 * `hasOnly()` acota QUÉ claves entran; `hasAll()` cuáles no pueden faltar.
 * Ninguna de las dos mira el tipo ni el tamaño, y estos dos campos no tenían
 * ni una cosa ni la otra. Medido contra el emulador antes del fix: un `create`
 * con 30 KB adentro de `id`, y otro con 30 KB adentro de `cancelledAt`, los dos
 * ALLOW. Es el hallazgo original de #781 —texto libre sin cota en un documento
 * que no se puede borrar— sobreviviendo en los dos campos que nadie miró.
 */
describe("appointments create — id y cancelledAt también tienen cota (#831)", () => {
  it("DENIEGA 30 KB de texto en id", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-id-inflado"),
        appointment({ id: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA un id que no es string", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), COL, "a-id-int"), appointment({ id: 12 }))
    );
  });

  it("DENIEGA 30 KB de texto en cancelledAt", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-cat-inflado"),
        appointment({ cancelledAt: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA sembrar la cancelación en el create", async () => {
    // Un turno nuevo nace `confirmed` y sin cancelación: es el mismo
    // invariante que el `cancellationLog` vacío, sobre los otros dos campos.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-precancelado"),
        appointment({
          cancelledAt: Timestamp.fromMillis(Date.now() - 86400000),
          cancelledBy: ATHLETE,
        })
      )
    );
  });

  it("DENIEGA sembrar SÓLO cancelledBy en el create", async () => {
    // ⚠️ #831 (quinta pasada) — el caso de arriba manda los DOS campos, así
    // que lo mata el gate de `cancelledAt` solo: borrando
    // `cancelledBy == null` de las reglas, la suite seguía VERDE. Un gate que
    // se revierte en silencio es un gate que no está, y éste nació en este
    // mismo PR. Este caso mueve únicamente `cancelledBy`, así que es el
    // negativo que lo mata.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-firmado-al-nacer"),
        appointment({ cancelledBy: TRAINER })
      )
    );
  });
});

/**
 * #831 (QUINTA pasada) — LA COLUMNA QUE FALTABA: el `create`.
 *
 * La matriz de la cuarta pasada modeló los dos caminos de UPDATE y dejó afuera
 * el `create` — que es justamente el que SIEMBRA el estado del que dependen
 * todos los gates de update. Tres celdas de esa columna estaban abiertas, y las
 * tres se midieron ALLOW contra el emulador antes del fix.
 *
 * La grave es `paymentId`, money-critical y permanente. Su gate set-once vive
 * en el Path 2 y lee `resource.data.paymentId`; el vecino que escribe esa
 * variable no es un update, es el `create`:
 *
 *   un desconocido crea un turno con `paymentId` ya sembrado
 *     → re-linkear al Payment real → DENY (set-once: el valor ya no es null)
 *     → limpiarlo a null           → DENY (el Path 1 lo pinea)
 *     → borrar el turno            → DENY (`delete: if false`)
 *     → el cobro de ese turno queda MUERTO para siempre
 *
 * Las otras dos son `athleteId` / `trainerId` sin tipo en el create, mientras
 * su variante de update los exigía string de forma INCONDICIONAL: las dos
 * mitades juntas dan un turno imborrable. Medido: `trainerId: 12345` pasaba el
 * create, y después el doc no se podía anotar NI cancelar.
 */
describe("appointments create — la columna que la matriz no tenía (#831)", () => {
  it("DENIEGA sembrar paymentId en el create — el cobro muerto", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "a-cobro-sembrado"),
        appointment({
          id: "a-cobro-sembrado",
          athleteId: ATTACKER,
          trainerId: VICTIM_PF,
          paymentId: "pay-del-atacante",
        })
      )
    );
  });

  it("DENIEGA el ataque completo: turno forjado con el cobro ya muerto", async () => {
    // El vector entero, con el actor que lo hace grave: una cuenta `athlete`
    // sin NINGUNA relación con el PF víctima. Si el create volviera a pasar,
    // las tres salidas del PF quedan cerradas — y eso también se assertea acá,
    // para que el test explique el DAÑO y no sólo el gate.
    const ID = "a-ataque-cobro";
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, ID),
        appointment({
          id: ID,
          athleteId: ATTACKER,
          trainerId: VICTIM_PF,
          paymentId: "pay-del-atacante",
        })
      )
    );

    // Y si el doc existiera igual —sembrado por Admin SDK, o creado antes de
    // este fix— las tres salidas siguen cerradas. Es el daño que justifica
    // cerrar el create, medido en vez de afirmado.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, ID),
        appointment({
          id: ID,
          athleteId: ATTACKER,
          trainerId: VICTIM_PF,
          paymentId: "pay-del-atacante",
        })
      );
    });
    // re-linkear al Payment real: el set-once ya no ve null
    await assertFails(
      updateDoc(doc(dbAs(VICTIM_PF), COL, ID), { paymentId: "pay-real" })
    );
    // limpiarlo: el Path 2 no deja volver a null
    await assertFails(
      updateDoc(doc(dbAs(VICTIM_PF), COL, ID), { paymentId: null })
    );
    // y por el Path 1 tampoco, que es el pin de la cuarta pasada
    await assertFails(
      updateDoc(doc(dbAs(ATTACKER), COL, ID), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: ATTACKER,
        paymentId: null,
      })
    );
  });

  it("DENIEGA un trainerId que no es string — el turno imborrable sembrado al nacer", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-trainerid-int"),
        appointment({ id: "a-trainerid-int", trainerId: 12345 })
      )
    );
  });

  it("DENIEGA un athleteId que no es string", async () => {
    // Por el disyunto del PF: `trainerId == auth.uid` deja `athleteId` libre.
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "a-athleteid-int"),
        appointment({
          id: "a-athleteid-int",
          trainerId: TRAINER_BOOKER,
          athleteId: 12345,
        })
      )
    );
  });

  it("DENIEGA un trainerId vacío", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "a-trainerid-vacio"),
        appointment({ id: "a-trainerid-vacio", trainerId: "" })
      )
    );
  });
});

/**
 * #831 (quinta pasada) — los docs que YA nacieron mal se siguen pudiendo
 * cerrar.
 *
 * Tipar `athleteId` / `trainerId` en el create cierra el origen, pero no
 * destraba lo ya escrito: el chequeo del update era INCONDICIONAL, o sea
 * validaba el DOCUMENTO y no la escritura, y eso dejaba esos docs sin poder
 * anotarse ni cancelarse — `delete: if false`, imborrable. Y pueden existir:
 * antes de #781 el create no validaba NADA, y `treino-dev` ES producción
 * (#826), así que no se le corren queries para saberlo.
 *
 * Es el mismo patrón que ya se corrigió para `durationMin`, `startsAt` y
 * `cancelledAt`, sobre los dos campos que faltaban.
 */
describe("appointments update — un turno legacy con ids mal tipados se sigue pudiendo cerrar (#831)", () => {
  const LEGACY_TID = "appt-legacy-trainerid-int";
  const LEGACY_AID = "appt-legacy-athleteid-int";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_TID),
        appointment({ id: LEGACY_TID, trainerId: 12345 })
      );
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_AID),
        appointment({ id: LEGACY_AID, athleteId: 12345 })
      );
    });
  });

  it("permite al atleta cancelar un legacy con trainerId no-string — sin esto es imborrable", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, LEGACY_TID), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({ at: inDays(0), byUid: ATHLETE }),
      })
    );
  });

  it("permite al PF anotar un legacy con athleteId no-string", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_AID), { noteAfter: "ok" })
    );
  });

  it("DENIEGA que el update MUEVA trainerId a un valor que no es string", async () => {
    // El chequeo sigue mordiendo cuando la escritura toca el campo — que es lo
    // único que una regla puede custodiar.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_AID), { trainerId: 999 })
    );
  });
});

/**
 * #831 (quinta pasada) — `athleteDisplayName` en el Path 2 aceptaba **null**.
 *
 * La matriz lo documentaba como `<= 200`, pero la cota medida era
 * "`<= 200` **O null O ausente**": `optStrMaxLen()` es opcional por diseño y el
 * campo es `required String` en el modelo. Dos escrituras y el stream de las
 * DOS partes se cae — `Appointment.fromJson` explota con null, y una sola fila
 * rompe `watchForTrainer` y `watchForAthlete` enteros. El atleta no lo puede
 * reparar: el Path 1 pinea el campo.
 */
describe("appointments update — el nombre del atleta no puede quedar en null (#831)", () => {
  const ID = "appt-nombre";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, ID),
        appointment({ id: ID })
      );
    });
  });

  it("DENIEGA al PF poner athleteDisplayName en null", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, ID), { athleteDisplayName: null })
    );
  });

  it("DENIEGA al PF pasarse de 200 caracteres en el nombre", async () => {
    // ⚠️ Este gate tampoco tenía cobertura: se podía borrar
    // `athleteDisplayName <= 200` del update y la suite seguía VERDE, porque
    // el único caso que tocaba el campo era el pin del Path 1.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, ID), {
        athleteDisplayName: "x".repeat(201),
      })
    );
  });

  it("DENIEGA al PF poner un athleteDisplayName que no es string", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, ID), { athleteDisplayName: 42 })
    );
  });

  it("permite al PF refrescar el nombre — la celda que la matriz deja escribible", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, ID), {
        athleteDisplayName: "Juan Pérez (renombrado)",
      })
    );
  });

  it("permite cerrar un legacy que YA tiene el nombre en null", async () => {
    // La rama del pin: si el valor no CAMBIA, el doc heredado se sigue
    // pudiendo cancelar. Sin esto el fix reintroduce la familia "imborrable".
    const LEGACY = "appt-legacy-sin-nombre";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY),
        appointment({ id: LEGACY, athleteDisplayName: null })
      );
    });
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, LEGACY), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: ATHLETE,
      })
    );
  });
});

/**
 * #831 (cuarta pasada) — el tipo de `startsAt` en el update también validaba el
 * documento HEREDADO.
 *
 * Es el mismo error que el bloque de `durationMin` de acá arriba documenta,
 * cometido dos líneas más abajo en la misma función y en el mismo PR. Medido:
 * un doc con `startsAt` guardado como string o como número de millis —o con
 * `cancelledAt` guardado como string— dejaba de poder anotarse Y de poder
 * cancelarse. `delete: if false`: imborrable, la familia de #781 otra vez.
 *
 * Condicionar los dos chequeos a que el campo CAMBIE no pierde nada: los DOS
 * caminos pinean `startsAt`, y `cancelledAt` está pineado en el Path 2 y
 * tipado en el Path 1, que es el único que lo escribe.
 */
describe("appointments update — un turno legacy con tipos raros se sigue pudiendo cerrar (#831)", () => {
  const LEGACY_STR = "appt-legacy-startsat-string";
  const LEGACY_MS = "appt-legacy-startsat-millis";
  const LEGACY_CAT = "appt-legacy-cancelledat-string";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_STR),
        appointment({ id: LEGACY_STR, startsAt: "2026-01-01T10:00:00Z" })
      );
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_MS),
        appointment({ id: LEGACY_MS, startsAt: Date.now() + 5 * 86400000 })
      );
      await setDoc(
        doc(ctx.firestore(), COL, LEGACY_CAT),
        appointment({ id: LEGACY_CAT, cancelledAt: "no-es-timestamp" })
      );
    });
  });

  it("permite al PF anotar un legacy con startsAt guardado como string", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_STR), { noteAfter: "ok" })
    );
  });

  it("permite al PF anotar un legacy con startsAt guardado en millis", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_MS), { noteAfter: "ok" })
    );
  });

  it("permite al PF anotar un legacy con cancelledAt guardado como string", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_CAT), { noteAfter: "ok" })
    );
  });

  it("DENIEGA que el update MUEVA startsAt a un valor que no es timestamp", async () => {
    // El chequeo sigue mordiendo cuando la escritura toca el campo — que es lo
    // único que una regla puede custodiar.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, LEGACY_MS), {
        startsAt: "2030-01-01T10:00:00Z",
      })
    );
  });
});

/**
 * #831 (cuarta pasada) — PARIDAD DE ESCRITORES.
 *
 * Cada pasada de este ticket agregó pines, y cada pin es una forma de romper
 * la app: `request.resource.data` es el documento MERGEADO, así que un pin sólo
 * es gratis mientras NINGÚN escritor real mande ese campo. Eso se venía
 * verificando a mano contra el emulador y anotándose en `docs/security.md` —
 * una afirmación en un doc, que no se pone roja cuando deja de ser cierta.
 *
 * Acá está como test. Cada caso es el mapa LITERAL que manda un escritor de
 * `AppointmentRepository`, con el mismo actor que la UI usa para llamarlo. Si
 * un pin futuro le pisa la cola a un escritor vivo, esto se pone rojo antes de
 * llegar a producción, que es donde se descubriría si no.
 *
 * `book()` no está: no tiene llamadores en `lib/` y su rama de ADR-1 —el flip
 * `cancelled → confirmed`— la DENIEGA la regla a propósito desde #831; los
 * casos que custodian esa ausencia están en el bloque del flip.
 */
/**
 * #831 (sexta pasada) — el `cancellationLog` del `create` tenía cota de
 * TAMAÑO, no de TIPO.
 *
 * `size()` en las reglas no es un método de las listas: lo tienen también los
 * String y los Map. Así que `d.get('cancellationLog', []).size() == 0` no dice
 * "log vacío" —que es como se leyó al escribirlo— sino **"algo que mide
 * cero"**, y eso lo cumplen `[]`, `""` y `{}` por igual.
 *
 * El daño NO es el inflado: 30 KB adentro del campo ya daban DENY, porque
 * miden 30000 y no 0. Es peor. El doc nace `status: 'confirmed'`, o sea entra
 * al stream VIVO —las tres queries de `appointment_repository.dart` filtran
 * `where('status', isEqualTo: 'confirmed')`—, y ahí
 * `Appointment.fromJson` lo castea con
 * `(json['cancellationLog'] as List<dynamic>?)`. Medido en Dart, las dos
 * variantes tiran `_TypeError`:
 *   · `""` → type 'String' is not a subtype of type 'List<dynamic>?'
 *   · `{}` → type '_Map<String, dynamic>' is not a subtype of type 'List…'
 * Una sola fila forjada rompe la deserialización del snapshot ENTERO, o sea la
 * agenda completa del PF, escrita por un desconocido —el disyunto del `create`
 * sólo pide `athleteId == auth.uid`— y sin forma de sacarla:
 * `allow delete: if false`.
 *
 * Medición de punta a punta, antes y después del `is list`:
 *   ANTES  → `""` ALLOW, `{}` ALLOW, query del PF `status == 'confirmed'`
 *            devuelve 2 docs forjados.
 *   DESPUÉS→ `""` DENY,  `{}` DENY,  la misma query devuelve 0.
 *
 * La pregunta que lo destapó, y que es la que le faltaba a cada celda de la
 * matriz de §4.9: **¿esta cota chequea el TIPO, o sólo una propiedad que
 * varios tipos comparten?**. Las otras 13 filas de la columna del `create` la
 * sobreviven, medidas una por una — ver §4.9.
 */
describe("appointments create — el cancellationLog tiene que ser una LISTA (#831)", () => {
  const FORGED = { athleteId: ATTACKER, trainerId: VICTIM_PF };

  it("DENIEGA un cancellationLog que es un String vacío — mide cero y no es una lista", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "log-str"),
        appointment({ id: "log-str", ...FORGED, cancellationLog: "" })
      )
    );
  });

  it("DENIEGA un cancellationLog que es un Map vacío", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "log-map"),
        appointment({ id: "log-map", ...FORGED, cancellationLog: {} })
      )
    );
  });

  it("DENIEGA un cancellationLog que es un Map con claves — `size()` cuenta claves, no caracteres", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "log-map2"),
        appointment({
          id: "log-map2",
          ...FORGED,
          cancellationLog: { byUid: ATTACKER, at: "forjado" },
        })
      )
    );
  });

  it("DENIEGA un cancellationLog que es un int — no tiene `size()` y la regla no evalúa", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "log-int"),
        appointment({ id: "log-int", ...FORGED, cancellationLog: 0 })
      )
    );
  });

  // Ancla de no-vacuidad: el `is list` no puede romper el create legítimo, que
  // manda `[]` porque el modelo lo crea con `@Default([])`.
  it("permite el create legítimo con el log en `[]` — el `is list` no rompe la lista vacía", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(ATHLETE), COL, "log-ok"),
        appointment({ id: "log-ok", cancellationLog: [] })
      )
    );
  });

  // Y el turno forjado ya no llega al stream del PF. Esta es la mitad de la
  // medición que importa: la regla que deniega es un medio, el fin es que la
  // agenda del PF no se rompa.
  it("el turno forjado ya no aparece en la query de watchForTrainer", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATTACKER), COL, "log-stream"),
        appointment({ id: "log-stream", ...FORGED, cancellationLog: "" })
      )
    );
    const snap = await getDocs(
      query(
        collection(dbAs(VICTIM_PF), COL),
        where("trainerId", "==", VICTIM_PF),
        where("status", "==", "confirmed")
      )
    );
    expect(snap.size).toBe(0);
  });
});

/**
 * #831 (sexta pasada) — la cota de 5000 caracteres del camino de UPDATE no
 * tenía cobertura de mutación. Es **el vector original de #781**, y hasta acá
 * era borrable con los 94 tests en verde.
 *
 * Los dos `optStrMaxLen(…, 5000)` de `appointmentUpdateShapeOk()` son lo único
 * que impide que el cap del `create` se esquive en dos escrituras: crear un
 * turno chico y engordarlo un segundo después. Medido, con los dos conjuntos
 * reemplazados por `true`:
 *   · el PF escribe 30 KB en `noteBefore` por el Path 2 → ALLOW, y el doc
 *     queda `status: 'confirmed'`, `noteBefore.length == 30000` — o sea DENTRO
 *     del stream vivo de `watchForTrainer`.
 *   · el único caso que había —el de "engordar colgándose de una cancelación
 *     válida"— seguía VERDE, porque no mandaba `cancelledBy` y el Path 1 no
 *     matcheaba. Verde por la estructura de paths, no por la cota: la misma
 *     enfermedad que su propio comentario documenta, reintroducida por el pin
 *     de `cancelledBy` que agregó este mismo PR.
 *
 * El Path 2 es el que hace falta cubrir, porque es el que deja el documento
 * CONFIRMADO. Los casos de abajo son los dos campos × el camino que los
 * escribe de verdad, más las anclas de no-vacuidad en el borde exacto.
 */
describe("appointments update — la cota de 5000 custodia el vector original de #781 (#831)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", TRAINER), {
        uid: TRAINER,
        role: "trainer",
      });
      for (const id of ["cap-1", "cap-2", "cap-3", "cap-4", "cap-5", "cap-6"]) {
        await setDoc(
          doc(ctx.firestore(), COL, id),
          appointment({ id, startsAt: inDays(5) })
        );
      }
    });
  });

  it("DENIEGA al PF engordar noteBefore por el Path 2 — el turno queda CONFIRMADO, o sea en el stream", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "cap-1"), {
        noteBefore: "x".repeat(30000),
      })
    );
  });

  it("DENIEGA al PF engordar noteAfter por el Path 2 — la nota post-sesión es el uso normal de la feature", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "cap-2"), {
        noteAfter: "x".repeat(30000),
      })
    );
  });

  it("DENIEGA 5001 caracteres — el borde exacto, un carácter arriba", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "cap-3"), {
        noteBefore: "x".repeat(5001),
      })
    );
  });

  it("permite 5000 caracteres exactos — ancla de no-vacuidad del borde", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "cap-4"), {
        noteBefore: "x".repeat(5000),
        noteAfter: "x".repeat(5000),
      })
    );
  });

  it("DENIEGA engordar noteBefore en una cancelación FIRMADA — el Path 1 tampoco es puerta", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "cap-5"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        noteBefore: "x".repeat(30000),
      })
    );
  });

  it("permite la MISMA cancelación firmada con una nota dentro de la cota — lo único que separa el DENY es el largo", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, "cap-6"), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        noteBefore: "x".repeat(5000),
      })
    );
  });
});

/**
 * #831 (sexta pasada) — las otras cuatro cotas de 30 KB que seguían **sin
 * custodia**, y que son el vector LITERAL de #781.
 *
 * El barrido de mutación en serio —los 42 conjuntos de las dos funciones de
 * forma, uno por uno contra el emulador— dio **25 ceros** sobre el HEAD
 * anterior. La mitad son gates SUBSUMIDOS (otro conjunto tapa el mismo ataque,
 * así que borrarlos no abre nada); la otra mitad son **borrables en silencio
 * con daño medido**. La clasificación no es razonada: cada cero se midió
 * aplicando su mutación y tirándole la escritura hostil que ese gate custodia,
 * y se anotó si pasaba a ALLOW. La tabla entera está en `docs/security.md`
 * §4.9.
 *
 * De los 14 con daño real, éstos cuatro son **el mismo texto de 30 KB que
 * QA-SEC-014 vino a cerrar**, y en los cuatro el documento queda `confirmed`,
 * o sea DENTRO del stream vivo. Por eso se cierran acá y no en un issue:
 * cuestan un test cada uno, la regla ya estaba bien escrita, lo único que
 * faltaba era la custodia.
 *
 * Medido, con cada conjunto reemplazado por `true` de a uno:
 *   · `create` sin `optStrMaxLen(noteAfter, 5000)`    → 30 KB ALLOW
 *   · `create` sin `optStrMaxLen(recurringId, 128)`   → 30 KB ALLOW
 *   · `update` sin `keys().hasOnly()`                 → el PF cuelga una clave
 *     arbitraria de 30 KB por el Path 2, y el turno sigue `confirmed`
 *   · `update` sin `optStrMaxLen(paymentId, 128)`     → el PF factura con un
 *     `paymentId` de 30 KB. Es money-critical Y permanente: el gate es
 *     set-once, así que el valor basura no se puede corregir nunca más.
 *
 * Los 10 restantes —tipo y tamaño de `athleteId` / `trainerId` / `id`, tipo de
 * `athleteDisplayName`, tipo y piso de `durationMin`— están listados con su
 * daño medido en §4.9 y van a issue: son de otra familia (identidad y forma,
 * no inflado de texto) y algunos piden decidir el comportamiento, no sólo
 * escribir un negativo.
 */
describe("appointments — las cuatro cotas de 30 KB que quedaban sin custodia (#831)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "users", TRAINER), {
        uid: TRAINER,
        role: "trainer",
      });
      for (const id of ["z1", "z2", "z3"]) {
        await setDoc(
          doc(ctx.firestore(), COL, id),
          appointment({ id, startsAt: inDays(5) })
        );
      }
    });
  });

  it("DENIEGA 30 KB de texto en noteAfter — el gemelo de noteBefore, en el create", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "z-note-after"),
        appointment({ id: "z-note-after", noteAfter: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA 30 KB de texto en recurringId — el create", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "z-rec"),
        appointment({ id: "z-rec", recurringId: "x".repeat(30000) })
      )
    );
  });

  it("DENIEGA al PF colgar una clave nueva por el Path 2 — el turno queda CONFIRMADO", async () => {
    // El caso que había para `hasOnly()` en el update viajaba sobre una
    // cancelación SIN firmar, así que lo denegaba la estructura de paths y no
    // la allowlist. Éste va por el Path 2, que es el que deja el documento
    // dentro del stream de `watchForTrainer`.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "z1"), {
        basura: "x".repeat(30000),
      })
    );
  });

  it("DENIEGA al PF facturar con un paymentId de 30 KB — set-once, o sea permanente", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, "z2"), {
        paymentId: "x".repeat(30000),
      })
    );
  });

  it("permite la facturación real — ancla de no-vacuidad del set-once", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "z3"), { paymentId: "payment-1" })
    );
  });
});

describe("appointments — los escritores reales de AppointmentRepository siguen pasando (#831)", () => {
  const SER = "serie-parity";

  async function seedConfirmed(
    id: string,
    overrides: Record<string, unknown> = {}
  ) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, id),
        appointment({ id, trainerId: TRAINER, startsAt: inDays(5), ...overrides })
      );
    });
  }

  // ── creadores ───────────────────────────────────────────────────────────

  it("1. createByTrainer — toJson() completo, sin nota", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "w-create-1"),
        appointment({
          id: "w-create-1",
          trainerId: TRAINER_BOOKER,
          startsAt: inDays(2),
        })
      )
    );
  });

  it("2. createByTrainer — con noteBefore", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "w-create-2"),
        appointment({
          id: "w-create-2",
          trainerId: TRAINER_BOOKER,
          startsAt: inDays(2),
          noteBefore: "traer banda elástica",
        })
      )
    );
  });

  it("3. createRecurringByTrainer — dos ocurrencias con el mismo recurringId", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "w-rec-1"),
        appointment({
          id: "w-rec-1",
          trainerId: TRAINER_BOOKER,
          startsAt: inDays(7),
          recurringId: SER,
        })
      )
    );
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "w-rec-2"),
        appointment({
          id: "w-rec-2",
          trainerId: TRAINER_BOOKER,
          startsAt: inDays(14),
          recurringId: SER,
        })
      )
    );
  });

  // ── cancelación ─────────────────────────────────────────────────────────

  it("4. cancel() — el atleta, con serverTimestamp", async () => {
    await seedConfirmed("w-cancel-athlete");
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, "w-cancel-athlete"), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({ byUid: ATHLETE, atMs: Date.now() }),
      })
    );
  });

  it("5. cancel() — el PF", async () => {
    await seedConfirmed("w-cancel-trainer");
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-cancel-trainer"), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
      })
    );
  });

  it("6. cancel() — con reason en la entrada del log", async () => {
    await seedConfirmed("w-cancel-reason");
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-cancel-reason"), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({
          byUid: TRAINER,
          atMs: Date.now(),
          reason: "el alumno avisó",
        }),
      })
    );
  });

  it("7. cancelFutureSeries() — dos ocurrencias de la misma serie", async () => {
    await seedConfirmed("w-serie-1", { recurringId: SER });
    await seedConfirmed("w-serie-2", { recurringId: SER, startsAt: inDays(12) });
    const atMs = Date.now();
    for (const id of ["w-serie-1", "w-serie-2"]) {
      await assertSucceeds(
        updateDoc(doc(dbAs(TRAINER), COL, id), {
          status: "cancelled",
          cancelledAt: serverTimestamp(),
          cancelledBy: TRAINER,
          cancellationLog: arrayUnion({ byUid: TRAINER, atMs }),
        })
      );
    }
  });

  it("8. cancel() sobre un turno YA cobrado", async () => {
    await seedConfirmed("w-cancel-billed", { paymentId: "pay-real" });
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-cancel-billed"), {
        status: "cancelled",
        cancelledAt: serverTimestamp(),
        cancelledBy: TRAINER,
        cancellationLog: arrayUnion({ byUid: TRAINER, atMs: Date.now() }),
      })
    );
  });

  // ── notas ───────────────────────────────────────────────────────────────

  it("9. updateNotes() — las dos con texto", async () => {
    await seedConfirmed("w-notes-text");
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-notes-text"), {
        noteBefore: "calentar 10'",
        noteAfter: "subió 5 kg en banco",
      })
    );
  });

  it("10. updateNotes() — las dos en null (el mapa literal manda null, no las omite)", async () => {
    await seedConfirmed("w-notes-null", {
      noteBefore: "algo",
      noteAfter: "algo",
    });
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-notes-null"), {
        noteBefore: null,
        noteAfter: null,
      })
    );
  });

  it("11. updateNotes() sobre un turno CANCELADO — sigue siendo el mismo camino", async () => {
    await seedConfirmed("w-notes-cancelled", {
      status: "cancelled",
      cancelledAt: Timestamp.fromMillis(Date.now() - 3600000),
      cancelledBy: TRAINER,
      cancellationLog: [{ byUid: TRAINER, atMs: Date.now() - 3600000 }],
    });
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-notes-cancelled"), {
        noteAfter: "no vino",
      })
    );
  });

  // ── cobro ───────────────────────────────────────────────────────────────

  it("12. billAppointment() / markBilled() — el update del turno", async () => {
    await seedConfirmed("w-bill-1");
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, "w-bill-1"), { paymentId: "pay-nuevo" })
    );
  });

  it("13. billAppointments() — el mismo Payment sobre dos turnos del lote", async () => {
    await seedConfirmed("w-bill-lote-1");
    await seedConfirmed("w-bill-lote-2", { startsAt: inDays(6) });
    for (const id of ["w-bill-lote-1", "w-bill-lote-2"]) {
      await assertSucceeds(
        updateDoc(doc(dbAs(TRAINER), COL, id), { paymentId: "pay-lote" })
      );
    }
  });
});

/**
 * #846 — el `reason` del cascade: la clave que congelaba el turno, y que ahora
 * es la señal CF→CF que ningún cliente puede escribir.
 *
 * `functions/src/cascade/appointments.ts` escribe `reason:
 * 'athlete-account-deleted'` con Admin SDK, y `notify-appointment.ts` la lee de
 * GUARD para NO notificar la cancelación (ADR-PN-006 / REQ-PN-CF-003).
 *
 * El bug: `reason` NO estaba en `hasOnly()`. El Admin SDK saltea las reglas,
 * así que la escritura pasaba; el daño quedaba después. `hasOnly()` corre sobre
 * `request.resource.data`, el documento **MERGEADO**, así que cualquier update
 * PARCIAL posterior del cliente arrastraba el `reason` guardado y la allowlist
 * lo rechazaba. Nuestro propio backend fabricaba turnos imborrables.
 *
 * ⚠️ El primer fix MOVÍA el motivo adentro del `cancellationLog` y pedía una
 * migración contra producción para destrabar lo ya escrito. Se revirtió por el
 * bloque de abajo: las reglas **no iteran listas** —está escrito sobre el
 * Path 1: *«ese sigue siendo forjable porque las reglas no iteran listas»*—,
 * así que ese motivo lo forja cualquier miembro del turno y el guard deja de
 * ser un guard.
 *
 * La salida es la contraria: `reason` ENTRA a las dos allowlists y queda
 * pineada en los dos caminos de cliente, `== null` en el `create` y con el
 * `delete` cerrado. Los documentos que ya están escritos se destraban con el
 * deploy de las reglas, sin correr nada contra producción.
 */
describe("appointments — `reason` es la señal del cascade y NO congela el turno (#846)", () => {
  const CONGELADO = "appt-846-con-reason";

  beforeEach(async () => {
    // El documento tal como lo dejó la CF: `reason` de primer nivel, escrito
    // con Admin SDK. Es la forma que HAY en producción hoy.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), COL, CONGELADO), {
        ...appointment({ id: CONGELADO, startsAt: inDays(5) }),
        reason: "athlete-account-deleted",
      });
    });
  });

  it("el atleta PUEDE cancelar un turno que lleva `reason` — el daño de #846, cerrado", async () => {
    // Éste es EL caso del issue. Contra las reglas anteriores daba DENY, y con
    // `allow delete: if false` el turno quedaba fijo en la agenda para siempre.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, CONGELADO), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });

  it("el PF PUEDE anotar un turno que lleva `reason`", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, CONGELADO), { noteAfter: "ok" })
    );
  });

  // ── Y la contraparte: la clave es INESCRIBIBLE para el cliente ───────────
  //
  // Estos cinco casos son lo que hace confiable al guard de
  // `notify-appointment.ts`. Si alguno se pone verde en ALLOW, el guard pasa a
  // ser forjable y un miembro del turno silencia al otro.

  it("DENIEGA al atleta AGREGAR `reason` mientras cancela (Path 1)", async () => {
    const LIMPIO = "appt-846-limpio";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LIMPIO),
        appointment({ id: LIMPIO, startsAt: inDays(5) })
      );
    });
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, LIMPIO), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        reason: "athlete-account-deleted",
      })
    );
  });

  it("DENIEGA al PF AGREGAR `reason` mientras anota (Path 2)", async () => {
    const LIMPIO = "appt-846-limpio-2";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, LIMPIO),
        appointment({ id: LIMPIO, startsAt: inDays(5) })
      );
    });
    // El vecino del Path 1. Blindar un solo camino es perseguir el vector.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, LIMPIO), {
        noteAfter: "ok",
        reason: "athlete-account-deleted",
      })
    );
  });

  it("DENIEGA CAMBIAR el `reason` que ya tiene el documento", async () => {
    // Por el Path 2, que es el único camino que el PF tiene sobre un turno
    // `confirmed`.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONGELADO), { reason: "otra-cosa" })
    );
  });

  it("DENIEGA al PF BORRAR el `reason` que escribió la CF", async () => {
    // Borrarlo también es control de flujo: deja el documento sin la marca de
    // que el cascade lo tocó.
    //
    // ⚠️ El actor es el PF a propósito. Con el ATLETA este caso sería VACUO: su
    // único camino es el Path 1, que exige `status == 'cancelled'`, así que un
    // update que sólo borra `reason` sobre un turno `confirmed` da DENY por el
    // status y no por el pin. Medido sacando el pin: con el atleta seguía en
    // verde. Un caso que no se pone rojo cuando borrás la regla que dice
    // custodiar no custodia nada.
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CONGELADO), { reason: deleteField() })
    );
  });

  it("DENIEGA crear un turno con `reason`", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), COL, "appt-846-create"), {
        ...appointment({ id: "appt-846-create" }),
        reason: "athlete-account-deleted",
      })
    );
  });

  it("crear con `reason: null` explícito sigue estando bien", async () => {
    // Ancla de no-vacuidad: lo que se prohíbe es el VALOR, no la clave. Un
    // cliente que mande la clave en null no se rompe.
    await assertSucceeds(
      setDoc(doc(dbAs(ATHLETE), COL, "appt-846-create-null"), {
        ...appointment({ id: "appt-846-create-null" }),
        reason: null,
      })
    );
  });

  // ── La forja que tumbó el fix anterior ──────────────────────────────────

  it("el motivo DENTRO del cancellationLog sí lo forja el cliente — por eso el guard no lo lee", async () => {
    // Esto es ALLOW, y está bien que lo sea: es una cancelación legítima por el
    // Path 1, y las reglas no pueden mirar adentro de la entrada del log.
    //
    // Lo que prueba es por qué el guard NO puede leer ahí: mientras lo hizo,
    // esta misma escritura dejaba al PF sin push y sin mail. La consecuencia
    // está medida en
    // `functions/src/__tests__/cascade/appointments-notify-contract.test.ts`.
    const FORJA = "appt-846-forja";
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, FORJA),
        appointment({ id: FORJA, startsAt: inDays(5) })
      );
    });
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, FORJA), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        cancellationLog: arrayUnion({
          byUid: ATHLETE,
          atMs: 1,
          reason: "athlete-account-deleted",
        }),
      })
    );
  });
});

/**
 * #847 — un turno con `startsAt` de otro tipo se podía ANOTAR pero no CANCELAR.
 *
 * Residuo medido de #831. Ese PR condicionó el `is timestamp` de
 * `appointmentUpdateShapeOk()` a que el campo CAMBIE, y con eso el doc heredado
 * se volvió anotable. Arregló **la mitad**: el gate de 24 h del Path 1 lee el
 * valor VIEJO con acceso directo (`resource.data.startsAt.toMillis()`), y sobre
 * un `startsAt` que no es `timestamp` —o que no está— `.toMillis()` no evalúa y
 * la regla FALLA CERRADO.
 *
 * Medido sobre el HEAD anterior, y es la tabla del issue:
 *   · `startsAt: "manana"` (string)   → anotar ALLOW, cancelar **DENY**
 *   · `startsAt: 1787…` (millis, int) → cancelar **DENY**
 *   · sin el campo                    → cancelar **DENY** (residuo hermano)
 * El Path 1 es el ÚNICO camino de salida de un turno y `allow delete: if false`:
 * el turno quedaba fijo en la agenda. La familia de #781, por la puerta que
 * quedaba.
 *
 * La decisión que cierra el issue está escrita sobre el gate mismo: un
 * `startsAt` que no es timestamp NO TIENE "24 horas antes" que calcular, así
 * que se lo cancela sin gate temporal. No abre nada porque ese estado ya no se
 * puede fabricar — el `create` exige `is timestamp` incondicional y el `update`
 * sólo deja escribir un timestamp cuando el campo cambia. La rama nueva sólo la
 * alcanzan documentos anteriores a #781.
 *
 * ⚠️ El caso de no-vacuidad del gate va en el bloque de acá abajo, y NO es
 * decoración: al condicionar el gate hay que probar que sigue mordiendo sobre
 * un doc bien tipado. Sin ese negativo, el gate entero pasa a ser borrable con
 * la suite en verde — que es exactamente el hallazgo de #850.
 */
describe("appointments update — un turno legacy con startsAt roto se puede CANCELAR (#847)", () => {
  const L_STR = "appt-847-string";
  const L_MS = "appt-847-millis";
  const L_NONE = "appt-847-sin-campo";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), COL, L_STR),
        appointment({ id: L_STR, startsAt: "manana" })
      );
      await setDoc(
        doc(ctx.firestore(), COL, L_MS),
        appointment({ id: L_MS, startsAt: Date.now() + 5 * 86400000 })
      );
      const sinCampo = appointment({ id: L_NONE });
      delete sinCampo.startsAt;
      await setDoc(doc(ctx.firestore(), COL, L_NONE), sinCampo);
    });
  });

  it("permite al atleta cancelar un legacy con startsAt string — sin esto es imborrable", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, L_STR), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });

  it("permite al PF cancelar un legacy con startsAt guardado en millis", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, L_MS), {
        status: "cancelled",
        cancelledBy: TRAINER,
      })
    );
  });

  it("permite cancelar un legacy SIN startsAt — el residuo hermano del mismo acceso directo", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, L_NONE), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });

  it("el legacy roto se sigue pudiendo ANOTAR — la mitad que #831 ya había cerrado", async () => {
    // Ancla: este caso es el que separa "#847 agregó algo" de "#847 rompió lo
    // anterior". Si el fix del gate hubiera tocado la forma, esto se cae.
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), COL, L_STR), { noteAfter: "ok" })
    );
  });

  it("DENIEGA que la cancelación del legacy MUEVA startsAt de paso", async () => {
    // El pin pasó a `.get()` para no fallar cerrado sobre el doc sin campo;
    // sigue mordiendo cuando la escritura toca el valor.
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, L_STR), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        startsAt: inDays(9),
      })
    );
  });

  it("DENIEGA ponerle un startsAt al doc que no lo tiene, colgándose de la cancelación", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, L_NONE), {
        status: "cancelled",
        cancelledBy: ATHLETE,
        startsAt: inDays(9),
      })
    );
  });
});

/**
 * #847 / #850 — el gate de 24 h no tenía UN SOLO negativo.
 *
 * `resource.data.startsAt.toMillis() - 86400000 > request.time.toMillis()` es
 * el único freno del camino de cancelación —el vector que #781 vino a cerrar—
 * y era borrable con la suite entera en verde: el bloque de arriba tiene el
 * positivo (`permite al miembro cancelar con más de 24 h`), pero un positivo no
 * custodia nada. Medido con el conjunto reemplazado por `true`: 0 rojos.
 *
 * Y ahora hace falta el doble, porque #847 le agregó una rama: sin este caso,
 * la mutación del gate condicionado tampoco se pone roja y el fix habría
 * cambiado "gate sin custodia" por "gate sin custodia, más ancho".
 */
describe("appointments update — el gate de 24 h sigue mordiendo (#847)", () => {
  const CERCA = "appt-24h-cerca";
  const LEJOS = "appt-24h-lejos";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      // 6 h vista: bien tipado, o sea la rama del gate que SÍ compara.
      await setDoc(
        doc(ctx.firestore(), COL, CERCA),
        appointment({
          id: CERCA,
          startsAt: Timestamp.fromMillis(Date.now() + 6 * 3600000),
        })
      );
      await setDoc(
        doc(ctx.firestore(), COL, LEJOS),
        appointment({ id: LEJOS, startsAt: inDays(5) })
      );
    });
  });

  it("DENIEGA al atleta cancelar a menos de 24 h — REQ-007", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, CERCA), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });

  it("DENIEGA al PF cancelar a menos de 24 h", async () => {
    await assertFails(
      updateDoc(doc(dbAs(TRAINER), COL, CERCA), {
        status: "cancelled",
        cancelledBy: TRAINER,
      })
    );
  });

  it("permite cancelar el mismo turno a 5 días — lo único que separa el DENY es la distancia", async () => {
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, LEJOS), {
        status: "cancelled",
        cancelledBy: ATHLETE,
      })
    );
  });
});

/**
 * #850 — los 10 gates de `appointmentShapeOk()` que nadie custodiaba.
 *
 * Del barrido de mutación en serio de #831: los **42 conjuntos** de
 * `appointmentShapeOk()` / `appointmentUpdateShapeOk()`, uno por uno,
 * reemplazados por `true` de a UNO SOLO, corriendo esta suite entre cada
 * mutación. #831 cerró 7 de las 25 filas que daban 0 rojos; estas 10 quedaban
 * **borrables con la suite entera en verde**, y cada una con su daño medido —
 * o sea que no son ceros por gate SUBSUMIDO, son ceros por gate SIN CUSTODIA.
 *
 * ⚠️ Las reglas están bien escritas: ninguna de estas escrituras pasa hoy. Lo
 * que faltaba es que borrar el gate ponga rojo a alguien, porque si no un
 * refactor futuro lo saca sin enterarse. Es literalmente lo que le pasó a
 * `cancelledBy == null` y a `athleteDisplayName <= 200` antes de #831.
 *
 * ─── Por qué el payload de cada caso es EXACTAMENTE ése ─────────────────────
 *
 * La suite YA tenía negativos para varios de estos campos, y pasaban **por el
 * motivo equivocado**: con `athleteId: 12345` y el `is string` borrado, la
 * regla no se afloja — `12345.size()` no evalúa y falla cerrado igual. El
 * ataque que mide el gate es el que **sobrevive a su ausencia**, y para los
 * `is string` eso es una LISTA: `['x'].size()` da 1, así que sin el `is string`
 * entra. Es la misma pregunta que destapó el `cancellationLog` en la sexta
 * pasada de #831: **¿esta cota chequea el TIPO, o sólo una propiedad que varios
 * tipos comparten?**
 *
 * `athleteDisplayName: []` es el más interesante de los diez: una lista vacía
 * mide 0, o sea cumple `<= 200`, y el campo es `required String` en el modelo.
 * Sin el `is string`, `Appointment.fromJson` explota y **una sola fila rompe el
 * stream entero** de `watchForTrainer` y `watchForAthlete`.
 *
 * ─── Y por qué el disyunto importa ──────────────────────────────────────────
 *
 * Los ataques sobre `athleteId` van por el camino del PF con rol
 * (`TRAINER_BOOKER`), no por el del atleta: el disyunto del atleta compara
 * `athleteId == request.auth.uid` y se cae AHÍ, antes de llegar a la forma —
 * el "negativo que no avisa" de #837. Los de `trainerId` van al revés, por el
 * disyunto del atleta, que deja `trainerId` libre.
 */
describe("appointments create — los 10 gates sin custodia (#850)", () => {
  // ── athleteId: por el disyunto del PF, que lo deja libre ────────────────

  it("DENIEGA un athleteId que es una LISTA — `['x']` mide 1 y esquiva las cotas", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "g-athleteid-list"),
        appointment({
          id: "g-athleteid-list",
          trainerId: TRAINER_BOOKER,
          athleteId: ["x"],
        })
      )
    );
  });

  it("DENIEGA un athleteId vacío", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "g-athleteid-vacio"),
        appointment({
          id: "g-athleteid-vacio",
          trainerId: TRAINER_BOOKER,
          athleteId: "",
        })
      )
    );
  });

  it("DENIEGA un athleteId de 200 caracteres — la cota de 128", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "g-athleteid-largo"),
        appointment({
          id: "g-athleteid-largo",
          trainerId: TRAINER_BOOKER,
          athleteId: "x".repeat(200),
        })
      )
    );
  });

  // ── trainerId: por el disyunto del atleta, que lo deja libre ────────────

  it("DENIEGA un trainerId que es una LISTA", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-trainerid-list"),
        appointment({ id: "g-trainerid-list", trainerId: ["x"] })
      )
    );
  });

  it("DENIEGA un trainerId de 200 caracteres — la cota de 128", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-trainerid-largo"),
        appointment({ id: "g-trainerid-largo", trainerId: "x".repeat(200) })
      )
    );
  });

  // ── athleteDisplayName ─────────────────────────────────────────────────

  it("DENIEGA un athleteDisplayName que es una LISTA VACÍA — mide 0 y cumple `<= 200`", async () => {
    // El campo es `required String` en el modelo: sin el `is string`, esta
    // fila rompe la deserialización del snapshot entero del PF.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-nombre-list"),
        appointment({ id: "g-nombre-list", athleteDisplayName: [] })
      )
    );
  });

  // ── id ─────────────────────────────────────────────────────────────────

  it("DENIEGA un id que es una LISTA — el `12` de antes no medía el gate", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-id-list"),
        appointment({ id: ["x"] })
      )
    );
  });

  it("DENIEGA un id vacío", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), COL, "g-id-vacio"), appointment({ id: "" }))
    );
  });

  // ── durationMin ────────────────────────────────────────────────────────

  it("DENIEGA un durationMin double — `60.5` está DENTRO del rango 1..600", async () => {
    // El negativo que ya existía usaba 100000, o sea medía `<= 600`. Este
    // valor pasa las dos cotas de rango: lo único que lo frena es el `is int`.
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-duration-double"),
        appointment({ id: "g-duration-double", durationMin: 60.5 })
      )
    );
  });

  it("DENIEGA un durationMin en cero — el borde inferior", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "g-duration-cero"),
        appointment({ id: "g-duration-cero", durationMin: 0 })
      )
    );
  });

  it("permite el turno legítimo con los mismos campos — ancla de no-vacuidad de los diez", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER_BOOKER), COL, "g-ancla"),
        appointment({
          id: "g-ancla",
          trainerId: TRAINER_BOOKER,
          athleteId: "atleta-cualquiera",
          athleteDisplayName: "Ana",
          durationMin: 60,
        })
      )
    );
  });
});
