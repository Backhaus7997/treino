/**
 * Tests de las decisiones puras del tope de media de chat (#chat-media-quota).
 *
 * Cubre lo que se puede ejercitar sin emulador ni bucket: el parseo del path, la
 * resolucion del tier, y —lo que mas importa— QUE SE CONSERVA Y QUE SOBRA.
 *
 * Los numeros van escritos LITERALES en los asserts a proposito, igual que en
 * `custom-exercise-video-quota.test.ts`: si alguien mueve un tope sin querer,
 * esto tiene que dar rojo. Un test que lee la constante que esta testeando no
 * prueba el tope, prueba que la constante es igual a si misma.
 *
 * Lo que este archivo NO prueba es que la REGLA rebote la subida — eso es
 * `chat-media-storage-rules.test.ts`, contra el emulador.
 */

// PRIMERO, y no es cosmetico: el modulo bajo test registra triggers de Storage
// que resuelven el bucket al cargarse. Ver el encabezado del helper.
import "./helpers/storage-trigger-env";

import {
  CHAT_MEDIA_PREFIX,
  FREE_MAX_CHAT_MEDIA_BYTES,
  MAX_CHAT_MEDIA_BYTES,
  StoredMedia,
  chatMediaCapFor,
  decideChatQuota,
  uidFromChatObjectName,
} from "../storage/chat-media-quota";

const MB = 1024 * 1024;

/** Un objeto de media, con `createdAt` en milisegundos arbitrarios. */
function media(name: string, sizeMb: number, createdAt: number): StoredMedia {
  return { name, size: Math.round(sizeMb * MB), createdAt };
}

describe("uidFromChatObjectName", () => {
  // ⚠️ EL TEST QUE IMPORTA. El path es
  // `chatMedia/{chatId}/{uid}/{file=**}`: el uid es el SEGUNDO segmento
  // despues del prefijo, no el primero como en `customExerciseVideos/{uid}/`.
  // Devolver el chatId escribiria el contador en un doc de `users` que no
  // existe, y el tope entero fallaria en silencio.
  it("devuelve el SEGUNDO segmento (el uid), no el chatId", () => {
    expect(uidFromChatObjectName("chatMedia/uidA_uidB/uidA/foto.jpg")).toBe(
      "uidA",
    );
  });

  it("soporta un path anidado — el wildcard es {file=**}", () => {
    expect(
      uidFromChatObjectName("chatMedia/uidA_uidB/uidA/2026/09/clip.mp4"),
    ).toBe("uidA");
  });

  it("ignora otro prefijo del bucket", () => {
    expect(uidFromChatObjectName("customExerciseVideos/uidA/clip.mp4")).toBeNull();
    expect(uidFromChatObjectName("postPhotos/uidA/p.jpg")).toBeNull();
  });

  it("ignora el marcador de carpeta que crea la consola", () => {
    expect(uidFromChatObjectName("chatMedia/uidA_uidB/uidA/")).toBeNull();
    expect(uidFromChatObjectName("chatMedia/uidA_uidB/")).toBeNull();
    expect(uidFromChatObjectName(CHAT_MEDIA_PREFIX)).toBeNull();
  });

  it("ignora undefined y un path con segmentos vacios", () => {
    expect(uidFromChatObjectName(undefined)).toBeNull();
    expect(uidFromChatObjectName("chatMedia//uidA/foto.jpg")).toBeNull();
    expect(uidFromChatObjectName("chatMedia/uidA_uidB//foto.jpg")).toBeNull();
  });
});

describe("chatMediaCapFor", () => {
  it("da 250 MB al alumno enforced y 5 GB a todos los demas", () => {
    expect(chatMediaCapFor(true)).toBe(250 * MB);
    expect(chatMediaCapFor(false)).toBe(5 * 1024 * MB);
    // Espejo de `athlete_entitlement.dart` y de `storage.rules`.
    expect(FREE_MAX_CHAT_MEDIA_BYTES).toBe(250 * MB);
    expect(MAX_CHAT_MEDIA_BYTES).toBe(5 * 1024 * MB);
  });
});

describe("decideChatQuota", () => {
  it("no borra nada cuando el total entra en el tope", () => {
    const items = [media("a", 10, 1), media("b", 10, 2)];
    const d = decideChatQuota(items, 250 * MB);
    expect(d.remove).toEqual([]);
    expect(d.keep).toHaveLength(2);
    expect(d.bytes).toBe(20 * MB);
  });

  it("acepta el total EXACTAMENTE igual al tope", () => {
    // La regla autoriza con `usage.bytes + size <= cap`, asi que el objeto que
    // deja el total clavado en el tope es legal. Un `<` aca lo borraria y las
    // dos capas discreparian en el unico punto donde tienen que coincidir.
    const d = decideChatQuota([media("a", 100, 1), media("b", 150, 2)], 250 * MB);
    expect(d.remove).toEqual([]);
    expect(d.bytes).toBe(250 * MB);
  });

  it("borra el excedente conservando los MAS VIEJOS", () => {
    // Los viejos son los mensajes que el usuario ya mando y ve en su historia;
    // los nuevos son los que se colaron por la carrera de la rafaga. Y como los
    // mensajes son INMUTABLES, un objeto borrado deja un bubble roto para
    // siempre: mejor que sea el que acaba de mandar y no uno de hace meses.
    const items = [
      media("viejo", 100, 1000),
      media("medio", 100, 2000),
      media("nuevo", 100, 3000),
    ];
    const d = decideChatQuota(items, 250 * MB);
    expect(d.keep.map((m) => m.name)).toEqual(["viejo", "medio"]);
    expect(d.remove.map((m) => m.name)).toEqual(["nuevo"]);
    expect(d.bytes).toBe(200 * MB);
  });

  it("corta en el primero que no entra y descarta todo lo que sigue", () => {
    // Con [60, 50, 30] y tope 100, un «mejor ajuste» conservaria el de 60 y el
    // de 30 y borraria el del medio — o sea borraria algo VIEJO para quedarse
    // con algo MAS NUEVO. Cortar en seco conserva un prefijo temporal contiguo,
    // que es lo que un chat le promete al usuario.
    const items = [
      media("p1", 60, 1000),
      media("p2", 50, 2000),
      media("p3", 30, 3000),
    ];
    const d = decideChatQuota(items, 100 * MB);
    expect(d.keep.map((m) => m.name)).toEqual(["p1"]);
    expect(d.remove.map((m) => m.name)).toEqual(["p2", "p3"]);
  });

  it("ordena por fecha aunque lleguen desordenados del listado", () => {
    const items = [
      media("nuevo", 200, 3000),
      media("viejo", 100, 1000),
    ];
    const d = decideChatQuota(items, 250 * MB);
    expect(d.keep.map((m) => m.name)).toEqual(["viejo"]);
    expect(d.remove.map((m) => m.name)).toEqual(["nuevo"]);
  });

  it("desempata por nombre con el mismo createdAt", () => {
    // Dos objetos del mismo milisegundo existen (una rafaga). Sin desempate, la
    // redelivery de Eventarc podria borrar uno distinto en cada pasada.
    const a = decideChatQuota(
      [media("bbb", 150, 1000), media("aaa", 150, 1000)],
      250 * MB,
    );
    const b = decideChatQuota(
      [media("aaa", 150, 1000), media("bbb", 150, 1000)],
      250 * MB,
    );
    expect(a.keep.map((m) => m.name)).toEqual(["aaa"]);
    expect(b.keep.map((m) => m.name)).toEqual(["aaa"]);
  });

  // ⚠️ LA DIVERGENCIA DELIBERADA CON `custom-exercise-video-quota.ts`.
  //
  // Aquel `decideQuota` borra CUALQUIER archivo con `size >= maxBytes` del cap
  // POR ARCHIVO. Copiar eso aca seria destructivo: el cap por video baja de 100
  // a 50 MB y el bucket tiene un MP4 de 90,31 MB en una conversacion real de
  // junio — la primera subida de ese usuario despues del deploy lo habria
  // borrado.
  //
  // El cap por archivo es PURAMENTE PREVENTIVO y vive solo en `storage.rules`.
  // Este modulo administra el TOTAL, y nada mas.
  it("NO borra por tamano: un objeto sobre el cap por archivo se conserva", () => {
    const grande = media("legado-90mb.mp4", 90.31, 1000);
    const d = decideChatQuota([grande], 250 * MB);
    expect(d.remove).toEqual([]);
    expect(d.keep.map((m) => m.name)).toEqual(["legado-90mb.mp4"]);
  });

  it("cuenta los bytes del archivo de legado contra el total igual", () => {
    // No se lo señala para borrar, pero tampoco se hace el distraido: sus bytes
    // ocupan cupo como los de cualquier otro.
    const d = decideChatQuota(
      [media("legado-90mb.mp4", 200, 1000), media("nuevo.jpg", 100, 2000)],
      250 * MB,
    );
    expect(d.remove.map((m) => m.name)).toEqual(["nuevo.jpg"]);
    expect(d.bytes).toBe(200 * MB);
  });

  it("no se rompe con la lista vacia", () => {
    const d = decideChatQuota([], 250 * MB);
    expect(d).toEqual({ keep: [], remove: [], bytes: 0 });
  });
});
