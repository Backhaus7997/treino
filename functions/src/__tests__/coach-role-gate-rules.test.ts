/**
 * QA-SEC-013 (#780) — el gate de rol `trainer` no había llegado a las tres
 * colecciones que publican la identidad y la agenda del PF.
 *
 * `rules-hardening` Slice C (AD-1 opción b) puso
 * `get(users/{uid}).data.role == 'trainer'` en cinco colecciones y dejó afuera
 * `trainerPublicProfiles`, `coach_availability_rules` y
 * `coach_availability_overrides`. Medido contra el emulador: una cuenta
 * `role: 'athlete'` se publicaba en el directorio de PFs **y volvía primero**
 * en la query de descubrimiento, porque el atacante elige el
 * `displayNameLowercase` por el que se ordena. Ver `docs/security.md` §4.9.
 *
 * Es un hueco de INTEGRIDAD, no de confidencialidad: no filtra datos de
 * terceros. Ensucia el directorio comercial y dejaba una colección
 * mundo-legible abierta a documentos arbitrarios de hasta 1 MB.
 *
 * ⚠️ Los `users/{uid}` se seedean con `withSecurityRulesDisabled` A PROPÓSITO.
 * Las reglas nuevas hacen `get(users/{uid})`, y sobre un doc inexistente la
 * evaluación **falla** — o sea que un `assertFails` sin seed pasaría por el
 * motivo equivocado (doc ausente, no rol incorrecto), que es lo que
 * `docs/security.md` §1.8 prohíbe. Con los dos usuarios existiendo y
 * difiriendo SÓLO en `role`, el único motivo posible de la diferencia es el
 * gate.
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

const PROJECT_ID = "treino-rules-test-sec013";
const RULES_PATH = path.resolve(__dirname, "../../../firestore.rules");

const TRAINER = "trainer-uid";
const ATHLETE = "athlete-uid";

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
  // Ver la nota ⚠️ del encabezado. Los dos docs son idénticos salvo `role`.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", TRAINER), { uid: TRAINER, role: "trainer" });
    await setDoc(doc(db, "users", ATHLETE), { uid: ATHLETE, role: "athlete" });
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

function dbAs(uid: string) {
  return testEnv.authenticatedContext(uid).firestore();
}

/** Perfil comercial mínimo, con el `displayNameLowercase` que ordena el directorio. */
function trainerProfile(uid: string): Record<string, unknown> {
  return {
    uid,
    displayName: "Juan Pérez",
    displayNameLowercase: "aaa juan perez",
    trainerSpecialty: "Fuerza",
    trainerOffersOnline: true,
  };
}

/** Regla semanal válida — forma exacta de `AvailabilityRule.toJson()`. */
function availabilityRule(
  id: string,
  trainerId: string,
  overrides: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    id,
    trainerId,
    dayOfWeek: 1,
    startHour: 9,
    startMinute: 0,
    endHour: 11,
    endMinute: 0,
    slotDurationMin: 60,
    ...overrides,
  };
}

describe("trainerPublicProfiles — gate de rol (QA-SEC-013)", () => {
  it("permite al trainer publicarse en el directorio", async () => {
    await assertSucceeds(
      setDoc(doc(dbAs(TRAINER), "trainerPublicProfiles", TRAINER), trainerProfile(TRAINER))
    );
  });

  it("DENIEGA que un athlete se publique en el directorio", async () => {
    // El vector del ticket: es dueño de su propio doc, pero no es PF.
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), "trainerPublicProfiles", ATHLETE), trainerProfile(ATHLETE))
    );
  });

  it("DENIEGA publicarse en el doc de OTRO uid", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), "trainerPublicProfiles", TRAINER), trainerProfile(TRAINER))
    );
  });

  it("DENIEGA que un athlete edite un perfil forjado antes del gate", async () => {
    // Sin el gate en `update`, cerrar sólo `create` dejaría vivo —y editable
    // para siempre— todo lo que ya se coló.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "trainerPublicProfiles", ATHLETE),
        trainerProfile(ATHLETE)
      );
    });
    await assertFails(
      updateDoc(doc(dbAs(ATHLETE), "trainerPublicProfiles", ATHLETE), {
        trainerSpecialty: "Hipertrofia",
      })
    );
  });

  it("permite al trainer editar su propio perfil", async () => {
    // El positivo que distingue "deniega por rol" de "deniega siempre". Sin
    // él, romper el update entero pasaría inadvertido.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), "trainerPublicProfiles", TRAINER),
        trainerProfile(TRAINER)
      );
    });
    await assertSucceeds(
      updateDoc(doc(dbAs(TRAINER), "trainerPublicProfiles", TRAINER), {
        trainerSpecialty: "Hipertrofia",
      })
    );
  });
});

describe("coach_availability_rules — gate de rol y forma (QA-SEC-013)", () => {
  it("permite al trainer publicar una regla válida", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "r1"),
        availabilityRule("r1", TRAINER)
      )
    );
  });

  it("acepta domingo (dayOfWeek 7) — el rango es 1..7, no 0..6", async () => {
    // Regresión del rango: `DateTime.monday` es 1 y `sunday` es 7. Un
    // `dayOfWeek >= 0 && <= 6` habría denegado en silencio TODAS las reglas
    // de domingo. Este caso es el que se pone rojo si alguien "corrige" el
    // rango a 0..6.
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "r-dom"),
        availabilityRule("r-dom", TRAINER, { dayOfWeek: 7 })
      )
    );
  });

  it("DENIEGA que un athlete publique agenda", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), "coach_availability_rules", "r2"),
        availabilityRule("r2", ATHLETE)
      )
    );
  });

  it("DENIEGA campos fuera de la forma — el vector de basura arbitraria", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "r3"),
        availabilityRule("r3", TRAINER, { basura: "x".repeat(50000) })
      )
    );
  });

  it("DENIEGA un dayOfWeek fuera de rango", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "r4"),
        availabilityRule("r4", TRAINER, { dayOfWeek: 0 })
      )
    );
  });

  it("DENIEGA un slotDurationMin fuera de la allowlist", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "r5"),
        availabilityRule("r5", TRAINER, { slotDurationMin: 45 })
      )
    );
  });

  it("DENIEGA una regla incompleta", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_rules", "r6"), {
        id: "r6",
        trainerId: TRAINER,
        dayOfWeek: 1,
      })
    );
  });

  it("DENIEGA publicar agenda a nombre de OTRO trainer", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), "coach_availability_rules", "r7"),
        availabilityRule("r7", TRAINER)
      )
    );
  });
});

describe("coach_availability_overrides — unión sellada (QA-SEC-013)", () => {
  const date = Timestamp.fromDate(new Date("2026-09-01T00:00:00Z"));

  it("permite la variante `block` — 4 campos, sin los de horario", async () => {
    // El caso que se rompe si alguien escribe un solo `hasAll` con los 9
    // campos de `extra`: se caerían todos los días bloqueados, que son la
    // mitad de la feature.
    await assertSucceeds(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o1"), {
        id: "o1",
        trainerId: TRAINER,
        date,
        type: "block",
      })
    );
  });

  it("permite la variante `extra` — 9 campos", async () => {
    await assertSucceeds(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o2"), {
        id: "o2",
        trainerId: TRAINER,
        date,
        type: "extra",
        startHour: 14,
        startMinute: 30,
        endHour: 16,
        endMinute: 0,
        slotDurationMin: 30,
      })
    );
  });

  it("DENIEGA un `block` con campos de horario colgados", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o3"), {
        id: "o3",
        trainerId: TRAINER,
        date,
        type: "block",
        startHour: 14,
      })
    );
  });

  it("DENIEGA un `extra` al que le faltan los horarios", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o4"), {
        id: "o4",
        trainerId: TRAINER,
        date,
        type: "extra",
      })
    );
  });

  it("DENIEGA un `type` desconocido", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o5"), {
        id: "o5",
        trainerId: TRAINER,
        date,
        type: "otro",
      })
    );
  });

  it("DENIEGA que un athlete publique overrides", async () => {
    await assertFails(
      setDoc(doc(dbAs(ATHLETE), "coach_availability_overrides", "o6"), {
        id: "o6",
        trainerId: ATHLETE,
        date,
        type: "block",
      })
    );
  });

  it("DENIEGA basura arbitraria aunque el type sea válido", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "o7"), {
        id: "o7",
        trainerId: TRAINER,
        date,
        type: "block",
        basura: "x".repeat(50000),
      })
    );
  });
});

// El `update` de las dos colecciones de agenda también cambió —ahora valida
// forma— así que necesita sus propias celdas. Sin estos casos, la fila de
// §1.1 diría ✅ en `update` apoyándose en tests que sólo ejercitan `create`,
// que es exactamente la celda mentida que §1.8 prohíbe.
describe("coach_availability_* — update valida forma (QA-SEC-013)", () => {
  const date = Timestamp.fromDate(new Date("2026-09-01T00:00:00Z"));

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(
        doc(db, "coach_availability_rules", "u1"),
        availabilityRule("u1", TRAINER)
      );
      await setDoc(doc(db, "coach_availability_overrides", "u2"), {
        id: "u2",
        trainerId: TRAINER,
        date,
        type: "block",
      });
    });
  });

  it("permite al trainer editar su propia regla con forma válida", async () => {
    await assertSucceeds(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "u1"),
        availabilityRule("u1", TRAINER, { startHour: 10 })
      )
    );
  });

  it("DENIEGA meter basura por el update de una regla", async () => {
    // El `create` acotado no sirve de nada si el `update` deja colar lo mismo
    // un segundo después.
    await assertFails(
      setDoc(
        doc(dbAs(TRAINER), "coach_availability_rules", "u1"),
        availabilityRule("u1", TRAINER, { basura: "x".repeat(50000) })
      )
    );
  });

  it("permite al trainer editar su propio override", async () => {
    await assertSucceeds(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "u2"), {
        id: "u2",
        trainerId: TRAINER,
        date: Timestamp.fromDate(new Date("2026-09-02T00:00:00Z")),
        type: "block",
      })
    );
  });

  it("DENIEGA meter basura por el update de un override", async () => {
    await assertFails(
      setDoc(doc(dbAs(TRAINER), "coach_availability_overrides", "u2"), {
        id: "u2",
        trainerId: TRAINER,
        date,
        type: "block",
        basura: "x".repeat(50000),
      })
    );
  });

  it("DENIEGA que un tercero edite la agenda ajena", async () => {
    await assertFails(
      setDoc(
        doc(dbAs(ATHLETE), "coach_availability_rules", "u1"),
        availabilityRule("u1", ATHLETE)
      )
    );
  });
});
