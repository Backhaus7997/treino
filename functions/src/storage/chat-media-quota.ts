/**
 * chat-media-quota.ts — el escritor de `users/{uid}.chatMediaUsage`, y la red
 * reactiva del tope de bytes de media de chat.
 *
 * Hermano de `custom-exercise-video-quota.ts`, y conviene leer aquel primero:
 * la ARQUITECTURA es la misma (regla preventiva + CF reactiva + gate de
 * cliente) y las tres diferencias de abajo son exactamente lo que cambia
 * cuando el prefijo deja de ser una biblioteca y pasa a ser un flujo.
 *
 * ─── Diferencia 1: el eje es BYTES, no cantidad ─────────────────────────────
 *
 * `customExerciseVideos` es una BIBLIOTECA: pocos archivos, se arma una vez, y
 * ahi `cantidad × por-archivo` acota el total — por eso su docstring descarta,
 * con razon, un tercer tope de MB totales.
 *
 * El chat es un FLUJO CONTINUO. Un PF con 30 alumnos manda cientos de archivos
 * por ano legitimamente: un tope de cantidad tendria que ser enorme para no
 * romperle el producto, y con la cantidad enorme el producto
 * `cantidad × por-archivo` deja de ser un techo util. El total en bytes si lo
 * es, y es lo unico que este modulo administra.
 *
 * Tampoco es «por chat», aunque sea la unidad que el path sugiere:
 * `firestore.rules` (~1973) tiene TRES ramas de creacion de chat —vinculo de
 * Coach, social direccional (REQ-FOLLOW-012) e inquiry (#637, cualquier atleta
 * a cualquier PF publicado)— asi que la cantidad de chats por usuario NO tiene
 * techo. N chats × tope-por-chat = sin techo.
 *
 * ─── Diferencia 2: el uid es el TERCER segmento, no el segundo ─────────────
 *
 * El path es `chatMedia/{chatId}/{uid}/{file=**}`, asi que **no existe un
 * prefijo unico que liste la media de un usuario**. Recontar obliga a enumerar
 * los chats del usuario primero (`chats where members array-contains uid`) y
 * listar `chatMedia/{chatId}/{uid}/` por cada uno. Es el MISMO camino que ya
 * usa el cascade de borrado de cuenta (`cascade/storage.ts`), y es correcto
 * porque `chats` nunca se borra: `firestore.rules` cierra su `allow delete` en
 * `false`, o sea que ningun chat con media puede volverse invisible para esta
 * enumeracion.
 *
 * El costo es N+1 llamadas por evento, con N = chats del usuario. Medido sobre
 * `treino-dev`: el maximo real es 10. La alternativa —listar `chatMedia/`
 * entero y filtrar— es O(toda la media del producto) por subida, que escala
 * al reves.
 *
 * ─── Diferencia 3: NO se borra por TAMANO, solo por TOTAL ──────────────────
 *
 * `decideQuota` de `custom-exercise-video-quota.ts` borra cualquier archivo con
 * `size >= maxBytes`. Copiar eso aca seria destructivo: el cap por video baja
 * de 100 MB a 50, y el bucket TIENE un MP4 de 90,31 MB del 18/06 en una
 * conversacion real. La primera subida de ese usuario despues del deploy
 * habria borrado el video de junio.
 *
 * Por eso **el cap por archivo es puramente preventivo y vive solo en
 * `storage.rules`**: gobierna lo que ENTRA. Este modulo gobierna el TOTAL, que
 * es una magnitud que no cambia de significado cuando se mueve el cap. Los
 * archivos que exceden el cap nuevo siguen contando sus bytes contra el total
 * —no se hacen los distraidos— pero no se los senala para borrar.
 *
 * Eso no deja ningun archivo legitimo huerfano: el cap por archivo (50 MB) es
 * dos ordenes de magnitud menor que el total (5 GB), asi que un solo archivo
 * jamas puede exceder el total por si mismo.
 *
 * ─── Que se conserva del original, y por que ───────────────────────────────
 *
 * · **Se RECUENTA en vez de incrementar.** Eventarc es at-least-once; un
 *   `FieldValue.increment()` se aplicaria dos veces en una redelivery y dejaria
 *   el contador desviado PARA SIEMPRE. Un contador de cuota desviado hacia
 *   abajo es un tope que no existe. Mismo criterio que `maintainReactionCounters`.
 *
 * · **Se conservan los MAS VIEJOS.** En el chat eso importa mas que alla: los
 *   mensajes son INMUTABLES (`firestore.rules`: `allow update, delete: if false`
 *   sobre `chats/{id}/messages`), asi que un objeto borrado deja el mensaje vivo
 *   con un `mediaUrl` muerto PARA SIEMPRE, sin forma de limpiarlo. Borrar del
 *   lado nuevo significa romper el bubble que el usuario acaba de mandar —que
 *   ve al instante— en vez de uno de hace seis meses, que no miraria nunca.
 *
 *   Lo que hace tolerable ese modo de falla es que los dos bubbles YA degradan:
 *   `errorWidget` en `chat_image_bubble.dart` y `_VideoErrorPlaceholder` en
 *   `firebase_storage_video_player.dart`. Un objeto ausente pinta un
 *   placeholder, no rompe la pantalla.
 *
 * · **Guarda anti-loop.** Este modulo escribe en `users/{uid}`, que disparan
 *   `syncEntitlementsOnSubscription` (compara solo `subscription`) y el trigger
 *   de `athletePaywallEnforced` (compara solo `athleteSubscription` + `role`).
 *   Esta escritura no toca ninguno de los tres. Si algun dia se le agrega un
 *   campo a este mapa, verifica que siga sin pisar esas entradas o el bucle
 *   factura sin parar. El ciclo propio —borrar dispara `onObjectDeleted`, que
 *   vuelve a reconciliar— termina en una vuelta: la segunda pasada ya esta
 *   dentro del tope, no borra nada, y el guard de «escribi solo si cambio» no
 *   escribe.
 *
 * ⚠️ Este modulo agrega el SEGUNDO par de triggers de Storage del proyecto, asi
 * que todo objeto del bucket invoca ahora dos funciones. Las dos cortan en la
 * primera linea si el prefijo no es el suyo (`uidFrom*ObjectName` devuelve
 * null), que es lo que mantiene barato el caso comun.
 *
 * ⚠️ Region us-east1, y es la EXCEPCION a ADR-PN-005 (todo lo demas vive en
 * southamerica-east1). No es una preferencia: un trigger de Storage DEBE estar
 * en la region del BUCKET o el deploy falla con
 * «A function in region X cannot listen to a bucket in region Y».
 *
 * `treino-dev.firebasestorage.app` esta en **US-EAST1** — medido contra la API
 * de GCS el 2026-09-15. `docs/roadmap.md` (Fase 1 Etapa 6) dice que el bucket
 * se creo en southamerica-east1 y **es falso**; de ahi lo copiaron estos dos
 * modulos y `docs/costos-storage.md`, y por eso el primer deploy se cayo.
 *
 * Si algun dia se migra el bucket, esta region se mueve con el. Verificalo
 * contra la API, no contra el roadmap.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import {
  onObjectDeleted,
  onObjectFinalized,
} from "firebase-functions/v2/storage";

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/** El prefijo que gobierna esta funcion. */
export const CHAT_MEDIA_PREFIX = "chatMedia/";

/** El campo que escribe este modulo, y nadie mas. */
export const CHAT_MEDIA_USAGE_FIELD = "chatMediaUsage";

/**
 * Los DOS topes de total. DEBEN espejar `athlete_entitlement.dart`
 * (`kFreeMaxChatMediaBytes`, `kMaxChatMediaBytes`) y los literales del
 * `chatMediaWriteAllowed()` de `storage.rules`. Los tres se mantienen a mano y
 * no hay nada que los sincronice.
 *
 * Los caps POR ARCHIVO (`kFreeMaxChatVideoBytes`, `kMaxChatVideoBytes`,
 * `kMaxChatImageBytes`) NO estan aca a proposito — ver la diferencia 3 del
 * encabezado. Viven en Dart y en `storage.rules`, y en ningun otro lado.
 *
 * Si esta copia fuera MAS PERMISIVA que la regla, la CF no borraria lo que la
 * regla ya reboto y no pasaria nada. Si fuera MAS ESTRICTA, borraria media que
 * la regla acepto: el usuario ve el mensaje enviado y el adjunto se convierte
 * en un placeholder solo. Ese es el modo de falla caro, y es mudo.
 */
export const FREE_MAX_CHAT_MEDIA_BYTES = 250 * 1024 * 1024;
export const MAX_CHAT_MEDIA_BYTES = 5 * 1024 * 1024 * 1024;

/**
 * El tope de total que le corresponde a un usuario.
 *
 * `enforced` sale de `users/{uid}.athletePaywallEnforced`, que ya cruza
 * suscripcion, vinculo activo Y ROL — `resolveAthletePaywallEnforced` corta en
 * `if (userData?.role !== "athlete") return false`. Eso importa mas aca que en
 * la videoteca: el chat es superficie COMPARTIDA de uso constante, y el tope
 * free tiene que dejar intacto el chat del Coach EN LAS DOS PUNTAS —el PF por
 * el rol, su alumno por el vinculo activo—.
 */
export function chatMediaCapFor(enforced: boolean): number {
  return enforced ? FREE_MAX_CHAT_MEDIA_BYTES : MAX_CHAT_MEDIA_BYTES;
}

/**
 * El uid dueno de un objeto de chat, o null si el path no es de este prefijo.
 *
 * El match de la regla es `chatMedia/{chatId}/{userId}/{file=**}`: el uid es el
 * SEGUNDO segmento despues del prefijo, no el primero como en
 * `customExerciseVideos/{userId}/...`. Confundirlos devuelve el chatId, y el
 * contador se escribiria en un doc de `users` que no existe — fallando en
 * silencio, que es la peor forma de fallar para un tope.
 *
 * Tiene que haber ALGO despues del uid: `chatMedia/{chatId}/{uid}/` a secas es
 * el marcador de carpeta que crea la consola, no un adjunto.
 */
export function uidFromChatObjectName(name: string | undefined): string | null {
  if (!name || !name.startsWith(CHAT_MEDIA_PREFIX)) return null;
  const parts = name.slice(CHAT_MEDIA_PREFIX.length).split("/");
  if (parts.length < 3) return null;
  const [chatId, uid] = parts;
  if (!chatId || !uid) return null;
  // `{file=**}` puede traer varios segmentos; lo que no puede es estar vacio.
  if (parts.slice(2).join("/") === "") return null;
  return uid;
}

export interface StoredMedia {
  name: string;
  size: number;
  createdAt: number;
}

export interface ChatQuotaDecision {
  keep: StoredMedia[];
  remove: StoredMedia[];
  bytes: number;
}

/**
 * Que se conserva y que sobra, dado el tope de bytes totales.
 *
 * Pura y exportada para poder testear la decision sin emulador ni bucket.
 *
 * **Corta en el primero que no entra y descarta todo lo que sigue**, en vez de
 * saltearlo y seguir buscando cual entra. Con [60, 50, 30] y un tope de 100, un
 * «mejor ajuste» conservaria el de 60 y el de 30 y borraria el de 50 — o sea
 * borraria algo del medio para quedarse con algo MAS NUEVO. Cortar en seco
 * conserva un prefijo temporal contiguo, que es lo que le promete al usuario un
 * chat: la conversacion vieja se queda entera, lo que no entro es lo ultimo que
 * mando.
 *
 * Tambien es lo que espeja exactamente a la regla, que autoriza con
 * `usage.bytes + size <= cap`: lo que la regla dejaria pasar es justo lo que
 * este acumulador conserva.
 *
 * Ordena por `createdAt` y desempata por nombre para que la decision sea
 * determinista — dos objetos del mismo milisegundo existen (una rafaga), y sin
 * desempate la redelivery podria borrar uno distinto cada vez.
 */
export function decideChatQuota(
  media: readonly StoredMedia[],
  maxBytes: number,
): ChatQuotaDecision {
  const sorted = [...media].sort(
    (a, b) => a.createdAt - b.createdAt || a.name.localeCompare(b.name),
  );

  const keep: StoredMedia[] = [];
  const remove: StoredMedia[] = [];
  let bytes = 0;
  let over = false;

  for (const m of sorted) {
    if (!over && bytes + m.size <= maxBytes) {
      keep.push(m);
      bytes += m.size;
    } else {
      over = true;
      remove.push(m);
    }
  }

  return { keep, remove, bytes };
}

export interface ChatReconcileResult {
  uid: string;
  bytes: number;
  count: number;
  chats: number;
  removed: string[];
  changed: boolean;
}

/**
 * Recuenta la media de chat de UN usuario, borra el excedente y deja el
 * contador al dia. Escribe solo si el valor cambia — segunda red contra el
 * bucle, y lo que hace barata la redelivery.
 */
export async function reconcileChatMediaQuota(
  app: App,
  uid: string,
): Promise<ChatReconcileResult> {
  const db = getFirestore(app);
  const userRef = db.collection("users").doc(uid);
  const bucket = getStorage(app).bucket();

  const [snap, chatsSnap] = await Promise.all([
    userRef.get(),
    db.collection("chats").where("members", "array-contains", uid).get(),
  ]);

  // Sin doc de perfil ⇒ no enforced, mismo default seguro que el fail-open de
  // `storage.rules` y de `paywallEnforcedFor` en `firestore.rules`. El techo
  // estructural sigue aplicando.
  const enforced = snap.exists && snap.get("athletePaywallEnforced") === true;

  // Un prefijo por chat: el uid es el TERCER segmento del path, asi que no hay
  // uno solo que los cubra a todos. Ver la diferencia 2 del encabezado.
  const perChat = await Promise.all(
    chatsSnap.docs.map(async (chat) => {
      const [files] = await bucket.getFiles({
        prefix: `${CHAT_MEDIA_PREFIX}${chat.id}/${uid}/`,
      });
      return files;
    }),
  );

  const media: StoredMedia[] = perChat
    .flat()
    // El filtro no es redundante con el prefijo: lo que descarta son los
    // marcadores de carpeta, que aparecen en el listado y pesan 0.
    .filter((f) => uidFromChatObjectName(f.name) === uid)
    .map((f) => ({
      name: f.name,
      size: Number(f.metadata?.size ?? 0),
      createdAt: Date.parse(String(f.metadata?.timeCreated ?? "")) || 0,
    }));

  const { keep, remove, bytes } = decideChatQuota(
    media,
    chatMediaCapFor(enforced),
  );

  for (const m of remove) {
    try {
      await bucket.file(m.name).delete();
      logger.warn("chatMediaQuota: objeto borrado por exceder el tope", {
        uid,
        object: m.name,
        size: m.size,
        enforced,
      });
    } catch (e) {
      // Borrado best-effort: un objeto que ya no esta (redelivery, o el cleanup
      // de huerfanos de `ChatMediaSendController` en el medio) no es un error.
      // Lo que NO se hace es abortar la reconciliacion — el contador tiene que
      // quedar al dia igual.
      logger.warn("chatMediaQuota: no se pudo borrar", {
        uid,
        object: m.name,
        error: String(e),
      });
    }
  }

  const usage = {
    bytes,
    count: keep.length,
    updatedAt: Date.now(),
  };

  const prev = snap.get(CHAT_MEDIA_USAGE_FIELD) as
    | { bytes?: number; count?: number }
    | undefined;
  // `updatedAt` se excluye de la comparacion a proposito: si entrara, cada
  // redelivery seria una escritura distinta y el guard no guardaria nada.
  const changed = prev?.bytes !== usage.bytes || prev?.count !== usage.count;

  // Sin doc de perfil no hay donde escribir, y crearlo desde aca seria acunar
  // un `users/{uid}` sin `role` ni `email` que despues nadie sabe de donde
  // salio. El contador aparece con el primer update real del perfil.
  if (changed && snap.exists) {
    await userRef.update({ [CHAT_MEDIA_USAGE_FIELD]: usage });
  }

  return {
    uid,
    bytes,
    count: keep.length,
    chats: chatsSnap.size,
    removed: remove.map((m) => m.name),
    changed,
  };
}

/** Handler compartido por los dos triggers. */
async function onChatMediaObjectEvent(
  objectName: string | undefined,
): Promise<void> {
  const uid = uidFromChatObjectName(objectName);
  if (uid === null) return; // otro prefijo, o el marcador de carpeta
  const r = await reconcileChatMediaQuota(ensureApp(), uid);
  logger.info("chatMediaQuota: reconciliado", r);
}

export const maintainChatMediaQuotaOnFinalize = onObjectFinalized(
  { region: "us-east1" },
  async (event) => {
    await onChatMediaObjectEvent(event.data.name);
  },
);

export const maintainChatMediaQuotaOnDelete = onObjectDeleted(
  { region: "us-east1" },
  async (event) => {
    await onChatMediaObjectEvent(event.data.name);
  },
);
