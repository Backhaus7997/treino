jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
}));

jest.mock("firebase-functions", () => ({
  logger: { error: jest.fn() },
}));

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { purgeRejectedLinkHandler } from "../purge-rejected-link";

const APP = {} as admin.app.App;

function installFirestore({ deleteError }: { deleteError?: Error } = {}) {
  const deleteDoc = jest.fn(async () => {
    if (deleteError) throw deleteError;
  });
  const doc = jest.fn(() => ({ delete: deleteDoc }));
  const collection = jest.fn(() => ({ doc }));
  (admin.firestore as unknown as jest.Mock).mockReturnValue({ collection });
  return { collection, doc, deleteDoc };
}

beforeEach(() => {
  jest.clearAllMocks();
});

describe("purgeRejectedLinkHandler", () => {
  it("borra un link terminated que nunca fue aceptado", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-rejected", {
        status: "terminated",
        acceptedAt: null,
      }),
    ).resolves.toBe(true);

    expect(firestore.collection).toHaveBeenCalledWith("trainer_links");
    expect(firestore.doc).toHaveBeenCalledWith("link-rejected");
    expect(firestore.deleteDoc).toHaveBeenCalledTimes(1);
  });

  it("conserva un vínculo real terminated con acceptedAt", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-real", {
        status: "terminated",
        acceptedAt: { seconds: 1 },
      }),
    ).resolves.toBe(false);

    expect(firestore.deleteDoc).not.toHaveBeenCalled();
  });

  it("conserva un link cuyo status no es terminated", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-pending", {
        status: "pending",
        acceptedAt: null,
      }),
    ).resolves.toBe(false);

    expect(firestore.deleteDoc).not.toHaveBeenCalled();
  });

  it("no lanza y devuelve false cuando Firestore falla", async () => {
    const error = new Error("Firestore caído");
    installFirestore({ deleteError: error });

    await expect(
      purgeRejectedLinkHandler(APP, "link-failed", {
        status: "terminated",
      }),
    ).resolves.toBe(false);

    expect(logger.error).toHaveBeenCalledWith(
      "purgeRejectedLink: no se pudo borrar el rechazo",
      { linkId: "link-failed", error },
    );
  });
});
