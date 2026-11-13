/** Tests de `cancelAppointmentsOnUnlink` (#1833) contra el emulador, y su contrato con `notify-appointment`. */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { Messaging, MulticastMessage } from "firebase-admin/messaging";
import { LINK_TERMINATED_REASON, cancelAppointmentsOnUnlinkHandler } from "../cancel-appointments-on-unlink";
import { notifyOnAppointmentHandler } from "../notifications/notify-appointment";
import { deleteByQueryPaged } from "../cascade/trainer-data";

// `??=`: `emulators:exec` ya exporta esto; pisarlo manda los tests al emulador de OTRO worktree.
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.GCLOUD_PROJECT ??= "treino-dev";

let testApp: App;
beforeAll(() => {
  testApp = initializeApp({ projectId: "treino-dev" }, "cancel-appointments-on-unlink-test");
});
afterAll(async () => {
  await deleteApp(testApp);
});
const db = () => getFirestore(testApp);

// Uids propios: otras suites comparten el emulador.
const [PF, ALUMNO, OTRO_PF, OTRO_ALUMNO] = ["unl-pf", "unl-alumno", "unl-otro-pf", "unl-otro-alumno"];
const [H, DAY] = [3600000, 24 * 3600000];
// Ahora, fijo. `startsAt` se guarda como wall-clock ART etiquetado UTC (ADR-7): el instante real MENOS 3 h.
const NOW = new Date("2026-11-13T15:00:00Z");
const startsIn = (ms: number) => Timestamp.fromMillis(NOW.getTime() + ms - 3 * H);

type Doc = Record<string, unknown>;
const appt = (over: Doc = {}): Doc => ({
  trainerId: PF, athleteId: ALUMNO, athleteDisplayName: "Alumno", durationMin: 60,
  status: "confirmed", startsAt: startsIn(DAY), ...over,
});
const link = (status: string, over: Doc = {}): Doc => ({ trainerId: PF, athleteId: ALUMNO, status, ...over });
const termina = (reason?: string, desde = "active"): [Doc, Doc] => [
  link(desde),
  link("terminated", reason ? { terminationReason: reason } : {}),
];
const seedAppt = (id: string, over: Doc = {}) => db().collection("appointments").doc(id).set(appt(over));
const seedLink = (id: string, data: Doc) => db().collection("trainer_links").doc(id).set(data);
const read = async (id: string) => (await db().collection("appointments").doc(id).get()).data() ?? {};
const run = (before?: Doc, after?: Doc) => cancelAppointmentsOnUnlinkHandler(testApp, "L1", before, after, NOW);

async function limpiar(): Promise<void> {
  for (const col of ["appointments", "trainer_links"]) {
    await deleteByQueryPaged(db(), db().collection(col).where("trainerId", "in", [PF, OTRO_PF]));
  }
  const mails = await db().collection("mail_queue").where("toUid", "in", [PF, ALUMNO]).get().catch(() => null);
  await Promise.all((mails?.docs ?? []).map((d) => d.ref.delete()));
}
beforeEach(limpiar);
afterEach(limpiar);

describe("el vínculo termina: cancela los turnos futuros del par", () => {
  it("cancela los futuros (sueltos, de serie, requested) con la forma de la cancelación del cliente", async () => {
    // <24 h y en wall-clock ART: guardado como lo guarda la app queda ANTES de `now()` en instante real
    // (contra `Timestamp.now()`, como las cascadas de borrado de cuenta, este caso daría al revés).
    expect(startsIn(2 * H).toMillis()).toBeLessThan(NOW.getTime());
    await seedAppt("a-cerca", { startsAt: startsIn(2 * H) });
    await seedAppt("a-serie-1", { recurringId: "serie", startsAt: startsIn(7 * DAY) });
    await seedAppt("a-requested", { status: "requested" });
    // Lo que NO se toca: ya empezó (hace 1 h), otro alumno, otro PF.
    await seedAppt("n-empezo", { startsAt: startsIn(-1 * H) });
    await seedAppt("n-otro-alumno", { athleteId: OTRO_ALUMNO });
    await seedAppt("n-otro-pf", { trainerId: OTRO_PF });

    expect(await run(...termina("athlete-terminated"))).toEqual({ outcome: "cancelled", count: 3 });

    for (const id of ["a-cerca", "a-serie-1", "a-requested"]) {
      const d = await read(id);
      expect(d).toMatchObject({ status: "cancelled", cancelledBy: ALUMNO, reason: LINK_TERMINATED_REASON });
      expect(d.cancelledAt).toBeInstanceOf(Timestamp);
      expect(d.cancellationLog).toEqual([
        { byUid: ALUMNO, atMs: NOW.getTime(), reason: "Vínculo terminado por el alumno." },
      ]);
      expect(d).toMatchObject({ athleteId: ALUMNO, trainerId: PF, durationMin: 60 }); // el resto, intacto
    }
    for (const id of ["n-empezo", "n-otro-alumno", "n-otro-pf"]) {
      expect(await read(id)).toMatchObject({ status: "confirmed" });
      expect((await read(id)).reason).toBeUndefined();
    }
  });

  it.each([
    ["trainer-terminated", "active", PF, "Vínculo terminado por el entrenador."],
    ["athlete-terminated", "paused", ALUMNO, "Vínculo terminado por el alumno."],
    ["switched_trainer", "active", ALUMNO, "Vínculo terminado por el alumno."],
    [undefined, "active", ALUMNO, "Vínculo terminado."],
  ])("terminationReason=%s (desde %s): cancelledBy %s", async (reason, desde, quien, motivo) => {
    await seedAppt("t1");
    await run(...termina(reason, desde));

    expect(await read("t1")).toMatchObject({
      status: "cancelled",
      cancelledBy: quien,
      cancellationLog: [{ byUid: quien, atMs: NOW.getTime(), reason: motivo }],
    });
  });
});

describe("cuándo NO cancela", () => {
  const duplicada = { terminationReason: "cancelled-by-athlete", reason: "duplicate-request" };
  const casos: Array<[string, Doc, Doc, string]> = [
    ["account-deleted", link("active"), link("terminated", { reason: "account-deleted" }), "cascade"],
    ["PF borró su cuenta", link("active"), link("terminated", { reason: "trainer-account-deleted" }), "cascade"],
    ["pending → rechazo", link("pending"), link("terminated", { terminationReason: "declined" }), "skipped"],
    ["pending → duplicada (#1827)", link("pending"), link("terminated", duplicada), "skipped"],
    ["terminated → terminated", link("terminated"), link("terminated", { reason: "x" }), "skipped"],
    ["active → paused", link("active"), link("paused"), "skipped"],
  ];

  it.each(casos)("%s", async (_nombre, before, after, outcome) => {
    await seedAppt("t1");
    expect(await run(before, after)).toEqual({ outcome, count: 0 });
    expect((await read("t1")).status).toBe("confirmed");
  });

  it("con OTRO vínculo vivo del par (active o paused) se quedan; los de otro par o terminados no cuentan", async () => {
    await seedAppt("t1");
    await seedLink("otro-par", link("active", { trainerId: OTRO_PF }));
    await seedLink("viejo", link("terminated"));
    for (const vivo of ["active", "paused"]) {
      await seedLink("otro", link(vivo));
      expect(await run(...termina("athlete-terminated"))).toEqual({ outcome: "live-link", count: 0 });
      expect((await read("t1")).status).toBe("confirmed");
    }
    await seedLink("otro", link("terminated"));
    expect((await run(...termina("athlete-terminated"))).outcome).toBe("cancelled");
  });

});

describe("idempotencia", () => {
  it("lo que el cliente del PF ya canceló (#1809) no se toca; la segunda corrida no encuentra nada", async () => {
    const delCliente = { byUid: PF, atMs: 1, reason: "Vínculo terminado por el entrenador." };
    await seedAppt("ya", { status: "cancelled", cancelledBy: PF, cancellationLog: [delCliente] });
    await seedAppt("pendiente");
    const [before, after] = termina("athlete-terminated");

    expect(await run(before, after)).toEqual({ outcome: "cancelled", count: 1 });
    expect(await read("ya")).toMatchObject({ cancelledBy: PF, cancellationLog: [delCliente] });
    expect((await read("ya")).reason).toBeUndefined();

    expect(await run(before, after)).toEqual({ outcome: "nothing", count: 0 });
    expect((await read("pendiente")).cancellationLog).toHaveLength(1);
  });

  it("dos entregas simultáneas del mismo evento cancelan cada turno UNA vez (la transacción relee)", async () => {
    const ids = [1, 2, 3, 4, 5].map((n) => `c${n}`);
    for (const [i, id] of ids.entries()) await seedAppt(id, { startsAt: startsIn((i + 1) * DAY) });
    const [before, after] = termina("athlete-terminated");

    const [a, b] = await Promise.all([run(before, after), run(before, after)]);

    expect(a.count + b.count).toBe(5);
    for (const id of ids) expect((await read(id)).cancellationLog).toHaveLength(1);
  });

  it("más de un lote (420 turnos > 400 por transacción): los cancela todos", async () => {
    const batch = db().batch();
    for (let i = 0; i < 420; i++) {
      batch.set(db().collection("appointments").doc(`m-${i}`), appt({ startsAt: startsIn((i + 1) * H) }));
    }
    await batch.commit();

    expect(await run(...termina("athlete-terminated"))).toEqual({ outcome: "cancelled", count: 420 });
    expect([(await read("m-0")).status, (await read("m-419")).status]).toEqual(["cancelled", "cancelled"]);
  });
});

describe("contrato con notify-appointment: el cancel REAL no avisa N veces", () => {
  const ids = ["k1", "k2", "k3"];
  const mensajeria = (): Messaging =>
    ({
      sendEachForMulticast: jest.fn(async (msg: MulticastMessage) => ({
        successCount: msg.tokens.length,
        failureCount: 0,
        responses: msg.tokens.map(() => ({ success: true, messageId: "id" })),
      })),
    }) as unknown as Messaging;
  const pushes = (m: Messaging) => (m.sendEachForMulticast as jest.Mock).mock.calls.length;
  const notificar = (m: Messaging, antes: Doc, despues: Doc) =>
    notifyOnAppointmentHandler(testApp, "k1", antes, despues, m);

  beforeEach(async () => {
    // Los dos con token: si el guard falla, el mock recibe destinatarios de VERDAD.
    await db().collection("users").doc(PF).set({ uid: PF, fcmTokens: ["pf-token"] });
    await db().collection("users").doc(ALUMNO).set({ uid: ALUMNO, fcmTokens: ["alumno-token"] });
    for (const id of ids) await seedAppt(id, { recurringId: "serie" });
  });
  afterEach(async () => {
    await db().collection("users").doc(PF).delete();
    await db().collection("users").doc(ALUMNO).delete();
  });

  it("el par de snapshots que produce el handler no manda push ni encola mail", async () => {
    const antes = await Promise.all(ids.map(read));
    expect((await run(...termina("athlete-terminated"))).count).toBe(3);
    const despues = await Promise.all(ids.map(read));

    const m = mensajeria();
    for (const [i, id] of ids.entries()) await notifyOnAppointmentHandler(testApp, id, antes[i], despues[i], m);

    expect(pushes(m)).toBe(0);
    expect((await db().collection("mail_queue").where("toUid", "in", [PF, ALUMNO]).get()).size).toBe(0);
  });

  it("CONTROL: la misma cancelación SIN la señal sí avisa; un `reason` forjado en el log no silencia", async () => {
    const antes = await read("k1");
    const cancelado = { ...antes, status: "cancelled", cancelledBy: ALUMNO };
    const forjado = { ...cancelado, cancellationLog: [{ byUid: ALUMNO, atMs: 1, reason: LINK_TERMINATED_REASON }] };

    const m = mensajeria();
    await notificar(m, antes, cancelado);
    await notificar(m, antes, forjado);

    expect(pushes(m)).toBe(2);
  });
});
