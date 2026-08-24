/**
 * sync-entitlements.ts — escribe `entitlement` en los vinculos de un PF segun
 * su limite efectivo (paywall Fase 7, downgrade).
 *
 * EL AGUJERO QUE CIERRA: el gate de `syncTrainerLoad` impide ACEPTAR por
 * encima del limite, pero no hace nada con los que ya estaban adentro. Un PF
 * con 7 alumnos cuya suscripcion vence pasa a limite 2 y conserva los 7: el
 * limite queda decorativo para todo el que ya entro.
 *
 * QUE SIGNIFICA BLOQUEADO HOY: el vinculo deja de contar para el limite. Nada
 * mas — ninguna clausula de firestore.rules AUTORIZA nada en funcion de
 * `entitlement`. Con precision, porque el campo SI figura en el archivo:
 * firestore.rules ~:570 lo pinnea como CF-write-only, que restringe QUIEN
 * escribe ese campo y no gatea ningun dato del alumno. El enforcement del lado
 * del PF llega en un slice posterior.
 * **El alumno NO pierde nada en ningun caso**: conserva rutinas, historial y
 * chat. La presion va sobre quien paga.
 *
 * `blockedAthleteIds`: copia denormalizada en `users/{trainerId}` de QUE
 * ALUMNOS quedan bloqueados, para que el enforcement futuro no tenga que
 * consultar `trainer_links` desde firestore.rules. Hoy es INERTE: ninguna
 * clausula lo lee. Se escribe ya para que el dato exista y sea correcto ANTES
 * de que algo dependa de el.
 *
 * BLOQUEANTE PARA EL SLICE DE ENFORCEMENT — el campo NO ESTA PINNEADO EN
 * `firestore.rules`. La clausula `allow update` de `users/{uid}`
 * (firestore.rules ~84-99) es una conjuncion de pins campo por campo, SIN
 * `hasOnly`: pinea `uid`, `role`, `email`, `createdAt`, `subscription` y
 * `weightedLoad`, y su propio comentario dice que el duenio "can still freely
 * update every OTHER field on their own doc". `blockedAthleteIds` es uno de
 * esos otros, asi que hoy el PF puede hacer `update({blockedAthleteIds: []})`
 * desde el cliente — y esa escritura no toca el mapa `subscription`, o sea que
 * `subscriptionChanged` devuelve false y ningun trigger reconcilia: la mentira
 * vive hasta el barrido de las 04:00. Mientras el campo sea INERTE eso no
 * hace danio; el dia que una regla lo lea es un bypass del paywall de una sola
 * escritura. El pin es una linea calcada del idiom de al lado
 * (`request.resource.data.get('blockedAthleteIds', null) ==
 * resource.data.get('blockedAthleteIds', null)`) mas su `assertFails` en
 * users-subscription-rules.test.ts, y va a poner en rojo el inventario
 * congelado (§5) de rules-read-isolation.test.ts, que es exactamente para lo
 * que ese test existe. No se hace aca porque `firestore.rules` esta fuera de
 * este slice.
 *
 * DATOS DEGRADADOS: si `subscription` no se pudo leer bien, este barrido NO
 * bloquea a nadie — solo devuelve. Ver la valvula mas abajo y la POLITICA en
 * subscription-state.ts.
 *
 * Transaccional por el mismo motivo que `syncTrainerLoad`: lee
 * `users/{trainerId}` (necesita `subscription`) y escribe `weightedLoad` ahi
 * mismo, asi que ese par read-write serializa contra las promociones
 * concurrentes. Sin eso, un accept y un downgrade simultaneos podrian dejar la
 * carga inconsistente.
 */

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { effectiveWeightLimit } from "./effective-limit";
import { toSubscriptionState } from "./subscription-state";
import { computeWeightedLoad, WeightedLink } from "./weighted-load";
import { reconcileEntitlements, BlockableLink } from "./select-blocked-links";

/**
 * Lee los millis de un valor que DEBERIA ser un Timestamp, sin confiar en que
 * lo sea. Total: cualquier cosa que no sirva devuelve null.
 *
 * Existe porque `acceptedAt` es alcanzable desde el cliente — firestore.rules
 * no lo pinnea y el `allow update` de trainer_links autoriza a cualquiera de
 * los dos members — y una llamada a `.toMillis()` sobre un string tiraba
 * TypeError, volteaba la transaccion entera, y como los dos llamadores hacen
 * catch-and-log sin relanzar, ese PF dejaba de reconciliar para TODOS sus
 * alumnos.
 */
function readMillis(raw: unknown): number | null {
  if (raw == null) return null;
  const maybe = raw as { toMillis?: () => unknown };
  if (typeof maybe.toMillis !== "function") return null;
  const ms = maybe.toMillis();
  return typeof ms === "number" && Number.isFinite(ms) ? ms : null;
}

export interface SyncEntitlementsResult {
  trainerId: string;
  /** `null` = sin limite (plan3). */
  limit: number | null;
  /**
   * ids efectivamente bloqueados. Vacio cuando la `subscription` venia
   * degradada, aunque `limit` diga que sobran vinculos: ver la valvula.
   */
  blocked: string[];
  unblocked: string[];
  weightedLoad: number;
  /**
   * Estado resultante (no delta) de `users/{trainerId}.blockedAthleteIds`, tal
   * cual quedo escrito. En una corrida degradada NO incorpora a los salteados:
   * ver la valvula.
   */
  blockedAthleteIds: string[];
}

/**
 * Reconcilia `entitlement` para todos los vinculos de un PF.
 *
 * Idempotente EN `trainer_links`: si el estado ya es correcto los diffs salen
 * vacios y no se escribe un solo vinculo, asi el barrido diario no ensucia el
 * historial de los alumnos. El `tx.set` de `users/{trainerId}` NO es
 * condicional: corre siempre, con los mismos valores si nada cambio. Es una
 * escritura por corrida sobre UN documento, y `linkLoadReconcile` la dispara
 * en cada escritura de `trainer_links`; no genera loop porque la guarda
 * `subscriptionChanged` compara solo el mapa `subscription`, que este barrido
 * nunca toca.
 */
export async function syncTrainerEntitlements(
  app: admin.app.App,
  trainerId: string,
  nowMs?: number,
): Promise<SyncEntitlementsResult> {
  const db = admin.firestore(app);
  const clock = nowMs ?? Date.now();

  return db.runTransaction(async (tx) => {
    // Reads-before-writes: Firestore exige TODAS las lecturas antes de la
    // primera escritura.
    const [trainerSnap, linksSnap] = await Promise.all([
      tx.get(db.collection("users").doc(trainerId)),
      tx.get(db.collection("trainer_links").where("trainerId", "==", trainerId)),
    ]);

    const { state: sub, degraded } = toSubscriptionState(trainerSnap.data(), trainerId);
    const limit = effectiveWeightLimit(sub, clock);

    const rawLinks: BlockableLink[] = linksSnap.docs.map((doc) => {
      const d = doc.data() as admin.firestore.DocumentData;
      // `acceptedAt` tampoco puede ir con cast a ciegas, y es el PEOR de los
      // tres: firestore.rules NO lo pinnea (`rg -c acceptedAt firestore.rules`
      // da 0) y el `allow update` de trainer_links autoriza a CUALQUIERA de los
      // dos members. O sea que es alcanzable desde el cliente. Con
      // `acceptedAt.toMillis()` a secas, un member que escriba ahi un string
      // tira TypeError, la transaccion se cae ENTERA, y los dos llamadores
      // hacen catch-and-log sin relanzar: ese PF deja de reconciliar para
      // TODOS sus alumnos, no solo para el vinculo roto. Un miembro podia
      // voltearle el barrido al entrenador con un solo write.
      //
      // Degradar a null falla del lado correcto: `reconcileEntitlements` trata
      // el faltante como POSITIVE_INFINITY, o sea que el vinculo con la fecha
      // corrupta cae PRIMERO. El costo de romper el propio dato lo paga quien
      // lo rompio, y nadie mas.
      //
      // El pin en las reglas llega en el slice de pines. Esto no lo reemplaza:
      // el Admin SDK bypasea rules, asi que la lectura defensiva hace falta
      // igual.
      // El chequeo es por FORMA, no `instanceof admin.firestore.Timestamp`:
      // Firestore solo guarda primitivos, mapas, arrays, Timestamp, GeoPoint y
      // Reference, asi que un `toMillis` invocable no lo puede falsificar el
      // cliente — y `instanceof` ademas se rompe contra los dobles de test.
      const acceptedAt = d.acceptedAt;
      const acceptedAtMs = readMillis(acceptedAt);
      if (acceptedAt !== undefined && acceptedAtMs === null) {
        logger.warn("syncTrainerEntitlements: acceptedAt no es un Timestamp", {
          trainerId,
          linkId: doc.id,
          acceptedAtType: typeof acceptedAt,
        });
      }
      return {
        id: doc.id,
        // Sin cast a ciegas: ver el filtro de abajo.
        athleteId: typeof d.athleteId === "string" ? d.athleteId : "",
        status: d.status as BlockableLink["status"],
        entitlement: d.entitlement as BlockableLink["entitlement"],
        acceptedAtMs,
      };
    });

    // Un `trainer_link` sin `athleteId` es un documento roto, y desde que
    // existe `blockedAthleteIds` dejo de ser inofensivo: ese valor ya no se
    // queda en una clave de Map en memoria, viaja al array que se escribe en
    // `users/{trainerId}`. El Admin SDK rechaza `undefined` dentro de un
    // array, asi que UN documento defectuoso volteaba la transaccion ENTERA:
    // ni entitlements ni `weightedLoad` se escribian, los dos llamadores
    // hacen catch-and-log sin relanzar, y ese PF dejaba de reconciliar para
    // siempre con solo un warn en Cloud Logging. Desproporcionado.
    //
    // Se SALTEAN, no se coercionan: un `athleteId` vacio colapsaria todos los
    // links rotos en un mismo atleta fantasma y los haria competir por cupo.
    // Saltearlos los deja fuera de la carga y fuera de la lista — no hay
    // ninguna decision sensata que tomar sobre un vinculo sin duenio. El log
    // es `error` porque hay documentos concretos que arreglar a mano.
    //
    // Hoy `firestore.rules` (~511) exige `athleteId == request.auth.uid` en el
    // create y lo pinea inmutable, asi que por camino de cliente no se llega:
    // esto cubre docs legacy y escrituras Admin SDK.
    const links = rawLinks.filter((l) => l.athleteId !== "");
    if (links.length !== rawLinks.length) {
      logger.error(
        "sync-entitlements: trainer_links sin athleteId — se SALTEAN",
        {
          trainerId,
          skippedLinkIds: rawLinks
            .filter((l) => l.athleteId === "")
            .map((l) => l.id),
        },
      );
    }

    const { block, unblock, blockedAthleteIds } = reconcileEntitlements(
      links,
      limit,
    );

    // ── VALVULA DE DEGRADACION ────────────────────────────────────────────
    //
    // POLITICA (definida en subscription-state.ts): la degradacion de datos
    // frena TRABAJO NUEVO (friccion sobre el entrenador) pero NUNCA revoca
    // relaciones existentes (friccion sobre el alumno).
    //
    // El barrido es el lado "no revoca". Si el mapa `subscription` no se
    // entendio, el `limit` que llego aca no sale de lo que el PF pago: sale del
    // fallback conservador. Bloquear con ese numero significa cortarle el
    // servicio a los alumnos de un PF que capaz pago plan3, por un typo
    // NUESTRO. `unblock` SI corre — devolver nunca puede empeorar la situacion
    // de un alumno, y un PF con datos rotos no tiene por que quedarse ademas
    // con vinculos bloqueados de un downgrade anterior.
    //
    // Asimetrico contra el gate de promote-link.ts, que con el mismo flag sigue
    // denegando. Es la asimetria del enunciado, no una inconsistencia.
    const blockNow = degraded ? [] : block;
    if (degraded && block.length > 0) {
      // error y no warn: es accionable y hay UN documento que arreglar a mano.
      // Va con el uid y con los ids salteados porque sin eso no hay como saber
      // a quien se le esta perdonando el limite ni por cuanto tiempo.
      logger.error(
        "sync-entitlements: subscription degradada — se SALTEA el bloqueo",
        { trainerId, limit, skippedBlock: block, skippedCount: block.length },
      );
    }

    // La valvula manda tambien sobre `blockedAthleteIds`, y aca es donde es
    // mas facil equivocarse.
    //
    // Escribir la lista fresca en una corrida degradada seria bloquear por la
    // puerta de atras: ese campo existe para que el enforcement futuro lo lea,
    // asi que meter a alguien ahi va a valer lo mismo que ponerle
    // `entitlement: "blocked"` a su vinculo — y los vinculos de `block` son
    // justamente los que NO se tocaron. La valvula quedaria abierta de un lado
    // y cerrada del otro.
    //
    // Dejar el valor viejo tampoco sirve: `unblock` SI corrio, asi que la
    // lista vieja seguiria nombrando alumnos cuyo vinculo ya volvio a
    // `entitled`. La contradiccion caeria del lado que perjudica al alumno,
    // que es el unico lado que la politica no admite.
    //
    // La salida coherente con "frena trabajo nuevo, nunca revoca": la lista
    // puede PERDER miembros pero nunca GANARLOS. Se le restan los atletas de
    // los vinculos salteados; lo que queda son los que ya venian bloqueados y
    // siguen sin entrar — exactamente el estado en que quedaron sus
    // `trainer_links`, que es lo unico que el campo tiene derecho a espejar.
    //
    // La resta es EXACTA, y depende de que `reconcileEntitlements` decida por
    // atleta: si un atleta no entra, TODOS sus vinculos vivos van a `block`,
    // asi que saltearlo lo saca entero de la lista. No hay forma de que quede
    // nombrado con la mitad de sus vinculos sin tocar. La invariante que
    // sobrevive a la valvula es la misma de la corrida sana: un atleta figura
    // aca si y solo si NINGUN vinculo vivo suyo quedo `entitled`.
    const skippedLinkIds = new Set(degraded ? block : []);
    const skippedAthleteIds = new Set(
      links.filter((l) => skippedLinkIds.has(l.id)).map((l) => l.athleteId),
    );
    const blockedAthleteIdsNow = blockedAthleteIds.filter(
      (a) => !skippedAthleteIds.has(a),
    );

    // Carga resultante: se recalcula sobre el estado YA reconciliado, no sobre
    // el previo. Si se usara el previo, `weightedLoad` mostraria la carga vieja
    // hasta el proximo trigger. Con la valvula abierta esto refleja la carga
    // REAL (nadie fue bloqueado), que es justamente lo que hace visible el
    // documento roto: un weightedLoad por arriba del limite.
    const after: WeightedLink[] = links.map((l) => ({
      athleteId: l.athleteId,
      status: l.status,
      entitlement: blockNow.includes(l.id)
        ? "blocked"
        : unblock.includes(l.id)
          ? "entitled"
          : l.entitlement,
    })) as WeightedLink[];
    const weightedLoad = computeWeightedLoad(after);

    // ── frontera: writes ──────────────────────────────────────────────────
    for (const id of blockNow) {
      tx.update(db.collection("trainer_links").doc(id), {
        entitlement: "blocked",
        blockedAt: admin.firestore.Timestamp.fromMillis(clock),
        blockedReason: "over-limit",
      });
    }
    for (const id of unblock) {
      tx.update(db.collection("trainer_links").doc(id), {
        entitlement: "entitled",
        blockedAt: admin.firestore.FieldValue.delete(),
        blockedReason: admin.firestore.FieldValue.delete(),
      });
    }
    // `merge: true` con un array REEMPLAZA el array entero, que es justo lo
    // que se quiere: el campo describe un estado completo, no un incremento.
    // Cuando no queda nadie bloqueado se escribe `[]` y el valor viejo muere.
    tx.set(
      db.collection("users").doc(trainerId),
      { weightedLoad, blockedAthleteIds: blockedAthleteIdsNow },
      { merge: true },
    );

    return {
      trainerId,
      limit,
      blocked: blockNow,
      unblocked: unblock,
      weightedLoad,
      blockedAthleteIds: blockedAthleteIdsNow,
    };
  });
}
