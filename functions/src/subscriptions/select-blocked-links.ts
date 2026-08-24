/**
 * select-blocked-links.ts — decide QUIENES quedan bloqueados cuando un PF
 * queda por encima de su limite efectivo (paywall Fase 7, downgrade).
 *
 * Pura: sin Firestore, sin reloj, sin efectos. La CF que la usa se encarga de
 * leer, escribir y transaccionar; aca solo vive la decision, que es la parte
 * que tiene reglas de negocio y bordes.
 *
 * QUE SIGNIFICA BLOQUEADO HOY: el vinculo deja de contar para el limite del
 * PF. Nada mas — ninguna clausula de firestore.rules AUTORIZA nada en funcion
 * de `entitlement`. Ojo con la precision, porque el campo SI figura en el
 * archivo: firestore.rules ~:570 lo pinnea como CF-write-only (`get('entitlement',
 * null) == resource.data.get('entitlement', null)`), que es una restriccion de
 * ESCRITURA sobre el propio campo, no un gate sobre datos del alumno.
 * `blockedAthleteIds` todavia no figura en absoluto. El enforcement del lado
 * del PF llega en un slice posterior. **El alumno NO pierde nada en ningun caso**:
 * conserva rutinas, historial y chat. La presion va sobre quien paga, no sobre
 * quien no decide.
 *
 * LA UNIDAD DE DECISION ES EL ATLETA, NO EL VINCULO. El limite se mide sobre
 * personas deduplicadas (`weighted-load.ts`) y `blockedAthleteIds` publica
 * personas, asi que decidir por vinculo dejaba las tres cifras peleadas entre
 * si. Ver `reconcileEntitlements`.
 *
 * CRITERIO: la PRIORIDAD para conservar es la antiguedad — primero los mas
 * ANTIGUOS por `acceptedAt`. La antiguedad es la unica senal de vinculo que el
 * sistema tiene sin preguntarle a nadie, y romper la relacion mas vieja es la
 * que mas duele y la que peor se explica. Ojo con el matiz de la cola: el
 * recorrido NO corta en el primer desborde, ver `reconcileEntitlements`.
 * Este es el DEFAULT: la pantalla de eleccion (slice siguiente) deja que el PF
 * lo sobrescriba a mano.
 *
 * PENDIENTE PARA EL SLICE DE LA PANTALLA: hasta 2026-08 el criterio era el
 * INVERSO (conservar los mas recientes) y el lado Dart todavia lo documenta
 * asi — `keep_students_screen.dart` ("los mas recientemente activos —
 * resuelto server-side") y `paywall_preview_screen.dart`
 * (`initialSelection` con el comentario "default: 2 mas recientes"). Esos dos
 * comentarios son FALSOS desde el flip. No se tocan aca porque viven fuera de
 * `functions/`, pero el que cablee `initialSelection` contra el server tiene
 * que darlos vuelta o la pantalla va a pre-seleccionar exactamente el
 * complemento de lo que el backend eligio.
 */

export interface BlockableLink {
  id: string;
  athleteId: string;
  status: "pending" | "active" | "paused" | "terminated";
  entitlement?: "entitled" | "blocked";
  /** ms epoch. null/undefined ⇒ defecto de datos: cae PRIMERO, ver el sort. */
  acceptedAtMs?: number | null;
}

/** Mismos pesos que `weighted-load.ts` — si divergen, el gate y el downgrade
 * discrepan sobre quien entra. */
const STATUS_WEIGHT: Record<BlockableLink["status"], number> = {
  active: 1.0,
  paused: 0.5,
  pending: 0.0,
  terminated: 0.0,
};

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export interface EntitlementReconciliation {
  /** ids que pasan a `blocked`. */
  block: string[];
  /** ids que vuelven a `entitled`. */
  unblock: string[];
  /** carga ponderada resultante. */
  keptLoad: number;
  /**
   * athleteIds que quedan bloqueados DESPUES de aplicar `block` y `unblock`.
   * Estado resultante, no delta: es la lista denormalizada que va a
   * `users/{trainerId}.blockedAthleteIds`. Deduplicada y ordenada.
   *
   * INVARIANTE: un atleta esta aca si y solo si TODOS sus vinculos vivos
   * (active|paused) quedan en `blocked` despues de aplicar los dos diffs. No
   * hay estado intermedio "medio bloqueado" — ver el agrupado por atleta.
   */
  blockedAthleteIds: string[];
}

/** Un atleta y todos sus vinculos vivos, colapsados en un solo candidato. */
interface AthleteSlot {
  athleteId: string;
  /** TODOS sus vinculos active|paused, por id ascendente. */
  linkIds: string[];
  /** Subconjunto de `linkIds` que hoy ya dice `blocked`. */
  blockedNow: string[];
  /** Lo que aporta al limite si se lo conserva: su vinculo mas pesado. */
  weight: number;
  /** Antiguedad de la RELACION: el `acceptedAt` mas viejo con dato. */
  seniority: number;
  /** Menor id de vinculo — desempate total y estable entre atletas. */
  tieId: string;
}

/**
 * Reconciliacion en DOS direcciones: que bloquear y que devolver.
 *
 * Bloquear solo no alcanza. Un PF que vuelve a pagar recupera cupo, y sin
 * devolucion queda roto para siempre — con alumnos bloqueados que ya no
 * tendrian por que estarlo.
 *
 * Los ya bloqueados SI son candidatos: compiten por el cupo con todos los
 * demas segun el mismo criterio (mas antiguo primero). Si el estado ya es
 * correcto no devuelve nada, asi el barrido diario no escribe todos los dias
 * lo mismo.
 *
 * ## Por que se decide por ATLETA y se escriben TODOS sus vinculos
 *
 * Un mismo alumno puede tener mas de un vinculo vivo con el mismo PF
 * (`trainer_link_repository.dart` crea con id autogenerado y no impide el
 * duplicado). Colapsar el atleta a un vinculo "representante" y escribir solo
 * ese dejaba un punto fijo ROTO: con un representante `active+blocked` y un
 * hermano `paused+entitled`, el diff salia vacio en cada corrida (el
 * representante ya estaba bloqueado) mientras el hermano seguia contando
 * 0.5 en `computeWeightedLoad`. El PF quedaba por encima de su limite PARA
 * SIEMPRE y ningun barrido lo podia arreglar, porque no habia nada que
 * escribir. Peor: `blockedAthleteIds` nombraba al alumno mientras su unico
 * vinculo vivo decia `entitled` — o sea, el enforcement futuro le iba a
 * cobrar la friccion al ALUMNO por un estado que su vinculo nunca declaro.
 *
 * Decidiendo por atleta y aplicando la decision a TODOS sus vinculos vivos,
 * las tres cifras dejan de poder contradecirse:
 *   `keptLoad` === `computeWeightedLoad(estado resultante)`, y
 *   `blockedAthleteIds` === exactamente los atletas sin ningun vinculo vivo
 *   entitled.
 * Hay un test que pinea esa igualdad contra la funcion real de carga.
 */
export function reconcileEntitlements(
  links: BlockableLink[],
  limit: number | null,
): EntitlementReconciliation {
  // Agrupado por atleta. Los tres agregados (max de peso, min de antiguedad,
  // min de id) son CONMUTATIVOS a proposito: el resultado no puede depender
  // del orden en que Firestore devolvio los docs. La version anterior se
  // quedaba con "el primero de peso maximo", que con pesos empatados dejaba la
  // decision atada al orden de la query — sin `orderBy`, o sea al azar del
  // backend.
  const slots = new Map<string, AthleteSlot>();
  for (const l of links) {
    if (l.status !== "active" && l.status !== "paused") continue;

    let slot = slots.get(l.athleteId);
    if (!slot) {
      slot = {
        athleteId: l.athleteId,
        linkIds: [],
        blockedNow: [],
        weight: 0,
        seniority: Number.POSITIVE_INFINITY,
        tieId: l.id,
      };
      slots.set(l.athleteId, slot);
    }

    slot.linkIds.push(l.id);
    if (l.entitlement === "blocked") slot.blockedNow.push(l.id);

    // Peso: el mas pesado de sus vinculos vivos, sin mirar `entitlement`.
    // Es lo que el atleta va a pesar SI SE LO CONSERVA — y conservarlo
    // devuelve a `entitled` todos sus vinculos, asi que ninguno queda
    // filtrado por `computeWeightedLoad`.
    if (STATUS_WEIGHT[l.status] > slot.weight) slot.weight = STATUS_WEIGHT[l.status];

    // Antiguedad: la mas VIEJA de sus vinculos. La relacion empezo cuando
    // empezo; un vinculo duplicado creado despues no rejuvenece al alumno.
    // El faltante entra como +Infinity, asi que solo decide cuando NINGUN
    // vinculo del atleta tiene fecha — un defecto de datos parcial no le
    // borra la antiguedad que si esta documentada en otro vinculo.
    const t = l.acceptedAtMs ?? Number.POSITIVE_INFINITY;
    if (t < slot.seniority) slot.seniority = t;

    if (l.id.localeCompare(slot.tieId) < 0) slot.tieId = l.id;
  }

  for (const slot of slots.values()) {
    slot.linkIds.sort((a, b) => a.localeCompare(b));
    slot.blockedNow.sort((a, b) => a.localeCompare(b));
  }

  // Mas ANTIGUO primero: el primero que entro es el ultimo en caer.
  //
  // El faltante NO se trata como "muy antiguo". Un atleta sin ningun
  // `acceptedAt` es un DEFECTO DE DATOS, no evidencia de lealtad: darle el
  // puesto mas protegido convertiria un bug de escritura en un cupo
  // garantizado. Por eso +Infinity — en orden ascendente queda ULTIMO, o sea
  // que es el PRIMERO en bloquearse. (Es una clave de comparacion local,
  // nunca se serializa: el `null` de "sin limite" sigue siendo `null`.)
  //
  // Desempate por id para que dos barridos con los mismos datos elijan siempre
  // a las mismas personas. `tieId` es el menor id de vinculo del atleta, o sea
  // UNICO entre atletas: el orden es total, no parcial, y por eso no queda
  // ningun resquicio donde el orden de entrada decida.
  //
  // La guarda `!==` antes de restar evita el `Infinity - Infinity = NaN` que
  // dejaria el sort en manos del motor.
  const ordered = [...slots.values()].sort((a, b) => {
    if (a.seniority !== b.seniority) return a.seniority - b.seniority;
    return a.tieId.localeCompare(b.tieId);
  });

  // Recorrido codicioso que NO CORTA en el primer desborde: si un atleta no
  // entra se lo saltea y se sigue, asi un `paused` posterior (0.5) puede
  // ocupar el medio cupo que quedo libre.
  //
  // CONSECUENCIA, y hay que decirla porque contradice la lectura literal de
  // "se conservan los mas antiguos": en la cola puede sobrevivir un vinculo
  // MAS NUEVO que uno bloqueado. Con limite 2 y P(paused,t100) A(t200)
  // A(t300) P(paused,t400), el tercero cae y el cuarto se queda.
  //
  // Se elige a proposito sobre cortar en el primer desborde: cortar bloquearia
  // a MAS gente para respetar la prolijidad del enunciado, y la politica es
  // que la friccion la coma el entrenador, no el alumno. Entre "explicacion
  // mas simple" y "menos alumnos afectados" gana lo segundo. La pantalla de
  // eleccion tiene que explicarlo asi: prioridad por antiguedad, y despues se
  // termina de llenar el cupo con quien todavia entre.
  const kept = new Set<string>();
  let keptLoad = 0;
  for (const slot of ordered) {
    // limit === null ⇒ plan3, sin tope: todos quedan, y los que estaban
    // bloqueados de un plan anterior se devuelven.
    if (limit === null || round2(keptLoad + slot.weight) <= limit) {
      keptLoad = round2(keptLoad + slot.weight);
      kept.add(slot.athleteId);
    }
  }

  // Solo se reportan CAMBIOS: lo que ya esta en su estado correcto no genera
  // escritura. Sin esto, el barrido diario reescribiria los mismos campos
  // indefinidamente.
  //
  // La decision del atleta se aplica a TODOS sus vinculos vivos, no al
  // representante: es lo unico que hace que `blockedAthleteIds` no mienta y
  // que la carga resultante cierre. Ver el bloque de arriba.
  const block: string[] = [];
  const unblock: string[] = [];
  for (const slot of ordered) {
    if (kept.has(slot.athleteId)) {
      unblock.push(...slot.blockedNow);
    } else {
      const yaBloqueados = new Set(slot.blockedNow);
      block.push(...slot.linkIds.filter((id) => !yaBloqueados.has(id)));
    }
  }

  // `blockedAthleteIds` sale de `ordered`/`kept`, NO de filtrar los links por
  // `entitlement === "blocked"`.
  //
  // POR QUE IMPORTA: `ordered` ya esta filtrado a active|paused y agrupado por
  // atleta — el universo exacto que compite por el cupo. La forma ingenua
  // arrastraria los `terminated` con su `entitlement` viejo, y un
  // terminated+blocked nunca vuelve a ser candidato (lo filtra el agrupado de
  // arriba), asi que su valor queda PETRIFICADO. Con esa formula un alumno
  // que se re-vincula quedaria en la lista para siempre y ningun barrido lo
  // sacaria, porque el valor seria "correcto" segun la formula.
  //
  // Ordenado por athleteId: es un SET, y una forma canonica hace que el
  // documento no cambie cuando lo unico que cambio fue el orden de llegada.
  const blockedAthleteIds = ordered
    .filter((s) => !kept.has(s.athleteId))
    .map((s) => s.athleteId)
    .sort();

  return { block, unblock, keptLoad: round2(keptLoad), blockedAthleteIds };
}
