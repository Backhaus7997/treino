jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
}));

jest.mock("firebase-functions", () => ({
  logger: { error: jest.fn(), info: jest.fn(), warn: jest.fn() },
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
        terminationReason: "declined",
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
        terminationReason: "declined",
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
        terminationReason: "declined",
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
        terminationReason: "declined",
      }),
    ).resolves.toBe(false);

    expect(logger.error).toHaveBeenCalledWith(
      "purgeRejectedLink: no se pudo borrar el rechazo",
      { linkId: "link-failed", error },
    );
  });

  // ── EL CASO QUE FALTABA ────────────────────────────────────────────────
  //
  // Estos cuatro son el hallazgo #1 de la revisión. `acceptedAt == null` NO
  // alcanza como criterio de borrado, por dos razones independientes:
  //
  //  1. `promote-link.ts` NO estampa `acceptedAt` en la rama resume, y
  //     `firestore.rules:781` deja al PF poner `paused` desde CUALQUIER
  //     status —incluido `pending`—. O sea que pending → paused → resume da
  //     un vínculo ACTIVO sin la marca, con data completamente nueva.
  //  2. `select-blocked-links.ts:192` llama «un DEFECTO DE DATOS» a un
  //     vínculo sin `acceptedAt`: los legacy también existen.
  //
  // Después, cualquier `terminate` sobre ese vínculo lo dejaría borrable. De
  // esos docs cuelgan reviews (`reviews/{linkId}_{athleteId}`) y el `linkId`
  // estampado en `chats`, y `firestore.rules:811` es `allow delete: if false`
  // — nada los repone.
  //
  // El criterio tiene que ser el MISMO que el de
  // `scripts/cleanup_rejected_links.js`: las dos razones que sólo se escriben
  // sobre un `pending`, que son las únicas que garantizan que nunca hubo
  // vínculo.
  it.each([
    ["athlete-terminated"],
    ["trainer-terminated"],
    ["switched_trainer"],
    ["Alta voluntaria del atleta"],
  ])(
    "CONSERVA un terminate real sin acceptedAt (reason=%s)",
    async (reason) => {
      const firestore = installFirestore();

      await expect(
        purgeRejectedLinkHandler(APP, "link-real-sin-stamp", {
          status: "terminated",
          acceptedAt: null,
          terminationReason: reason,
        }),
      ).resolves.toBe(false);

      expect(firestore.deleteDoc).not.toHaveBeenCalled();
    },
  );

  it("CONSERVA un terminated sin razón alguna", async () => {
    // Sin `terminationReason` no se puede afirmar que nunca hubo vínculo.
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-sin-razon", {
        status: "terminated",
        acceptedAt: null,
      }),
    ).resolves.toBe(false);

    expect(firestore.deleteDoc).not.toHaveBeenCalled();
  });

  it("borra una cancelación del alumno", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-cancelado", {
        status: "terminated",
        acceptedAt: null,
        terminationReason: "cancelled-by-athlete",
      }),
    ).resolves.toBe(true);

    expect(firestore.deleteDoc).toHaveBeenCalledTimes(1);
  });

  it("una razón que no es string no rompe ni borra", async () => {
    const firestore = installFirestore();

    for (const basura of [42, {}, [], true, null]) {
      await expect(
        purgeRejectedLinkHandler(APP, "link-basura", {
          status: "terminated",
          acceptedAt: null,
          terminationReason: basura,
        }),
      ).resolves.toBe(false);
    }

    expect(firestore.deleteDoc).not.toHaveBeenCalled();
  });
});
