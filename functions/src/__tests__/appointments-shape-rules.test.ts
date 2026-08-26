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

const ATHLETE = "athlete-uid";
const TRAINER = "trainer-uid";
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

  it("acepta un turno dentro de las próximas horas — el rango tolera el wall-clock", async () => {
    // ADR-7: `startsAt` es wall-clock, no instante real. Este caso se pone
    // rojo si alguien endurece el rango a `> request.time`, que denegaría
    // toda reserva cercana en cualquier zona al oeste de UTC.
    await assertSucceeds(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-soon"),
        appointment({ id: "appt-soon", startsAt: Timestamp.fromMillis(Date.now() + 3600000) })
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

  it("DENIEGA un turno absurdamente lejano en el futuro", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), COL, "appt-6"),
        appointment({ id: "appt-6", startsAt: inDays(400) })
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

  it("DENIEGA engordar el turno por el update", async () => {
    // Sin cota en el update, el cap del create se esquiva creando un turno
    // chico y engordándolo un segundo después.
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), {
        noteBefore: "x".repeat(30000),
      })
    );
  });

  it("DENIEGA agregar claves nuevas por el update", async () => {
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), {
        basura: "x".repeat(30000),
      })
    );
  });

  it("permite al miembro cancelar con más de 24 h", async () => {
    // Ancla de no-vacuidad del Path 1: la cota de forma no puede romper la
    // cancelación, que es el único camino de salida que tiene un turno.
    await assertSucceeds(
      updateDoc(doc(dbAs(ATHLETE), COL, "appt-u"), { status: "cancelled" })
    );
  });
});
