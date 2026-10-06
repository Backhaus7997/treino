/**
 * Los pasos de DATOS de la cascada de borrado de cuenta (Firestore + Storage).
 *
 * Salen de `runDeleteAccount` para que los corra tambien el reintento de los
 * borrados `partial` (`retention/retry-partial-deletions.ts`, #1353). Quedan
 * FUERA de aca, a proposito: la baja de Mercado Pago (fail-closed, va primero y
 * una sola vez), el audit log y la baja de Auth (va ultima). Un reintento no
 * debe cobrarle nada a nadie ni volver a tocar la identidad.
 *
 * Cada paso va en su propio try/catch: uno que falla no frena a los demas, y
 * su error se acumula como `<paso>: <mensaje>`. Todos son idempotentes (ver los
 * headers de cada modulo), asi que correrlos de nuevo sobre un uid ya borrado
 * es un no-op, y sobre uno a medio borrar termina el trabajo.
 *
 * El orden es el que tenia `runDeleteAccount`; los docs del usuario van al
 * final de los datos para que un reintento siga encontrando sus colgantes.
 */

import { App } from "firebase-admin/app";
import { sweepFollows } from "./friendships";
import { deletePosts } from "./posts";
import { terminateTrainerLinks } from "./trainer-links";
import { cancelFutureAppointments } from "./appointments";
import {
  deleteAvatar,
  deleteAthleteStorage,
  deleteTrainerStorage,
} from "./storage";
import {
  cancelFutureAppointmentsAsTrainer,
  deleteTrainerOwnedData,
  deleteTrainerTemplates,
  terminateLinksAsTrainer,
} from "./trainer-data";
import { deleteAthleteOwnedData } from "./athlete-data";
import { deleteAthleteRoutines } from "./routines";
import { deleteUserDocs } from "./users";

export interface DataCascadeResult {
  deletedCollections: string[];
  errors: string[];
}

interface Step {
  /** Prefijo del error en `errors[]` y etiqueta en `deletedCollections`. */
  label: string;
  run: (app: App, uid: string) => Promise<unknown>;
  /** Etiquetas extra cuando el paso sale bien (users -> + userPublicProfiles). */
  alsoDeleted?: string[];
}

const STEPS: Step[] = [
  { label: "follows", run: (a, u) => sweepFollows(a, u) },
  { label: "posts", run: (a, u) => deletePosts(a, u) },
  // Como atleta: vinculos propios.
  { label: "trainer_links", run: (a, u) => terminateTrainerLinks(a, u) },
  // T1: vinculos donde este uid es el PF. Motivo `trainer-account-deleted`.
  { label: "trainer-links", run: (a, u) => terminateLinksAsTrainer(a, u) },
  { label: "appointments", run: (a, u) => cancelFutureAppointments(a, u) },
  // T2: turnos futuros + disponibilidad del PF.
  {
    label: "trainer-appointments",
    run: (a, u) => cancelFutureAppointmentsAsTrainer(a, u),
  },
  // Admin SDK saltea las reglas de Storage (ADR-ACCDEL-013).
  { label: "storage", run: (a, u) => deleteAvatar(a, u) },
  // chatMedia / customExerciseVideos / temp / athleteFiles (QA-CMP-002).
  { label: "storage-athlete", run: (a, u) => deleteAthleteStorage(a, u) },
  // T3: archivos que el PF escribio para sus alumnos.
  { label: "trainer-storage", run: (a, u) => deleteTrainerStorage(a, u) },
  // measurements, performance_tests, shares, billing, notas... (QA-CMP-003).
  { label: "athlete-data", run: (a, u) => deleteAthleteOwnedData(a, u) },
  // T4: lo que el PF escribio sobre sus alumnos. `payments` se RETIENE (fiscal).
  { label: "trainer-data", run: (a, u) => deleteTrainerOwnedData(a, u) },
  // Rutinas del atleta, `ratings` incluido (QA-CMP-004).
  { label: "routines", run: (a, u) => deleteAthleteRoutines(a, u) },
  // T5: plantillas del PF, publicadas incluidas.
  { label: "trainer-templates", run: (a, u) => deleteTrainerTemplates(a, u) },
  {
    label: "users",
    run: (a, u) => deleteUserDocs(a, u),
    alsoDeleted: ["userPublicProfiles"],
  },
];

export async function runDataCascade(
  app: App,
  uid: string
): Promise<DataCascadeResult> {
  const deletedCollections: string[] = [];
  const errors: string[] = [];
  for (const step of STEPS) {
    try {
      await step.run(app, uid);
      deletedCollections.push(step.label, ...(step.alsoDeleted ?? []));
    } catch (err: unknown) {
      errors.push(`${step.label}: ${(err as Error).message ?? String(err)}`);
    }
  }
  return { deletedCollections, errors };
}
