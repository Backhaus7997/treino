/**
 * Integration tests for the TRAINER account-deletion cascade (#1333).
 * Run against the Firebase Local Emulator (Firestore).
 *
 * The cascade runs UNCONDITIONALLY on every deleteAccount call (no role
 * guard), so every test also asserts the cascade is a no-op for other uids.
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
process.env.GCLOUD_PROJECT = "treino-dev";

let testApp: App;

beforeAll(() => {
  testApp = initializeApp(
    { projectId: "treino-dev", storageBucket: "treino-dev.appspot.com" },
    "trainer-data-cascade-test"
  );
});

afterAll(async () => {
  await deleteApp(testApp);
});

import {
  TRAINER_ACCOUNT_DELETED_REASON,
  deleteByQueryPaged,
  cancelFutureAppointmentsAsTrainer,
  deleteTrainerOwnedData,
  deleteTrainerTemplates,
  terminateLinksAsTrainer,
} from "../../cascade/trainer-data";

const db = () => getFirestore(testApp);

describe("TRAINER_ACCOUNT_DELETED_REASON", () => {
  it("is the CF->CF contract value", () => {
    expect(TRAINER_ACCOUNT_DELETED_REASON).toBe("trainer-account-deleted");
  });
});

describe("SC-PSD-08: deleteByQueryPaged", () => {
  const owner = "psd-page-owner";
  const other = "psd-page-other";
  const col = "psd_paged_probe";

  afterEach(async () => {
    await db().recursiveDelete(db().collection(col));
  });

  it("deletes more than one page (450 docs) and nothing else", async () => {
    const writer = db().bulkWriter();
    for (let i = 0; i < 450; i++) {
      writer.set(db().collection(col).doc(`o-${i}`), { trainerId: owner });
    }
    writer.set(db().collection(col).doc("keep"), { trainerId: other });
    await writer.close();

    const deleted = await deleteByQueryPaged(
      db(),
      db().collection(col).where("trainerId", "==", owner)
    );

    expect(deleted).toBe(450);
    const left = await db().collection(col).get();
    expect(left.docs.map((d) => d.id)).toEqual(["keep"]);
  });

  it("returns 0 on an empty result", async () => {
    const deleted = await deleteByQueryPaged(
      db(),
      db().collection(col).where("trainerId", "==", "nobody")
    );
    expect(deleted).toBe(0);
  });
});

describe("SC-PSD-06: terminateLinksAsTrainer", () => {
  const pf = "psd-links-pf";
  const ids = ["l-pending", "l-active", "l-paused", "l-done", "l-other"];

  beforeEach(async () => {
    const b = db().batch();
    const mk = (id: string, trainerId: string, status: string, extra = {}) =>
      b.set(db().collection("trainer_links").doc(id), {
        trainerId,
        athleteId: `ath-${id}`,
        status,
        ...extra,
      });
    mk("l-pending", pf, "pending");
    mk("l-active", pf, "active");
    mk("l-paused", pf, "paused");
    mk("l-done", pf, "terminated", { reason: "declined" });
    mk("l-other", "psd-links-other-pf", "active");
    await b.commit();
  });
  afterEach(async () => {
    await Promise.all(
      ids.map((id) => db().collection("trainer_links").doc(id).delete())
    );
  });

  it("terminates every non-terminal link with the new reason, same keys as the athlete cascade", async () => {
    const res = await terminateLinksAsTrainer(testApp, pf);
    expect(res.count).toBe(3);

    for (const id of ["l-pending", "l-active", "l-paused"]) {
      const d = (await db().collection("trainer_links").doc(id).get()).data()!;
      expect(d.status).toBe("terminated");
      expect(d.reason).toBe(TRAINER_ACCOUNT_DELETED_REASON);
      expect(d.terminatedAt).toBeInstanceOf(Timestamp);
      // #846 hasOnly trap: no keys beyond the athlete cascade's.
      expect(Object.keys(d).sort()).toEqual(
        ["athleteId", "reason", "status", "terminatedAt", "trainerId"].sort()
      );
    }
  });

  it("leaves already-terminated links and other trainers' links alone", async () => {
    await terminateLinksAsTrainer(testApp, pf);
    const done = (await db().collection("trainer_links").doc("l-done").get()).data()!;
    expect(done.reason).toBe("declined");
    const other = (await db().collection("trainer_links").doc("l-other").get()).data()!;
    expect(other.status).toBe("active");
  });

  it("SC-PSD-04: a second run is a no-op (count 0, nothing re-written)", async () => {
    await terminateLinksAsTrainer(testApp, pf);
    const before = (await db().collection("trainer_links").doc("l-active").get()).data()!;
    const res = await terminateLinksAsTrainer(testApp, pf);
    expect(res.count).toBe(0);
    const after = (await db().collection("trainer_links").doc("l-active").get()).data()!;
    expect(after.terminatedAt.isEqual(before.terminatedAt)).toBe(true);
  });
});

describe("SC-PSD-12/13/14: cancelFutureAppointmentsAsTrainer", () => {
  const pf = "psd-appt-pf";
  const day = 24 * 3600 * 1000;
  const future = () => Timestamp.fromMillis(Date.now() + 3 * day);
  const past = () => Timestamp.fromMillis(Date.now() - 3 * day);
  const appts = ["a-future-conf", "a-future-req", "a-future-cancelled", "a-past", "a-other"];
  const avail = ["r1", "r2", "o1", "r-other"];

  beforeEach(async () => {
    const b = db().batch();
    const ap = (id: string, trainerId: string, status: string, startsAt: Timestamp) =>
      b.set(db().collection("appointments").doc(id), {
        trainerId,
        athleteId: `ath-${id}`,
        status,
        startsAt,
      });
    ap("a-future-conf", pf, "confirmed", future());
    ap("a-future-req", pf, "requested", future());
    ap("a-future-cancelled", pf, "cancelled", future());
    ap("a-past", pf, "confirmed", past());
    ap("a-other", "psd-appt-other", "confirmed", future());
    b.set(db().collection("coach_availability_rules").doc("r1"), { trainerId: pf });
    b.set(db().collection("coach_availability_rules").doc("r2"), { trainerId: pf });
    b.set(db().collection("coach_availability_overrides").doc("o1"), { trainerId: pf });
    b.set(db().collection("coach_availability_rules").doc("r-other"), { trainerId: "psd-appt-other" });
    await b.commit();
  });
  afterEach(async () => {
    await Promise.all([
      ...appts.map((id) => db().collection("appointments").doc(id).delete()),
      ...avail.slice(0, 2).concat("r-other").map((id) =>
        db().collection("coach_availability_rules").doc(id).delete()),
      db().collection("coach_availability_overrides").doc("o1").delete(),
    ]);
  });

  it("cancels future requested/confirmed with the new reason + cancelledBy + log entry", async () => {
    const res = await cancelFutureAppointmentsAsTrainer(testApp, pf);
    expect(res.count).toBe(2);
    for (const id of ["a-future-conf", "a-future-req"]) {
      const d = (await db().collection("appointments").doc(id).get()).data()!;
      expect(d.status).toBe("cancelled");
      expect(d.reason).toBe(TRAINER_ACCOUNT_DELETED_REASON);
      expect(d.cancelledBy).toBe(pf);
      expect(d.cancellationLog).toEqual([
        expect.objectContaining({
          byUid: pf,
          reason: TRAINER_ACCOUNT_DELETED_REASON,
          atMs: expect.any(Number),
        }),
      ]);
    }
  });

  it("SC-PSD-13: past, already-cancelled and other trainers' appointments untouched", async () => {
    await cancelFutureAppointmentsAsTrainer(testApp, pf);
    const past = (await db().collection("appointments").doc("a-past").get()).data()!;
    expect(past.status).toBe("confirmed");
    expect(past.reason).toBeUndefined();
    const cancelled = (await db().collection("appointments").doc("a-future-cancelled").get()).data()!;
    expect(cancelled.reason).toBeUndefined();
    const other = (await db().collection("appointments").doc("a-other").get()).data()!;
    expect(other.status).toBe("confirmed");
  });

  it("SC-PSD-14: deletes the trainer's availability rules and overrides only", async () => {
    await cancelFutureAppointmentsAsTrainer(testApp, pf);
    expect((await db().collection("coach_availability_rules").where("trainerId", "==", pf).get()).size).toBe(0);
    expect((await db().collection("coach_availability_overrides").where("trainerId", "==", pf).get()).size).toBe(0);
    expect((await db().collection("coach_availability_rules").doc("r-other").get()).exists).toBe(true);
  });

  it("second run is a no-op", async () => {
    await cancelFutureAppointmentsAsTrainer(testApp, pf);
    const res = await cancelFutureAppointmentsAsTrainer(testApp, pf);
    expect(res.count).toBe(0);
  });
});

const OWNED_COLLECTIONS = [
  "athlete_notes",
  "athlete_billing",
  "athlete_files",
  "follow_up_entries",
  "nutrition_plans",
  "reviews",
  "session_shares",
  "profile_shares",
];

describe("SC-PSD-15/17/18/19: deleteTrainerOwnedData", () => {
  const pf = "psd-owned-pf";
  const other = "psd-owned-other";

  beforeEach(async () => {
    const b = db().batch();
    for (const c of OWNED_COLLECTIONS) {
      b.set(db().collection(c).doc(`${c}-pf-1`), { trainerId: pf, athleteId: "a1" });
      b.set(db().collection(c).doc(`${c}-pf-2`), { trainerId: pf, athleteId: "a2" });
      b.set(db().collection(c).doc(`${c}-other`), { trainerId: other, athleteId: "a1" });
    }
    b.set(db().collection("payments").doc("pay-pf"), { trainerId: pf, athleteId: "a1" });
    b.set(db().collection("gyms").doc("psd-gym"), { name: "Shared gym", createdBy: pf });
    await b.commit();
  });
  afterEach(async () => {
    const b = db().batch();
    for (const c of OWNED_COLLECTIONS) {
      for (const sfx of ["pf-1", "pf-2", "other"]) b.delete(db().collection(c).doc(`${c}-${sfx}`));
    }
    b.delete(db().collection("payments").doc("pay-pf"));
    b.delete(db().collection("gyms").doc("psd-gym"));
    await b.commit();
  });

  it("deletes every trainer-keyed collection for the uid and nothing else", async () => {
    const res = await deleteTrainerOwnedData(testApp, pf);
    expect(res.deleted).toBe(OWNED_COLLECTIONS.length * 2);
    for (const c of OWNED_COLLECTIONS) {
      expect((await db().collection(c).where("trainerId", "==", pf).get()).size).toBe(0);
      expect((await db().collection(c).doc(`${c}-other`).get()).exists).toBe(true);
    }
  });

  it("SC-PSD-18/21: payments (fiscal retention) and shared gyms are retained", async () => {
    await deleteTrainerOwnedData(testApp, pf);
    expect((await db().collection("payments").doc("pay-pf").get()).exists).toBe(true);
    expect((await db().collection("gyms").doc("psd-gym").get()).exists).toBe(true);
  });

  it("second run is a no-op", async () => {
    await deleteTrainerOwnedData(testApp, pf);
    expect((await deleteTrainerOwnedData(testApp, pf)).deleted).toBe(0);
  });
});

describe("SC-PSD-09/10: deleteTrainerTemplates", () => {
  const pf = "psd-tpl-pf";
  const ids = ["t-private", "t-public", "t-assigned", "t-adopted", "t-other"];

  beforeEach(async () => {
    const r = (id: string) => db().collection("routines").doc(id);
    const b = db().batch();
    b.set(r("t-private"), { assignedBy: pf, source: "trainer-template", visibility: "private" });
    b.set(r("t-public"), { assignedBy: pf, source: "trainer-template", visibility: "public" });
    b.set(r("t-assigned"), { assignedBy: pf, assignedTo: "ath-1", source: "trainer-assigned" });
    b.set(r("t-adopted"), { createdBy: "ath-2", source: "user-created", adoptedFrom: "t-public" });
    b.set(r("t-other"), { assignedBy: "psd-tpl-other", source: "trainer-template" });
    b.set(r("t-public").collection("ratings").doc("ath-9"), { stars: 5 });
    await b.commit();
  });
  afterEach(async () => {
    await Promise.all(ids.map((id) => db().recursiveDelete(db().collection("routines").doc(id))));
  });

  it("deletes private and published templates with their ratings subcollection", async () => {
    const res = await deleteTrainerTemplates(testApp, pf);
    expect(res.deleted).toBe(2);
    expect((await db().collection("routines").doc("t-private").get()).exists).toBe(false);
    expect((await db().collection("routines").doc("t-public").get()).exists).toBe(false);
    expect((await db().collection("routines").doc("t-public").collection("ratings").get()).size).toBe(0);
  });

  it("keeps assigned plans, athlete-adopted copies and other trainers' templates", async () => {
    await deleteTrainerTemplates(testApp, pf);
    for (const id of ["t-assigned", "t-adopted", "t-other"]) {
      expect((await db().collection("routines").doc(id).get()).exists).toBe(true);
    }
  });

  it("second run is a no-op", async () => {
    await deleteTrainerTemplates(testApp, pf);
    expect((await deleteTrainerTemplates(testApp, pf)).deleted).toBe(0);
  });
});

describe("SC-PSD-05/03: the cascade runs for ANY uid and is a no-op for an athlete", () => {
  const ath = "psd-noop-athlete";
  const pf = "psd-noop-pf";
  const seeded: Array<[string, string]> = [
    ["trainer_links", "nl1"],
    ["appointments", "na1"],
    ["athlete_notes", "nn1"],
    ["athlete_billing", "nb1"],
    ["follow_up_entries", "nf1"],
    ["reviews", "nr1"],
    ["session_shares", ath],
    ["profile_shares", ath],
    ["payments", "np1"],
    ["routines", "nt-assigned"],
    ["routines", "nt-own"],
  ];

  beforeEach(async () => {
    const b = db().batch();
    const set = (c: string, id: string, d: object) => b.set(db().collection(c).doc(id), d);
    set("trainer_links", "nl1", { trainerId: pf, athleteId: ath, status: "active" });
    set("appointments", "na1", {
      trainerId: pf, athleteId: ath, status: "confirmed",
      startsAt: Timestamp.fromMillis(Date.now() + 86400000),
    });
    for (const c of ["athlete_notes", "athlete_billing", "follow_up_entries", "reviews"]) {
      set(c, { athlete_notes: "nn1", athlete_billing: "nb1", follow_up_entries: "nf1", reviews: "nr1" }[c]!,
        { trainerId: pf, athleteId: ath });
    }
    set("session_shares", ath, { trainerId: pf });
    set("profile_shares", ath, { trainerId: pf });
    set("payments", "np1", { trainerId: pf, athleteId: ath });
    set("routines", "nt-assigned", { assignedBy: pf, assignedTo: ath, source: "trainer-assigned" });
    set("routines", "nt-own", { createdBy: ath, source: "user-created" });
    await b.commit();
  });
  afterEach(async () => {
    await Promise.all(seeded.map(([c, id]) => db().collection(c).doc(id).delete()));
  });

  const snapshotAll = async () =>
    Promise.all(seeded.map(async ([c, id]) => (await db().collection(c).doc(id).get()).data()));

  it("an athlete uid touches nothing (every trainerId/assignedBy query is empty)", async () => {
    const before = await snapshotAll();
    expect(await terminateLinksAsTrainer(testApp, ath)).toEqual({ count: 0 });
    expect(await cancelFutureAppointmentsAsTrainer(testApp, ath)).toEqual({ count: 0 });
    expect(await deleteTrainerOwnedData(testApp, ath)).toEqual({ deleted: 0 });
    expect(await deleteTrainerTemplates(testApp, ath)).toEqual({ deleted: 0 });
    expect(await snapshotAll()).toEqual(before);
  });

  it("SC-PSD-03: re-running for the PF after users/{uid} is gone still sweeps everything", async () => {
    // users/{pf} was never created here: the cascade must not depend on it.
    await terminateLinksAsTrainer(testApp, pf);
    await cancelFutureAppointmentsAsTrainer(testApp, pf);
    await deleteTrainerOwnedData(testApp, pf);
    await deleteTrainerTemplates(testApp, pf);
    expect((await db().collection("trainer_links").doc("nl1").get()).data()!.status).toBe("terminated");
    expect((await db().collection("appointments").doc("na1").get()).data()!.status).toBe("cancelled");
    expect((await db().collection("athlete_notes").doc("nn1").get()).exists).toBe(false);
    // retained / athlete-owned
    expect((await db().collection("payments").doc("np1").get()).exists).toBe(true);
    expect((await db().collection("routines").doc("nt-assigned").get()).exists).toBe(true);
    expect((await db().collection("routines").doc("nt-own").get()).exists).toBe(true);
  });
});
