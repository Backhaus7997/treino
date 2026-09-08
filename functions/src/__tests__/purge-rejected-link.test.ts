jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
}));

// La puerta MODULAR tiene que dar el MISMO doble que la namespaced de arriba.
// Sin esto, producción —que importa `getFirestore` de `firebase-admin/firestore`—
// se lleva el SDK REAL por la puerta de al lado, y esta suite NO se pone roja:
// sale verde, porque el handler tiene catch-all y varias aserciones prueban por
// AUSENCIA (`deleteDoc` no llamado). Lo caza `firebase-admin-mock-surface.test.ts`,
// que es el trinquete de esta migración.
jest.mock("firebase-admin/app", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).app());

jest.mock("firebase-admin/firestore", () => (
    jest.requireActual("./helpers/modular-from-namespaced") as Record<
      string,
      () => unknown
    >
).firestoreDesdeNamespaced());

jest.mock("firebase-functions", () => ({
  logger: { error: jest.fn(), info: jest.fn(), warn: jest.fn() },
}));

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import {
  clasificarTerminacion,
  purgeRejectedLinkHandler,
} from "../purge-rejected-link";

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

// ─── clasificarTerminacion ──────────────────────────────────────────────────
//
// La ÚNICA respuesta a «¿qué fue este `terminated`?». La consumen dos lugares
// —a quién se notifica, y si el doc se borra— y ése es exactamente el punto:
// mientras fueron dos predicados separados divergieron, y el que decidía el
// borrado era el más flojo de los dos.
describe("clasificarTerminacion", () => {
  it("declined sin acceptedAt → rechazo", () => {
    expect(
      clasificarTerminacion({ acceptedAt: null, terminationReason: "declined" }),
    ).toBe("rechazo");
  });

  it("cancelled-by-athlete sin acceptedAt → cancelacion", () => {
    expect(
      clasificarTerminacion({ terminationReason: "cancelled-by-athlete" }),
    ).toBe("cancelacion");
  });

  it.each([
    ["athlete-terminated"],
    ["trainer-terminated"],
    ["switched_trainer"],
    ["Alta voluntaria del atleta"],
  ])("un terminate real sin acceptedAt → vinculo-real (reason=%s)", (reason) => {
    // EL CASO QUE COSTÓ EL BUG. `pending → paused → resume` da un vínculo
    // ACTIVO sin la marca: promote-link.ts no estampa `acceptedAt` en la rama
    // resume, y firestore.rules deja pasar a `paused` desde cualquier status.
    // Después, cualquier terminate lo dejaba borrable.
    expect(
      clasificarTerminacion({ acceptedAt: null, terminationReason: reason }),
    ).toBe("vinculo-real");
  });

  it("sin razón alguna → vinculo-real", () => {
    expect(clasificarTerminacion({ acceptedAt: null })).toBe("vinculo-real");
  });

  // ── Cuenta borrada ────────────────────────────────────────────────────────
  //
  // `cascade/trainer-links.ts` termina las solicitudes del atleta que borra su
  // cuenta con `reason: 'account-deleted'` — OJO, `reason`, NO
  // `terminationReason`. Una solicitud que nunca fue aceptada, de alguien que
  // ya no existe, es basura por la misma definición que un rechazo.
  it("account-deleted sin acceptedAt → cuenta-borrada", () => {
    expect(
      clasificarTerminacion({ acceptedAt: null, reason: "account-deleted" }),
    ).toBe("cuenta-borrada");
  });

  it("account-deleted CON acceptedAt → vinculo-real: la historia se conserva", () => {
    // El atleta se fue, pero la relación existió y de ella cuelgan los pagos y
    // las sesiones que el PF necesita. Se conserva.
    expect(
      clasificarTerminacion({
        acceptedAt: { seconds: 1 },
        reason: "account-deleted",
      }),
    ).toBe("vinculo-real");
  });

  it("`reason` no se confunde con `terminationReason`", () => {
    // Son campos DISTINTOS: la cascada escribe `reason`, el cliente escribe
    // `terminationReason`. Un `reason` cualquiera no habilita nada.
    expect(
      clasificarTerminacion({ acceptedAt: null, reason: "otra-cosa" }),
    ).toBe("vinculo-real");
    expect(
      clasificarTerminacion({ acceptedAt: null, terminationReason: "account-deleted" }),
    ).toBe("vinculo-real");
  });

  it("acceptedAt presente gana SIEMPRE, aun con razón de rechazo", () => {
    // Combinación imposible hoy (decline sólo corre sobre `pending`), pero si
    // aparece en los datos es una anomalía: se conserva, y se avisa a los dos.
    expect(
      clasificarTerminacion({
        acceptedAt: { seconds: 1 },
        terminationReason: "declined",
      }),
    ).toBe("vinculo-real");
  });

  it.each([[42], [{}], [[]], [true]])(
    "una razón que no es string → vinculo-real (%p)",
    (basura) => {
      expect(
        clasificarTerminacion({ acceptedAt: null, terminationReason: basura }),
      ).toBe("vinculo-real");
    },
  );
});

// ─── purgeRejectedLinkHandler ───────────────────────────────────────────────
//
// Recibe la CAUSA YA DECIDIDA, no el snapshot. Es deliberado: mientras recibía
// `after` podía —y debía— re-derivar el predicado, y ahí fue donde divergió del
// de `scripts/cleanup_rejected_links.js`. Con este parámetro tipado, esa clase
// de bug ni siquiera compila.
describe("purgeRejectedLinkHandler", () => {
  it("borra un rechazo", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-rechazado", "rechazo"),
    ).resolves.toBe(true);

    expect(firestore.collection).toHaveBeenCalledWith("trainer_links");
    expect(firestore.doc).toHaveBeenCalledWith("link-rechazado");
    expect(firestore.deleteDoc).toHaveBeenCalledTimes(1);
  });

  it("borra una cancelación del alumno", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-cancelado", "cancelacion"),
    ).resolves.toBe(true);

    expect(firestore.deleteDoc).toHaveBeenCalledTimes(1);
  });

  it("borra una solicitud de cuenta borrada", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-cuenta-borrada", "cuenta-borrada"),
    ).resolves.toBe(true);

    expect(firestore.deleteDoc).toHaveBeenCalledTimes(1);
  });

  it("NO borra un vínculo real", async () => {
    const firestore = installFirestore();

    await expect(
      purgeRejectedLinkHandler(APP, "link-real", "vinculo-real"),
    ).resolves.toBe(false);

    expect(firestore.deleteDoc).not.toHaveBeenCalled();
  });

  it("no lanza y devuelve false cuando Firestore falla", async () => {
    const error = new Error("Firestore caído");
    installFirestore({ deleteError: error });

    await expect(
      purgeRejectedLinkHandler(APP, "link-failed", "rechazo"),
    ).resolves.toBe(false);

    expect(logger.error).toHaveBeenCalledWith(
      "purgeRejectedLink: no se pudo borrar el rechazo",
      { linkId: "link-failed", error },
    );
  });
});
