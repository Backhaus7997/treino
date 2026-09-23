/**
 * Tests de la cuarentena de rutinas, contra el emulador de Firestore.
 *
 * Superficie distinta de `quarantineIfVetted`: una rutina puede tener VARIOS
 * campos vetados a la vez en el mismo write (top-level Y anidados dentro de
 * `days[].slots[]`), y Firestore no deja actualizar un elemento de array por
 * indice — hay que leer el array completo, redactar adentro, y reescribirlo
 * entero. Ver el dartdoc de `quarantineRoutineIfVetted`.
 *
 * Correr:
 *   firebase emulators:exec --only firestore --project treino-dev \
 *     "npx jest --forceExit quarantine-routine-fields"
 */

import { App, deleteApp, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

import {
  QUARANTINE_COLLECTION,
  quarantineRoutineIfVetted,
} from "../moderation/quarantine-vetted-content";

const VETADO = "sos un hijo de puta";
const REVIEW = "sos un pelotudo";

interface RutinaData extends FirebaseFirestore.DocumentData {
  name: string;
  split?: string | null;
  summary?: string | null;
  days: { name: string; slots: { notes?: string | null }[] }[];
}

/**
 * Rutina con DOS dias — el segundo con CUATRO slots — para poder probar el
 * caso `days[1].slots[3]` (ultimo dia, ultimo slot) y no sólo la posicion 0.
 */
function rutinaBase(overrides: Partial<RutinaData> = {}): RutinaData {
  return {
    name: "Rutina limpia",
    split: "PPL",
    summary: "Resumen limpio.",
    days: [
      { name: "Dia 1 - Pecho", slots: [{ notes: "buena forma" }] },
      {
        name: "Dia 2 - Piernas",
        slots: [
          { notes: "sentir el musculo" },
          { notes: "buena forma" },
          { notes: "controlar el descenso" },
          { notes: "notas limpias" },
        ],
      },
    ],
    ...overrides,
  };
}

let app: App;
let db: Firestore;

beforeAll(() => {
  app = initializeApp({ projectId: "treino-dev" }, "quarantine-routine-tests");
  db = getFirestore(app);
});

afterAll(async () => {
  await deleteApp(app);
});

afterEach(async () => {
  for (const c of ["routines", QUARANTINE_COLLECTION]) {
    const snap = await db.collection(c).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
});

const registro = (path: string, field: string) =>
  db
    .collection(QUARANTINE_COLLECTION)
    .doc(`${path.replace(/\//g, "__")}__${field.replace(/[[\].]/g, "_")}`)
    .get();

describe("quarantineRoutineIfVetted", () => {
  it("redacta el nombre vetado y deja registro", async () => {
    const data = rutinaBase({ name: VETADO });
    await db.doc("routines/r1").set(data);

    const findings = await quarantineRoutineIfVetted({
      db,
      path: "routines/r1",
      data,
      authorUid: "athlete-a",
    });

    expect(findings).toEqual([{ field: "name", verdict: "block" }]);
    expect((await db.doc("routines/r1").get()).get("name")).toBe("");

    const reg = await registro("routines/r1", "name");
    expect(reg.exists).toBe(true);
    expect(reg.get("verdict")).toBe("block");
    expect(reg.get("kind")).toBe("routine");
    expect(reg.get("authorUid")).toBe("athlete-a");
  });

  it("redacta split vetado sin tocar name/summary/days", async () => {
    const data = rutinaBase({ split: VETADO });
    await db.doc("routines/r2").set(data);

    await quarantineRoutineIfVetted({ db, path: "routines/r2", data });

    const after = (await db.doc("routines/r2").get()).data()!;
    expect(after.split).toBe("");
    expect(after.name).toBe("Rutina limpia");
    expect(after.summary).toBe("Resumen limpio.");
  });

  it("redacta summary vetado", async () => {
    const data = rutinaBase({ summary: VETADO });
    await db.doc("routines/r3").set(data);

    await quarantineRoutineIfVetted({ db, path: "routines/r3", data });

    expect((await db.doc("routines/r3").get()).get("summary")).toBe("");
  });

  it("redacta days[0].name vetado sin tocar sus slots ni el otro dia", async () => {
    const data = rutinaBase();
    data.days[0].name = VETADO;
    await db.doc("routines/r4").set(data);

    const findings = await quarantineRoutineIfVetted({
      db,
      path: "routines/r4",
      data,
    });

    expect(findings).toEqual([{ field: "days[0].name", verdict: "block" }]);
    const after = (await db.doc("routines/r4").get()).data()!;
    expect(after.days[0].name).toBe("");
    expect(after.days[0].slots[0].notes).toBe("buena forma");
    expect(after.days[1].name).toBe("Dia 2 - Piernas");
  });

  it(
    "redacta days[1].slots[3].notes vetado — el ULTIMO slot del ULTIMO " +
      "dia, no el primero — sin tocar los otros tres slots del mismo dia " +
      "ni el dia 0",
    async () => {
      // Un bug de indice (mirar solo days[0], o siempre slots[0]) pasa
      // desapercibido si el unico caso probado es la posicion 0.
      const data = rutinaBase();
      data.days[1].slots[3].notes = VETADO;
      await db.doc("routines/r5").set(data);

      const findings = await quarantineRoutineIfVetted({
        db,
        path: "routines/r5",
        data,
      });

      expect(findings).toEqual([
        { field: "days[1].slots[3].notes", verdict: "block" },
      ]);
      const after = (await db.doc("routines/r5").get()).data()!;
      expect(after.days[1].slots[3].notes).toBe("");
      // Los otros tres slots del MISMO dia quedan intactos.
      expect(after.days[1].slots[0].notes).toBe("sentir el musculo");
      expect(after.days[1].slots[1].notes).toBe("buena forma");
      expect(after.days[1].slots[2].notes).toBe("controlar el descenso");
      // Y el dia 0, sin relacion, tampoco se toca.
      expect(after.days[0].name).toBe("Dia 1 - Pecho");
      expect(after.days[0].slots[0].notes).toBe("buena forma");
    },
  );

  it("dos campos vetados a la vez dejan DOS registros — ninguno pisa al otro", async () => {
    const data = rutinaBase({ name: VETADO });
    data.days[1].slots[3].notes = VETADO;
    await db.doc("routines/r6").set(data);

    const findings = await quarantineRoutineIfVetted({
      db,
      path: "routines/r6",
      data,
    });

    expect(findings).toHaveLength(2);
    const nombreReg = await registro("routines/r6", "name");
    const notasReg = await registro("routines/r6", "days[1].slots[3].notes");
    expect(nombreReg.exists).toBe(true);
    expect(notasReg.exists).toBe(true);
    expect(nombreReg.get("field")).toBe("name");
    expect(notasReg.get("field")).toBe("days[1].slots[3].notes");

    const after = (await db.doc("routines/r6").get()).data()!;
    expect(after.name).toBe("");
    expect(after.days[1].slots[3].notes).toBe("");
  });

  it(
    "vocabulario que roza el filtro (allowlist, \"culo\"/\"puta\" como " +
      "subcadena de palabras legitimas) no se toca",
    async () => {
      // A diferencia del corpus viejo (musculo/dorsal/aductores: ninguna es
      // subcadena de un termino de VETTED_ANTI_EVASION, asi que este test
      // pasaba igual con `checkText` devolviendo "ok" siempre) este corpus
      // usa palabras que SI entran a la pasada antievasion y sobreviven solo
      // por la allowlist — "controlo" contiene "trolo", "computo" contiene
      // "puto" — o que dependen de que la pasada A compare por palabra
      // completa y no por subcadena — "calculo" contiene "culo". Si se
      // rompe cualquiera de las dos cosas, este test se pone rojo.
      const data = rutinaBase({
        name: "Full body - controlo la tecnica",
        split: "El computo de series por grupo muscular",
        summary: "Trabajo el musculo dorsal sin descontrolo en la carga.",
      });
      data.days[0].name = "Dia de aductores y calculo de RM";
      data.days[1].slots[3].notes = "No te disputo el peso, priorizo la forma";
      await db.doc("routines/r7").set(data);

      const findings = await quarantineRoutineIfVetted({
        db,
        path: "routines/r7",
        data,
      });

      expect(findings).toEqual([]);
      const after = (await db.doc("routines/r7").get()).data()!;
      expect(after.name).toBe("Full body - controlo la tecnica");
      expect(after.split).toBe("El computo de series por grupo muscular");
      expect(after.days[0].name).toBe("Dia de aductores y calculo de RM");
      expect(after.days[1].slots[3].notes).toBe(
        "No te disputo el peso, priorizo la forma",
      );
    },
  );

  it(
    "el cue que motivo todo: 'matate' en una nota de entrenador ya no " +
      "bloquea la rutina, pero queda para revision",
    async () => {
      // finding 3: "matate" es jerga de gimnasio corriente ("matate en la
      // ultima serie") y bajo de `block` a `review` — deja de impedir el
      // guardado, pero sigue quedando anotado para que un humano lo mire.
      const data = rutinaBase();
      data.days[1].slots[3].notes =
        "Dale, matate en la ultima serie que ya casi terminamos";
      await db.doc("routines/r13").set(data);

      const findings = await quarantineRoutineIfVetted({
        db,
        path: "routines/r13",
        data,
      });

      expect(findings).toEqual([
        { field: "days[1].slots[3].notes", verdict: "review" },
      ]);
      // review no redacta: la nota del entrenador sobrevive tal cual.
      const after = (await db.doc("routines/r13").get()).data()!;
      expect(after.days[1].slots[3].notes).toBe(
        "Dale, matate en la ultima serie que ya casi terminamos",
      );
      const reg = await registro("routines/r13", "days[1].slots[3].notes");
      expect(reg.get("verdict")).toBe("review");
      expect(reg.get("redacted")).toBe(false);
    },
  );

  it("severidad review deja registro pero NO redacta", async () => {
    // `review` significa "que alguien lo mire", no "no se puede guardar" —
    // mismo contrato que `quarantineIfVetted`.
    const data = rutinaBase({ name: REVIEW });
    await db.doc("routines/r8").set(data);

    const findings = await quarantineRoutineIfVetted({
      db,
      path: "routines/r8",
      data,
    });

    expect(findings).toEqual([{ field: "name", verdict: "review" }]);
    expect((await db.doc("routines/r8").get()).get("name")).toBe(REVIEW);
    const reg = await registro("routines/r8", "name");
    expect(reg.get("redacted")).toBe(false);
  });

  it("no encuentra nada en una rutina limpia y no escribe registro", async () => {
    const data = rutinaBase();
    await db.doc("routines/r9").set(data);

    const findings = await quarantineRoutineIfVetted({
      db,
      path: "routines/r9",
      data,
    });

    expect(findings).toEqual([]);
    expect((await db.collection(QUARANTINE_COLLECTION).get()).size).toBe(0);
  });

  it("la segunda pasada sobre lo ya redactado no hace nada (no hay bucle)", async () => {
    const data = rutinaBase({ name: VETADO });
    await db.doc("routines/r10").set(data);
    await quarantineRoutineIfVetted({ db, path: "routines/r10", data });

    const redactedData = (await db.doc("routines/r10").get()).data()!;
    const segunda = await quarantineRoutineIfVetted({
      db,
      path: "routines/r10",
      data: redactedData,
    });

    expect(segunda).toEqual([]);
  });

  it("no redacta si el documento cambio despues del evento (precondicion)", async () => {
    // Entre que el handler mira el valor y escribe, alguien mas pudo
    // editar la rutina (reordenar un slot, cambiar un peso). Sin
    // precondicion el `update()` cae sobre la version NUEVA y pisa esa
    // edicion — acá el riesgo es mayor que con un campo suelto, porque lo
    // que se pisaria es el array `days` ENTERO.
    const data = rutinaBase({ name: VETADO });
    const ref = db.doc("routines/r11");
    await ref.set(data);
    const viejo = (await ref.get()).updateTime;

    // Alguien edita entre medio — algo sin relacion con el nombre.
    await ref.update({ estimatedMinutesPerDay: 45 });

    await quarantineRoutineIfVetted({
      db,
      path: "routines/r11",
      data,
      updateTime: viejo,
    });

    const after = (await ref.get()).data()!;
    expect(after.name).toBe(VETADO); // no se toco: se abandono
    expect(after.estimatedMinutesPerDay).toBe(45); // la edicion sobrevive

    // finding 6: el registro no puede seguir afirmando `redacted: true`
    // sobre una rutina que en realidad no se toco.
    const reg = await registro("routines/r11", "name");
    expect(reg.get("redacted")).toBe(false);
  });

  it("no guarda el texto vetado en el registro", async () => {
    // Puede tener datos personales de terceros. Quien modere abre el
    // documento original, autenticado.
    const data = rutinaBase({ name: VETADO });
    await db.doc("routines/r12").set(data);
    await quarantineRoutineIfVetted({ db, path: "routines/r12", data });

    const reg = JSON.stringify(
      (await registro("routines/r12", "name")).data(),
    );
    expect(reg).not.toContain("puta");
    expect(reg).not.toContain("hijo");
  });

  it(
    "BLOQUEANTE: un days[] con un elemento null no apaga el filtro del " +
      "resto del documento — el top-level se redacta y el registro se " +
      "escribe igual",
    async () => {
      // Vector real: un escritor por SDK directo manda `days: [null]`.
      // `Array.isArray(data.days)` protege que `days` sea un array, NO que
      // sus elementos lo sean, y firestore.rules solo valida
      // `data.days.size()` (no el tipo de los elementos). Antes del fix,
      // `day.name` tiraba `TypeError: Cannot read properties of null` DENTRO
      // del `.map()`, antes de llegar al loop que escribe
      // `moderation_quarantine` — asi que ni el top-level se redactaba ni
      // quedaba registro, y el termino vetado quedaba publicado.
      const data = {
        name: VETADO,
        split: null,
        summary: "Resumen limpio.",
        days: [null],
      };
      await db.doc("routines/r14").set(data);

      const findings = await quarantineRoutineIfVetted({
        db,
        path: "routines/r14",
        data,
      });

      expect(findings).toEqual([{ field: "name", verdict: "block" }]);
      expect((await db.doc("routines/r14").get()).get("name")).toBe("");
      const reg = await registro("routines/r14", "name");
      expect(reg.exists).toBe(true);
      expect(reg.get("verdict")).toBe("block");
    },
  );

  it(
    "BLOQUEANTE: un slots[] con un elemento null no apaga el filtro del " +
      "resto del dia ni del documento",
    async () => {
      const data = {
        name: "Rutina limpia",
        split: null,
        summary: "Resumen limpio.",
        days: [
          { name: VETADO, slots: [null] },
          { name: "Dia 2", slots: [{ notes: VETADO }, null] },
        ],
      };
      await db.doc("routines/r15").set(data);

      const findings = await quarantineRoutineIfVetted({
        db,
        path: "routines/r15",
        data,
      });

      expect(findings).toEqual([
        { field: "days[0].name", verdict: "block" },
        { field: "days[1].slots[0].notes", verdict: "block" },
      ]);
      const after = (await db.doc("routines/r15").get()).data()!;
      expect(after.days[0].name).toBe("");
      expect(after.days[1].slots[0].notes).toBe("");
      // Los `null` conviven en el array sin romper nada — no es nuestro
      // trabajo "arreglarlos", solo no dejar que apaguen el resto.
      expect(after.days[0].slots[0]).toBeNull();
      expect(after.days[1].slots[1]).toBeNull();
    },
  );
});
