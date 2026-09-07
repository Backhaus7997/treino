/**
 * El ORDEN entre la notificación de rechazo y el borrado del vínculo.
 *
 * Unit test con mocks — LOCAL, sin emulador. La suite de integración de
 * `notifyOnLinkChange` (`notify-link-change.test.ts`) corre contra Firestore
 * emulado y cubre el contenido de los pushes; esto cubre algo que un test de
 * integración NO puede afirmar: la SECUENCIA de efectos, y que un purge que
 * explota no se lleva puesta la notificación.
 *
 * POR QUÉ IMPORTA. El borrado del rechazo (purge-rejected-link.ts) vive al final
 * de `notifyOnLinkChangeHandler` justamente para que el orden sea una propiedad
 * del código. Si mañana alguien lo mueve a un trigger propio sobre
 * `trainer_links/{linkId}`, el orden pasa a depender de cómo Eventarc planifique
 * dos invocaciones independientes — y este test no lo notaría, así que lo dice
 * acá: la garantía es "está en el mismo handler, y último".
 */

const calls: string[] = [];

jest.mock("../notifications/send-fcm", () => ({
  sendFcm: jest.fn(async () => {
    calls.push("sendFcm");
    return { successCount: 1, failureCount: 0 };
  }),
}));

jest.mock("../mail/enqueue-mail", () => ({
  enqueueMail: jest.fn(async () => {
    calls.push("enqueueMail");
  }),
}));

jest.mock("../mail/format", () => ({
  resolveAthleteName: jest.fn(async () => "Ana"),
  resolveTrainerName: jest.fn(async () => "Beto"),
}));

jest.mock("../purge-rejected-link", () => ({
  purgeRejectedLinkHandler: jest.fn(async () => {
    calls.push("purge");
    return true;
  }),
}));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import * as admin from "firebase-admin";
import { sendFcm } from "../notifications/send-fcm";
import { purgeRejectedLinkHandler } from "../purge-rejected-link";
import { notifyOnLinkChangeHandler } from "../notifications/notify-link-change";

const APP = {} as admin.app.App;

const TRAINER = "trainer-A";
const ATHLETE = "athlete-X";

/** Un rechazo del PF: `pending` → `terminated`, sin `acceptedAt`. */
function rechazo(): Record<string, unknown> {
  return {
    trainerId: TRAINER,
    athleteId: ATHLETE,
    status: "terminated",
    terminationReason: "declined",
  };
}

beforeEach(() => {
  calls.length = 0;
  jest.clearAllMocks();
});

describe("notifyOnLinkChange — orden del purge", () => {
  it("notifica PRIMERO y borra DESPUÉS", async () => {
    await notifyOnLinkChangeHandler(
      APP,
      "link-1",
      { trainerId: TRAINER, athleteId: ATHLETE, status: "pending" },
      rechazo(),
    );

    expect(calls).toEqual(["sendFcm", "purge"]);
  });

  it("el purge recibe el linkId y el snapshot `after`", async () => {
    const after = rechazo();

    await notifyOnLinkChangeHandler(
      APP,
      "link-1",
      { trainerId: TRAINER, athleteId: ATHLETE, status: "pending" },
      after,
    );

    expect(purgeRejectedLinkHandler).toHaveBeenCalledWith(APP, "link-1", after);
  });

  it("un purge que falla NO impide la notificación", async () => {
    // El handler real nunca lanza — devuelve false y loguea. Este test pinea que
    // el llamador tampoco depende de eso: si un día empezara a propagar, un
    // reintento de la CF duplicaría el push Y su fila en
    // `users/{uid}/notifications`.
    (purgeRejectedLinkHandler as jest.Mock).mockResolvedValueOnce(false);

    await notifyOnLinkChangeHandler(
      APP,
      "link-1",
      { trainerId: TRAINER, athleteId: ATHLETE, status: "pending" },
      rechazo(),
    );

    expect(sendFcm).toHaveBeenCalledTimes(1);
  });

  it("no borra nada cuando el vínculo se acepta (pending → active)", async () => {
    await notifyOnLinkChangeHandler(
      APP,
      "link-1",
      { trainerId: TRAINER, athleteId: ATHLETE, status: "pending" },
      {
        trainerId: TRAINER,
        athleteId: ATHLETE,
        status: "active",
        acceptedAt: { __ts: 1 },
      },
    );

    // El handler del purge se llama igual —el filtro vive adentro, no acá— pero
    // con un `after` que NO califica. Lo que se pinea es que el snapshot que le
    // llega es el de un vínculo aceptado.
    expect(purgeRejectedLinkHandler).toHaveBeenCalledWith(
      APP,
      "link-1",
      expect.objectContaining({ status: "active" }),
    );
  });

  it("la cascada de borrado de cuenta corta antes: ni push ni purge", async () => {
    await notifyOnLinkChangeHandler(
      APP,
      "link-1",
      { trainerId: TRAINER, athleteId: ATHLETE, status: "active" },
      { ...rechazo(), reason: "account-deleted" },
    );

    expect(calls).toEqual([]);
    expect(purgeRejectedLinkHandler).not.toHaveBeenCalled();
  });

  it("un delete (after ausente) corta antes: no se re-dispara el purge", async () => {
    // El propio borrado del purge vuelve a disparar este trigger. Sin este
    // corte habría un bucle.
    await notifyOnLinkChangeHandler(APP, "link-1", rechazo(), undefined);

    expect(calls).toEqual([]);
    expect(purgeRejectedLinkHandler).not.toHaveBeenCalled();
  });
});
