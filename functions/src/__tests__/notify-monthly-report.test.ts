/** Unit tests for the monthly-report scheduler. No emulator or real FCM. */

jest.mock("firebase-admin", () => {
  class Timestamp {
    constructor(readonly date: Date) {}
    static fromDate(date: Date): Timestamp {
      return new Timestamp(date);
    }
    toDate(): Date {
      return this.date;
    }
  }
  const firestore = jest.fn();
  Object.assign(firestore, { Timestamp });
  return {
    firestore,
    app: jest.fn(),
    initializeApp: jest.fn(),
  };
});

jest.mock("../notifications/send-fcm", () => ({
  sendFcm: jest.fn(async () => ({ successCount: 1, failureCount: 0 })),
}));

import * as admin from "firebase-admin";
import { sendFcm } from "../notifications/send-fcm";
import {
  notifyMonthlyReportHandler,
  reportedMonthFor,
} from "../notifications/notify-monthly-report";

type SessionSeed = {
  uid: string;
  startedAt: Date;
  status?: string;
  wasFullyCompleted?: boolean;
};

type UserSeed = {
  role: "athlete" | "trainer";
  lastMonthlyReportNotifiedMonth?: string;
};

type FakeSessionDoc = {
  __index: number;
  data: () => Record<string, unknown>;
  ref: {
    path: string;
    parent: { parent: { id: string } };
  };
};

function installFirestore(
  sessions: SessionSeed[],
  users: Record<string, UserSeed>,
): void {
  const docs: FakeSessionDoc[] = sessions
    .sort((a, b) => a.startedAt.getTime() - b.startedAt.getTime())
    .map((session, index) => ({
      __index: index,
      data: () => ({
        startedAt: admin.firestore.Timestamp.fromDate(session.startedAt),
        status: session.status ?? "finished",
        wasFullyCompleted: session.wasFullyCompleted ?? true,
      }),
      ref: {
        path: `users/${session.uid}/sessions/session-${index}`,
        parent: { parent: { id: session.uid } },
      },
    }));

  const firestore = {
    collectionGroup: jest.fn(() => {
      let lower = Number.NEGATIVE_INFINITY;
      let upper = Number.POSITIVE_INFINITY;
      let offset = 0;
      let limit = 500;
      const query: Record<string, jest.Mock> = {};
      query.where = jest.fn((field: string, op: string, value: { toDate(): Date }) => {
        if (field !== "startedAt") throw new Error(`unexpected field ${field}`);
        if (op === ">=") lower = value.toDate().getTime();
        else if (op === "<") upper = value.toDate().getTime();
        else throw new Error(`unexpected operator ${op}`);
        return query;
      });
      query.orderBy = jest.fn(() => query);
      query.limit = jest.fn((size: number) => {
        limit = size;
        return query;
      });
      query.startAfter = jest.fn((cursor: FakeSessionDoc) => {
        offset = cursor.__index + 1;
        return query;
      });
      query.get = jest.fn(async () => {
        const matching = docs.filter((doc) => {
          const startedAt = (doc.data().startedAt as { toDate(): Date }).toDate().getTime();
          return startedAt >= lower && startedAt < upper;
        });
        const page = matching.filter((doc) => doc.__index >= offset).slice(0, limit);
        return { docs: page, size: page.length, empty: page.length === 0 };
      });
      return query;
    }),
    collection: jest.fn((name: string) => {
      if (name !== "users") throw new Error(`unexpected collection ${name}`);
      return {
        doc: (uid: string) => ({
          get: jest.fn(async () => ({
            exists: users[uid] !== undefined,
            data: () => users[uid],
          })),
          update: jest.fn(async (update: Partial<UserSeed>) => {
            if (!users[uid]) throw new Error(`missing user ${uid}`);
            Object.assign(users[uid], update);
          }),
        }),
      };
    }),
  };

  (admin.firestore as unknown as jest.Mock).mockReturnValue(firestore);
}

const app = {} as admin.app.App;
const messaging = {} as admin.messaging.Messaging;
const mockedSendFcm = sendFcm as jest.MockedFunction<typeof sendFcm>;

beforeEach(() => {
  jest.clearAllMocks();
  mockedSendFcm.mockResolvedValue({ successCount: 1, failureCount: 0 });
});

it("reports December of the previous year when execution is January 1 ART", () => {
  const month = reportedMonthFor(new Date("2027-01-01T13:00:00.000Z"));

  expect(month.key).toBe("2026-12");
  expect(month.name).toBe("diciembre");
  expect(month.start.toISOString()).toBe("2026-12-01T03:00:00.000Z");
  expect(month.endExclusive.toISOString()).toBe("2027-01-01T03:00:00.000Z");
});

it("does not notify an athlete without a qualifying session in the reported month", async () => {
  installFirestore(
    [
      { uid: "outside", startedAt: new Date("2026-07-31T23:00:00.000Z") },
      {
        uid: "abandoned",
        startedAt: new Date("2026-08-15T15:00:00.000Z"),
        wasFullyCompleted: false,
      },
    ],
    {
      outside: { role: "athlete" },
      abandoned: { role: "athlete" },
    },
  );

  const result = await notifyMonthlyReportHandler(
    app,
    new Date("2026-09-01T13:00:00.000Z"),
    messaging,
  );

  expect(result.notified).toBe(0);
  expect(result.eligibleAthletes).toBe(0);
  expect(mockedSendFcm).not.toHaveBeenCalled();
});

it("does not resend on a second run for the same reported month", async () => {
  const users: Record<string, UserSeed> = { athlete: { role: "athlete" } };
  installFirestore(
    [{ uid: "athlete", startedAt: new Date("2026-08-15T15:00:00.000Z") }],
    users,
  );
  const now = new Date("2026-09-01T13:00:00.000Z");

  await notifyMonthlyReportHandler(app, now, messaging);
  const second = await notifyMonthlyReportHandler(app, now, messaging);

  expect(mockedSendFcm).toHaveBeenCalledTimes(1);
  expect(second.notified).toBe(0);
  expect(second.skipped).toBe(1);
  expect(users.athlete.lastMonthlyReportNotifiedMonth).toBe("2026-08");
});

it("sends the exact Flutter deep link with the reported month", async () => {
  installFirestore(
    [{ uid: "athlete", startedAt: new Date("2026-08-31T23:59:00.000Z") }],
    { athlete: { role: "athlete" } },
  );

  await notifyMonthlyReportHandler(
    app,
    new Date("2026-09-01T13:00:00.000Z"),
    messaging,
  );

  expect(mockedSendFcm).toHaveBeenCalledWith(
    app,
    expect.objectContaining({
      kind: "monthly-report",
      notification: {
        title: "Tu reporte de agosto está listo",
        body: "Mirá cuánto entrenaste, tu volumen y tu distribución muscular del mes.",
      },
      data: { deepLink: "/home/insights/monthly?month=2026-08" },
    }),
    messaging,
  );
});

it("paginates the collectionGroup query", async () => {
  const sessions = Array.from({ length: 500 }, (_, index) => ({
    uid: `abandoned-${index}`,
    startedAt: new Date(`2026-08-${String((index % 28) + 1).padStart(2, "0")}T12:00:00.000Z`),
    wasFullyCompleted: false,
  }));
  sessions.push({
    uid: "athlete-page-two",
    startedAt: new Date("2026-08-31T20:00:00.000Z"),
    wasFullyCompleted: true,
  });
  installFirestore(sessions, { "athlete-page-two": { role: "athlete" } });

  const result = await notifyMonthlyReportHandler(
    app,
    new Date("2026-09-01T13:00:00.000Z"),
    messaging,
  );

  expect(result.scannedSessions).toBe(501);
  expect(result.notified).toBe(1);
});
