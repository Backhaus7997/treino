/**
 * notifyMonthlyReport — avisa que el reporte del mes cerrado ya está listo.
 *
 * Corre el día 1 a las 10:00 ART: el mes ya cerró a las 00:00 y el push llega
 * en un horario razonable. Una única collectionGroup query paginada encuentra
 * las sesiones del mes; filtrar status/wasFullyCompleted en memoria evita un
 * índice compuesto y, sobre todo, evita una query por cada usuario.
 *
 * Sólo se notifican atletas con al menos una sesión realmente completada. El
 * marcador `lastMonthlyReportNotifiedMonth` guarda el mes REPORTADO (YYYY-MM),
 * por lo que los reintentos secuenciales del scheduler no vuelven a enviar.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { artDateKey } from "../mail/format";
import { sendFcm } from "./send-fcm";

const PAGE_SIZE = 500;
const MONTH_NAMES_ES_AR = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
] as const;

function getApp(): admin.app.App {
  try {
    return admin.app();
  } catch {
    return admin.initializeApp();
  }
}

export interface ReportedMonth {
  key: string;
  name: string;
  start: Date;
  endExclusive: Date;
}

export interface NotifyMonthlyReportResult {
  notified: number;
  skipped: number;
  failed: number;
  scannedSessions: number;
  eligibleAthletes: number;
  reportedMonth: string;
}

/** Resolves the previous calendar month and its exact ART boundaries. */
export function reportedMonthFor(now: Date): ReportedMonth {
  const [yearText, monthText] = artDateKey(now).split("-");
  const executionYear = Number(yearText);
  const executionMonthIndex = Number(monthText) - 1;
  const reportedMonthIndex = executionMonthIndex === 0
    ? 11
    : executionMonthIndex - 1;
  const reportedYear = executionMonthIndex === 0
    ? executionYear - 1
    : executionYear;
  const nextMonthIndex = (reportedMonthIndex + 1) % 12;
  const nextMonthYear = reportedMonthIndex === 11
    ? reportedYear + 1
    : reportedYear;

  // Argentina is UTC-03 and has had no DST since 2009. 03:00Z is therefore
  // exactly 00:00 ART; using UTC midnight would leak the previous ART day.
  const start = new Date(Date.UTC(reportedYear, reportedMonthIndex, 1, 3));
  const endExclusive = new Date(Date.UTC(nextMonthYear, nextMonthIndex, 1, 3));
  const key = `${reportedYear}-${String(reportedMonthIndex + 1).padStart(2, "0")}`;

  return { key, name: MONTH_NAMES_ES_AR[reportedMonthIndex], start, endExclusive };
}

/** Handler with clock and Messaging injected so tests never call real FCM. */
export async function notifyMonthlyReportHandler(
  app: admin.app.App,
  now: Date,
  messaging?: admin.messaging.Messaging,
): Promise<NotifyMonthlyReportResult> {
  const db = admin.firestore(app);
  const month = reportedMonthFor(now);
  const athleteUids = new Set<string>();
  let scannedSessions = 0;
  let cursor: admin.firestore.QueryDocumentSnapshot | undefined;

  do {
    let query: admin.firestore.Query = db
      .collectionGroup("sessions")
      .where("startedAt", ">=", admin.firestore.Timestamp.fromDate(month.start))
      .where(
        "startedAt",
        "<",
        admin.firestore.Timestamp.fromDate(month.endExclusive),
      )
      .orderBy("startedAt", "asc")
      .limit(PAGE_SIZE);

    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();

    for (const sessionDoc of page.docs) {
      scannedSessions++;
      const data = sessionDoc.data();
      if (data.status !== "finished" || data.wasFullyCompleted !== true) continue;

      const uid = sessionDoc.ref.parent.parent?.id;
      if (uid) athleteUids.add(uid);
      else {
        logger.warn("notifyMonthlyReport: session has no user parent", {
          sessionPath: sessionDoc.ref.path,
        });
      }
    }

    cursor = page.size === PAGE_SIZE ? page.docs[page.docs.length - 1] : undefined;
  } while (cursor);

  let notified = 0;
  let skipped = 0;
  let failed = 0;

  for (const uid of athleteUids) {
    try {
      const userRef = db.collection("users").doc(uid);
      const userSnap = await userRef.get();
      const user = userSnap.data();

      if (!userSnap.exists || user?.role !== "athlete") {
        skipped++;
        logger.info("notifyMonthlyReport: session owner is not an athlete — skipping", { uid });
        continue;
      }
      if (user.lastMonthlyReportNotifiedMonth === month.key) {
        skipped++;
        continue;
      }

      await sendFcm(
        app,
        {
          uids: [uid],
          kind: "monthly-report",
          notification: {
            title: `Tu reporte de ${month.name} está listo`,
            body: "Mirá cuánto entrenaste, tu volumen y tu distribución muscular del mes.",
          },
          data: {
            deepLink: `/home/insights/monthly?month=${month.key}`,
          },
        },
        messaging,
      );

      await userRef.update({ lastMonthlyReportNotifiedMonth: month.key });
      notified++;
    } catch (error: unknown) {
      failed++;
      logger.error("notifyMonthlyReport: failed for athlete", { uid, error });
    }
  }

  const result = {
    notified,
    skipped,
    failed,
    scannedSessions,
    eligibleAthletes: athleteUids.size,
    reportedMonth: month.key,
  };
  logger.info("notifyMonthlyReport: run complete", result);
  return result;
}

/** Runs monthly at 10:00 ART, in the same region as the other TREINO CFs. */
export const notifyMonthlyReport = onSchedule(
  {
    schedule: "0 10 1 * *",
    timeZone: "America/Argentina/Buenos_Aires",
    region: "southamerica-east1",
  },
  async () => {
    const result = await notifyMonthlyReportHandler(getApp(), new Date());
    logger.info("notifyMonthlyReport: scheduled run done", result);
  },
);
