/**
 * select-blocked-links.test.ts — quien se bloquea cuando un PF queda por
 * encima de su limite (paywall Fase 7, downgrade). LOCAL — sin emulador.
 *
 * Pura decision, sin Firestore: dada la lista de vinculos y el limite
 * efectivo, devuelve a quien bloquear, a quien devolver, la carga resultante y
 * la lista denormalizada de atletas que quedan bloqueados.
 */

import {
  reconcileEntitlements,
  BlockableLink,
  EntitlementReconciliation,
} from "../subscriptions/select-blocked-links";
import { computeWeightedLoad } from "../subscriptions/weighted-load";

const link = (o: Partial<BlockableLink> & { id: string }): BlockableLink => ({
  athleteId: `a-${o.id}`,
  status: "active",
  entitlement: "entitled",
  acceptedAtMs: 1000,
  ...o,
});

/**
 * Proyecta el estado resultante igual que lo hace sync-entitlements.ts antes
 * de recalcular la carga. Vive aca para poder confrontar la decision con la
 * funcion REAL de carga en vez de con una cuenta a mano.
 */
const aplicar = (
  links: BlockableLink[],
  r: EntitlementReconciliation,
): BlockableLink[] => {
  const block = new Set(r.block);
  const unblock = new Set(r.unblock);
  return links.map((l) => ({
    ...l,
    entitlement: block.has(l.id)
      ? "blocked"
      : unblock.has(l.id)
        ? "entitled"
        : l.entitlement,
  }));
};

const carga = (links: BlockableLink[]): number =>
  computeWeightedLoad(
    links.map((l) => ({
      athleteId: l.athleteId,
      status: l.status,
      entitlement: l.entitlement,
    })),
  );

// ---------------------------------------------------------------------------
// SELECCION — quien entra en el cupo.
//
// La PRIORIDAD es la antiguedad: se conservan primero los mas ANTIGUOS. Ojo
// que no es un corte limpio — ver el describe "la cola del cupo". Estos tests
// estaban escritos
// contra la funcion `selectLinksToBlock`, que se borro por muerta; la conducta
// que verificaban (pesos, dedupe, desempate, bordes del limite) vive igual en
// `reconcileEntitlements`, que es la que usa produccion, asi que se re-alojaron
// aca en vez de borrarse con ella.
// ---------------------------------------------------------------------------

describe("reconcileEntitlements — seleccion", () => {
  it("bajo el limite no bloquea a nadie", () => {
    const r = reconcileEntitlements([link({ id: "L1" }), link({ id: "L2" })], 7);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
    expect(r.blockedAthleteIds).toEqual([]);
  });

  it("justo en el limite no bloquea (7.0 <= 7)", () => {
    const links = Array.from({ length: 7 }, (_, i) =>
      link({ id: `L${i}`, acceptedAtMs: 1000 + i }));
    expect(reconcileEntitlements(links, 7).block).toEqual([]);
  });

  it("conserva los mas ANTIGUOS y bloquea el excedente", () => {
    // Free (2): 4 activos. Se conservan los 2 de acceptedAt mas BAJO — la
    // relacion mas vieja es la que peor se explica romper.
    const links = [
      link({ id: "viejo1", acceptedAtMs: 100 }),
      link({ id: "viejo2", acceptedAtMs: 200 }),
      link({ id: "nuevo1", acceptedAtMs: 900 }),
      link({ id: "nuevo2", acceptedAtMs: 800 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.block.sort()).toEqual(["nuevo1", "nuevo2"]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("los pausados pesan 0.5 y por eso entran mas", () => {
    // Limite 2: un activo (1.0) + dos pausados (0.5+0.5) = 2.0 exacto.
    const links = [
      link({ id: "act", acceptedAtMs: 100 }),
      link({ id: "pau1", status: "paused", acceptedAtMs: 200 }),
      link({ id: "pau2", status: "paused", acceptedAtMs: 300 }),
      link({ id: "sobra", acceptedAtMs: 900 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.block).toEqual(["sobra"]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("ignora terminated y pending (no pesan, no se bloquean)", () => {
    const links = [
      link({ id: "term", status: "terminated", acceptedAtMs: 100 }),
      link({ id: "pend", status: "pending", acceptedAtMs: 200 }),
      link({ id: "act", acceptedAtMs: 900 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.block).toEqual([]);
    expect(r.blockedAthleteIds).toEqual([]);
  });

  it("dedupea por atleta: dos vinculos al mismo alumno cuentan una vez", () => {
    // Mismo criterio que computeWeightedLoad — si no, un alumno con un vinculo
    // duplicado consumiria doble cupo y bloquearia a otro sin motivo.
    const links = [
      link({ id: "d1", athleteId: "mismo", acceptedAtMs: 100 }),
      link({ id: "d2", athleteId: "mismo", status: "paused", acceptedAtMs: 200 }),
      link({ id: "otro", athleteId: "otro", acceptedAtMs: 300 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
  });

  it("desempata por id cuando acceptedAt coincide (determinista)", () => {
    // Sin desempate estable, dos barridos consecutivos podrian bloquear a
    // personas distintas con los mismos datos.
    const links = [
      link({ id: "b", acceptedAtMs: 500 }),
      link({ id: "a", acceptedAtMs: 500 }),
      link({ id: "c", acceptedAtMs: 500 }),
    ];
    const r1 = reconcileEntitlements(links, 1);
    const r2 = reconcileEntitlements([...links].reverse(), 1);
    expect(r1.block).toEqual(r2.block);
    expect(r1.blockedAthleteIds).toEqual(r2.blockedAthleteIds);
  });

  it("un vinculo sin acceptedAt cae PRIMERO: es un defecto de datos, no antiguedad", () => {
    // Con "se conservan los mas antiguos", tratar el faltante como muy viejo lo
    // volveria el MAS protegido de todos — un bug de escritura convertido en
    // cupo garantizado. Cae antes incluso que el vinculo mas nuevo legitimo.
    const links = [
      link({ id: "sinFecha", acceptedAtMs: null }),
      link({ id: "viejo", acceptedAtMs: 100 }),
      link({ id: "nuevo", acceptedAtMs: 9000 }),
    ];
    expect(reconcileEntitlements(links, 2).block).toEqual(["sinFecha"]);
  });
});

// ---------------------------------------------------------------------------
// Reconciliacion en DOS direcciones.
//
// Bloquear solo no alcanza: un PF que vuelve a pagar recupera cupo, y si nadie
// restaura los vinculos queda roto para siempre. La CF necesita saber tanto a
// quien bloquear como a quien devolver.
// ---------------------------------------------------------------------------

describe("reconcileEntitlements — devolucion", () => {
  it("con cupo de sobra devuelve a los bloqueados", () => {
    const links = [
      link({ id: "act", acceptedAtMs: 900 }),
      link({ id: "bloq", entitlement: "blocked", acceptedAtMs: 800 }),
    ];
    const r = reconcileEntitlements(links, 7);
    expect(r.unblock).toEqual(["bloq"]);
    expect(r.block).toEqual([]);
    expect(r.blockedAthleteIds).toEqual([]);
  });

  it("devuelve solo lo que entra: los mas ANTIGUOS primero", () => {
    // Limite 2, un activo viejo (1.0) + tres bloqueados. Entra uno solo, y es
    // el mas antiguo de los tres.
    const links = [
      link({ id: "act", acceptedAtMs: 100 }),
      link({ id: "b_viejo", entitlement: "blocked", acceptedAtMs: 200 }),
      link({ id: "b_medio", entitlement: "blocked", acceptedAtMs: 500 }),
      link({ id: "b_nuevo", entitlement: "blocked", acceptedAtMs: 800 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.unblock).toEqual(["b_viejo"]);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
    expect(r.blockedAthleteIds).toEqual(["a-b_medio", "a-b_nuevo"]);
  });

  it("estado estable no produce escrituras (idempotente)", () => {
    // Si el barrido diario reporta cambios sobre un estado ya correcto,
    // escribe todos los dias lo mismo y ensucia el historial.
    const links = [
      link({ id: "act", acceptedAtMs: 100 }),
      link({ id: "act2", acceptedAtMs: 200 }),
      link({ id: "bloq", entitlement: "blocked", acceptedAtMs: 900 }),
    ];
    const r = reconcileEntitlements(links, 2);
    expect(r.block).toEqual([]);
    expect(r.unblock).toEqual([]);
    // Aunque no haya delta, el estado resultante sigue nombrando al bloqueado.
    expect(r.blockedAthleteIds).toEqual(["a-bloq"]);
  });

  it("bloquea y desbloquea en la misma pasada si hace falta", () => {
    // Limite 1. El bloqueado es MAS antiguo que el activo: hay que devolver el
    // bloqueado y bloquear al activo nuevo.
    const links = [
      link({ id: "nuevo_activo", acceptedAtMs: 900 }),
      link({ id: "viejo_bloq", entitlement: "blocked", acceptedAtMs: 100 }),
    ];
    const r = reconcileEntitlements(links, 1);
    expect(r.unblock).toEqual(["viejo_bloq"]);
    expect(r.block).toEqual(["nuevo_activo"]);
    expect(r.blockedAthleteIds).toEqual(["a-nuevo_activo"]);
  });

  it("terminated bloqueado no se devuelve (ya no es alumno)", () => {
    const links = [
      link({ id: "term", status: "terminated", entitlement: "blocked", acceptedAtMs: 900 }),
    ];
    const r = reconcileEntitlements(links, 7);
    expect(r.unblock).toEqual([]);
    expect(r.block).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// `blockedAthleteIds` — la lista denormalizada que va a
// `users/{trainerId}`.
//
// INERTE hoy: ninguna clausula de firestore.rules la lee. Se escribe ahora
// para que el dato exista y sea correcto ANTES de que algo dependa de el —
// justamente porque la forma ingenua de derivarla se rompe en silencio.
// ---------------------------------------------------------------------------

describe("blockedAthleteIds", () => {
  it("es el estado RESULTANTE, no el delta", () => {
    // Limite 1: entra el mas viejo. `B` se bloquea recien ahora y `C` ya venia
    // bloqueado — `block` tiene uno solo, la lista tiene los dos.
    const links = [
      link({ id: "A", athleteId: "a1", acceptedAtMs: 100 }),
      link({ id: "B", athleteId: "a2", acceptedAtMs: 200 }),
      link({ id: "C", athleteId: "a3", entitlement: "blocked", acceptedAtMs: 300 }),
    ];
    const r = reconcileEntitlements(links, 1);
    expect(r.block).toEqual(["B"]);
    expect(r.unblock).toEqual([]);
    expect(r.blockedAthleteIds).toEqual(["a2", "a3"]);
  });

  it("un atleta con un link terminated+blocked y otro activo NO queda en la lista", () => {
    // ESTE es el caso que mata la forma ingenua
    // (`links.filter(l => l.entitlement === "blocked")`). `reconcileEntitlements`
    // solo considera candidatos active|paused, asi que el `entitlement` de un
    // terminated queda PETRIFICADO: nunca vuelve a evaluarse. Derivando de ahi,
    // un alumno que se re-vincula quedaria bloqueado PARA SIEMPRE y ningun
    // barrido lo arreglaria, porque el valor seria "correcto" segun la formula.
    const links = [
      link({
        id: "viejo",
        athleteId: "vuelve",
        status: "terminated",
        entitlement: "blocked",
        acceptedAtMs: 100,
      }),
      link({ id: "nuevo", athleteId: "vuelve", acceptedAtMs: 900 }),
    ];
    const r = reconcileEntitlements(links, 7);
    expect(r.blockedAthleteIds).toEqual([]);
    expect(r.block).toEqual([]);
    expect(r.unblock).toEqual([]);
  });

  it("nombra a cada atleta una sola vez Y bloquea TODOS sus vinculos", () => {
    // La lista es un SET de personas, no de vinculos: si un atleta apareciera
    // dos veces, cualquier lector futuro contaria mal.
    //
    // La segunda mitad no es adorno: nombrar a a2 en la lista OBLIGA a que
    // ninguno de sus vinculos vivos quede `entitled`. Esta assertion faltaba y
    // dejaba pasar el estado incoherente — a2 publicado como bloqueado
    // mientras `dup2` seguia entitled y contando 0.5 de cupo.
    const links = [
      link({ id: "entra", athleteId: "a1", acceptedAtMs: 50 }),
      link({ id: "dup1", athleteId: "a2", acceptedAtMs: 100 }),
      link({ id: "dup2", athleteId: "a2", status: "paused", acceptedAtMs: 200 }),
    ];
    const r = reconcileEntitlements(links, 1);
    expect(r.blockedAthleteIds).toEqual(["a2"]);
    expect(r.block).toEqual(["dup1", "dup2"]);
    expect(carga(aplicar(links, r))).toBe(r.keptLoad);
  });

  it("sale ordenado: es un set, y una forma canonica evita diffs falsos", () => {
    const links = [
      link({ id: "L1", athleteId: "zzz", acceptedAtMs: 100 }),
      link({ id: "L2", athleteId: "aaa", acceptedAtMs: 200 }),
      link({ id: "L3", athleteId: "mmm", acceptedAtMs: 300 }),
    ];
    const r = reconcileEntitlements(links, 0);
    expect(r.blockedAthleteIds).toEqual(["aaa", "mmm", "zzz"]);
  });
});

// ---------------------------------------------------------------------------
// Plan 3 — sin limite (`limit: null`).
//
// El tipo obliga a contemplarlo en cada comparacion; estos tests pinean que la
// decision sea "no bloquear nunca" y no un accidente de como se compara null.
// ---------------------------------------------------------------------------

describe("limite nulo (plan3, ilimitado)", () => {
  it("no bloquea a nadie, por muchos que haya", () => {
    const links = Array.from({ length: 40 }, (_, i) =>
      link({ id: `L${i}`, athleteId: `a${i}`, acceptedAtMs: 1000 + i }));
    const r = reconcileEntitlements(links, null);
    expect(r.block).toEqual([]);
    expect(r.keptLoad).toBe(40);
    expect(r.blockedAthleteIds).toEqual([]);
  });

  it("DEVUELVE a todos los bloqueados al subir a plan3", () => {
    // Alguien que estaba en Free con 3 bloqueados y compra el ilimitado: los
    // recupera a todos de una.
    const links = [
      link({ id: "ok1", athleteId: "a1", acceptedAtMs: 900 }),
      link({ id: "b1", athleteId: "a2", entitlement: "blocked", acceptedAtMs: 800 }),
      link({ id: "b2", athleteId: "a3", entitlement: "blocked", acceptedAtMs: 700 }),
      link({ id: "b3", athleteId: "a4", entitlement: "blocked", acceptedAtMs: 600 }),
    ];
    const r = reconcileEntitlements(links, null);
    expect(r.unblock.sort()).toEqual(["b1", "b2", "b3"]);
    expect(r.block).toEqual([]);
    expect(r.blockedAthleteIds).toEqual([]);
  });

  it("con plan3 y nada bloqueado no genera escrituras", () => {
    const links = [
      link({ id: "a", athleteId: "a1" }),
      link({ id: "b", athleteId: "a2" }),
    ];
    const r = reconcileEntitlements(links, null);
    expect(r.block).toEqual([]);
    expect(r.unblock).toEqual([]);
  });

  it("limite 0 NO es lo mismo que ilimitado", () => {
    // Guarda contra el bug clasico: si alguien reemplaza el chequeo de null
    // por un falsy (!limit), el 0 pasaria como ilimitado y nadie se bloquearia.
    const links = [link({ id: "L1", athleteId: "a1" })];
    expect(reconcileEntitlements(links, 0).block).toEqual(["L1"]);
    expect(reconcileEntitlements(links, 0).blockedAthleteIds).toEqual(["a1"]);
    expect(reconcileEntitlements(links, null).block).toEqual([]);
    expect(reconcileEntitlements(links, null).blockedAthleteIds).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// UN ATLETA CON VARIOS VINCULOS VIVOS.
//
// `trainer_link_repository.dart` crea con id autogenerado y no impide que un
// mismo alumno pida dos veces, asi que el duplicado es alcanzable desde el
// cliente. Es la zona donde "decidir por vinculo" y "publicar por atleta" se
// separan, y donde estaba el punto fijo roto que este bloque pinea.
// ---------------------------------------------------------------------------

describe("un atleta con varios vinculos vivos", () => {
  it("un vinculo YA bloqueado no tapa al hermano entitled del mismo atleta", () => {
    // EL BUG QUE CIERRA: agrupando por "el vinculo mas pesado" el
    // representante de aX era `LB` (active), que ya estaba bloqueado, asi que
    // el diff salia VACIO — y `LP` (paused, entitled) seguia contando 0.5.
    // Resultado: carga 2.5 con limite 2, en cada corrida, para siempre, sin
    // nada que escribir para arreglarlo. Y `blockedAthleteIds` nombraba a aX
    // mientras su unico vinculo vivo decia `entitled`: la friccion se la comia
    // el ALUMNO por un estado que su vinculo nunca declaro.
    const links = [
      link({ id: "LY", athleteId: "aY", acceptedAtMs: 100 }),
      link({ id: "LZ", athleteId: "aZ", acceptedAtMs: 150 }),
      link({ id: "LB", athleteId: "aX", entitlement: "blocked", acceptedAtMs: 300 }),
      link({ id: "LP", athleteId: "aX", status: "paused", acceptedAtMs: 400 }),
    ];
    const r = reconcileEntitlements(links, 2);

    expect(r.blockedAthleteIds).toEqual(["aX"]);
    // `LB` no aparece: ya estaba. `LP` si — es el que faltaba escribir.
    expect(r.block).toEqual(["LP"]);
    expect(r.unblock).toEqual([]);
    expect(r.keptLoad).toBe(2.0);
    expect(carga(aplicar(links, r))).toBe(2.0);
  });

  it("el estado que deja es un punto fijo CORRECTO: la segunda corrida no cambia nada", () => {
    // Un punto fijo por si solo no prueba nada — el bug tambien era estable.
    // Lo que se pinea es que el punto fijo CUMPLA el limite.
    const links = [
      link({ id: "LY", athleteId: "aY", acceptedAtMs: 100 }),
      link({ id: "LZ", athleteId: "aZ", acceptedAtMs: 150 }),
      link({ id: "LB", athleteId: "aX", entitlement: "blocked", acceptedAtMs: 300 }),
      link({ id: "LP", athleteId: "aX", status: "paused", acceptedAtMs: 400 }),
    ];
    const despues = aplicar(links, reconcileEntitlements(links, 2));
    const segunda = reconcileEntitlements(despues, 2);

    expect(segunda.block).toEqual([]);
    expect(segunda.unblock).toEqual([]);
    expect(segunda.blockedAthleteIds).toEqual(["aX"]);
    expect(carga(despues)).toBe(2.0);
  });

  it("el resultado NO depende del orden de entrada, ni con vinculos de PESO IGUAL", () => {
    // El agrupado se queda con "el mas pesado", y con `>` estricto dos activos
    // del mismo atleta empatan: ganaba el que Firestore hubiera devuelto
    // primero. La query no lleva `orderBy`, asi que eso era azar del backend
    // decidiendo a quien se le corta. Los tres agregados de ahora (max de
    // peso, min de antiguedad, min de id) son conmutativos.
    const links = [
      link({ id: "L1", athleteId: "aX", entitlement: "blocked", acceptedAtMs: 300 }),
      link({ id: "L2", athleteId: "aX", acceptedAtMs: 400 }),
      link({ id: "LY", athleteId: "aY", acceptedAtMs: 100 }),
    ];
    const directo = reconcileEntitlements(links, 1);
    const alReves = reconcileEntitlements([...links].reverse(), 1);

    expect(alReves).toEqual(directo);
    expect(directo.block).toEqual(["L2"]);
    expect(directo.blockedAthleteIds).toEqual(["aX"]);
    expect(carga(aplicar(links, directo))).toBe(directo.keptLoad);
  });

  it("al recuperar cupo devuelve TODOS los vinculos del atleta, no uno", () => {
    const links = [
      link({ id: "LB1", athleteId: "aX", entitlement: "blocked", acceptedAtMs: 100 }),
      link({
        id: "LB2",
        athleteId: "aX",
        status: "paused",
        entitlement: "blocked",
        acceptedAtMs: 200,
      }),
    ];
    const r = reconcileEntitlements(links, 7);

    expect(r.unblock).toEqual(["LB1", "LB2"]);
    expect(r.blockedAthleteIds).toEqual([]);
    expect(carga(aplicar(links, r))).toBe(r.keptLoad);
  });

  it("el desempate por id tambien es conmutativo cuando el atleta tiene varios vinculos", () => {
    // Con la antiguedad empatada decide el id, y el id del ATLETA es el menor
    // de sus vinculos. Si en vez del menor se tomara "el ultimo que llego",
    // volveria a entrar el orden de la query por la ventana de al lado.
    const links = [
      link({ id: "z1", athleteId: "aX", acceptedAtMs: 500 }),
      link({ id: "a2", athleteId: "aX", status: "paused", acceptedAtMs: 500 }),
      link({ id: "m1", athleteId: "aY", acceptedAtMs: 500 }),
    ];
    const directo = reconcileEntitlements(links, 1);
    const alReves = reconcileEntitlements([...links].reverse(), 1);

    expect(alReves).toEqual(directo);
    // "a2" < "m1": aX tiene prioridad y aY es el que cae.
    expect(directo.blockedAthleteIds).toEqual(["aY"]);
  });

  it("un vinculo duplicado NUEVO no rejuvenece al atleta", () => {
    // La antiguedad es de la RELACION, no del papel. Si contara el vinculo mas
    // nuevo, pedir un segundo vinculo — cosa que la app permite — empujaria al
    // alumno al final de la cola y lo haria caer antes. Castigar al que usa la
    // app es exactamente la friccion que la politica no admite.
    const links = [
      link({ id: "viejo", athleteId: "aX", acceptedAtMs: 100 }),
      link({ id: "reciente", athleteId: "aX", status: "paused", acceptedAtMs: 9000 }),
      link({ id: "otro", athleteId: "aY", acceptedAtMs: 500 }),
    ];
    const r = reconcileEntitlements(links, 1);

    expect(r.blockedAthleteIds).toEqual(["aY"]);
    expect(r.block).toEqual(["otro"]);
  });

  it("un solo vinculo sin acceptedAt no le borra la antiguedad al atleta", () => {
    // El faltante entra como +Infinity al `min`, asi que solo decide cuando
    // NINGUN vinculo del atleta tiene fecha. Un defecto de datos parcial no
    // puede tapar la antiguedad que si esta documentada al lado.
    const links = [
      link({ id: "conFecha", athleteId: "aX", acceptedAtMs: 100 }),
      link({ id: "sinFecha", athleteId: "aX", status: "paused", acceptedAtMs: null }),
      link({ id: "otro", athleteId: "aY", acceptedAtMs: 500 }),
    ];
    const r = reconcileEntitlements(links, 1);

    expect(r.blockedAthleteIds).toEqual(["aY"]);
  });
});

// ---------------------------------------------------------------------------
// LA COLA DEL CUPO.
//
// El recorrido no corta en el primer desborde. Es una decision, no un
// descuido, y hay que poder explicarla en la pantalla de eleccion.
// ---------------------------------------------------------------------------

describe("la cola del cupo", () => {
  it("no corta en el primer desborde: un pausado POSTERIOR ocupa el medio cupo libre", () => {
    // Limite 2 con P(0.5) A(1.0) A(1.0) P(0.5) por antiguedad: entran el 1 y
    // el 2 (1.5), el 3 desborda (2.5) y el 4 entra clavado (2.0). O sea que
    // sobrevive un vinculo MAS NUEVO que uno bloqueado — la lectura literal de
    // "se conservan los mas antiguos" no alcanza para describirlo.
    //
    // Se elige asi sobre cortar en el primer desborde porque cortar bloquearia
    // a DOS alumnos en vez de a uno para respetar la prolijidad del enunciado.
    // La friccion la come el entrenador, no el alumno.
    const links = [
      link({ id: "P1", athleteId: "a1", status: "paused", acceptedAtMs: 100 }),
      link({ id: "A2", athleteId: "a2", acceptedAtMs: 200 }),
      link({ id: "A3", athleteId: "a3", acceptedAtMs: 300 }),
      link({ id: "P4", athleteId: "a4", status: "paused", acceptedAtMs: 400 }),
    ];
    const r = reconcileEntitlements(links, 2);

    expect(r.block).toEqual(["A3"]);
    expect(r.blockedAthleteIds).toEqual(["a3"]);
    expect(r.keptLoad).toBe(2.0);
    expect(carga(aplicar(links, r))).toBe(2.0);
  });
});

// ---------------------------------------------------------------------------
// INVARIANTE CRUZADA con `weighted-load.ts`.
//
// `keptLoad` es lo que la decision CREE que va a pesar el PF;
// `computeWeightedLoad` es lo que el sistema mide despues de escribir. Que se
// separen es el modo de falla mas caro de este modulo: deja al PF por encima
// de su limite sin nada que reconciliar. Ningun test lo miraba.
// ---------------------------------------------------------------------------

describe("keptLoad === carga real del estado resultante", () => {
  const casos: Array<[string, BlockableLink[], number | null]> = [
    ["duplicado blocked+entitled del mismo atleta", [
      link({ id: "LY", athleteId: "aY", acceptedAtMs: 100 }),
      link({ id: "LB", athleteId: "aX", entitlement: "blocked", acceptedAtMs: 300 }),
      link({ id: "LP", athleteId: "aX", status: "paused", acceptedAtMs: 400 }),
    ], 1],
    ["dos activos duplicados del mismo atleta", [
      link({ id: "L1", athleteId: "aX", acceptedAtMs: 300 }),
      link({ id: "L2", athleteId: "aX", acceptedAtMs: 400 }),
      link({ id: "LY", athleteId: "aY", acceptedAtMs: 100 }),
    ], 1],
    ["mezcla de terminated, pending y pausados", [
      link({ id: "T", athleteId: "a1", status: "terminated", entitlement: "blocked", acceptedAtMs: 50 }),
      link({ id: "N", athleteId: "a1", acceptedAtMs: 60 }),
      link({ id: "PE", athleteId: "a2", status: "pending", acceptedAtMs: 70 }),
      link({ id: "PA", athleteId: "a3", status: "paused", acceptedAtMs: 80 }),
      link({ id: "AC", athleteId: "a4", acceptedAtMs: 90 }),
    ], 2],
    ["plan3 con bloqueados de un plan anterior", [
      link({ id: "B1", athleteId: "a1", entitlement: "blocked", acceptedAtMs: 100 }),
      link({ id: "B2", athleteId: "a2", status: "paused", entitlement: "blocked", acceptedAtMs: 200 }),
      link({ id: "OK", athleteId: "a3", acceptedAtMs: 300 }),
    ], null],
    ["limite 0: no queda nadie", [
      link({ id: "L1", athleteId: "a1", acceptedAtMs: 100 }),
      link({ id: "L2", athleteId: "a1", status: "paused", acceptedAtMs: 200 }),
    ], 0],
  ];

  it.each(casos)("%s", (_nombre, links, limite) => {
    const r = reconcileEntitlements(links, limite);
    expect(carga(aplicar(links, r))).toBe(r.keptLoad);
  });
});
