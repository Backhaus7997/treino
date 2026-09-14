/**
 * Tests de la logica PURA del tope de videos de ejercicio custom.
 *
 * No tocan emulador ni bucket a proposito: lo que se ejercita aca es la
 * DECISION (que se conserva, que sobra, que topes aplican), que es donde viven
 * los errores caros. El cableado de los triggers y la lectura de
 * `athletePaywallEnforced` se cubren del lado de las reglas, en
 * `custom-exercise-videos-storage-rules.test.ts`.
 *
 * Los numeros estan escritos LITERALES en los asserts (25 MB, 3, 50) en vez de
 * importar las constantes. Es deliberado: un test que importa la constante que
 * el codigo usa pasa igual si alguien cambia la constante, y este archivo es
 * justamente el que tiene que gritar cuando un tope se mueve sin querer.
 */

// PRIMERO, y no es cosmetico: el modulo bajo test registra triggers de Storage
// que resuelven el bucket al cargarse. Ver el encabezado del helper.
import "./helpers/storage-trigger-env";

import {
  capsFor,
  decideQuota,
  uidFromObjectName,
  StoredVideo,
} from "../storage/custom-exercise-video-quota";

const MB = 1024 * 1024;

function vid(name: string, sizeMb: number, createdAt: number): StoredVideo {
  return { name, size: Math.round(sizeMb * MB), createdAt };
}

describe("uidFromObjectName", () => {
  it("saca el uid de un objeto en la raiz de la carpeta del usuario", () => {
    expect(uidFromObjectName("customExerciseVideos/abc123/clip.mp4")).toBe(
      "abc123",
    );
  });

  it("saca el uid de un objeto ANIDADO — el match es {file=**}", () => {
    expect(
      uidFromObjectName("customExerciseVideos/abc123/2026/07/clip.mp4"),
    ).toBe("abc123");
  });

  it("devuelve null para otro prefijo del bucket", () => {
    // Los dos triggers escuchan el bucket ENTERO: sin este corte, cada avatar
    // y cada foto de chat dispararian una reconciliacion de cuota.
    expect(uidFromObjectName("chatMedia/a_b/uid/foto.jpg")).toBeNull();
    expect(uidFromObjectName("avatars/abc123.jpg")).toBeNull();
  });

  it("devuelve null para el marcador de carpeta", () => {
    // La consola de Firebase crea objetos de cero bytes con el path terminado
    // en `/` al navegar. No son videos y no tienen que contar.
    expect(uidFromObjectName("customExerciseVideos/abc123/")).toBeNull();
    expect(uidFromObjectName("customExerciseVideos/")).toBeNull();
  });

  it("devuelve null para undefined", () => {
    expect(uidFromObjectName(undefined)).toBeNull();
  });
});

describe("capsFor", () => {
  it("aplica el tope free al alumno con el paywall aplicado", () => {
    expect(capsFor(true)).toEqual({ maxCount: 3, maxBytes: 25 * MB });
  });

  it("aplica el techo estructural a quien no lo tiene aplicado", () => {
    // El PF cae siempre aca: `resolveAthletePaywallEnforced` corta en
    // `role !== 'athlete'`. Tambien el alumno que paga y el vinculado.
    expect(capsFor(false)).toEqual({ maxCount: 50, maxBytes: 100 * MB });
  });
});

describe("decideQuota", () => {
  const freeCaps = { maxCount: 3, maxBytes: 25 * MB };

  it("no saca nada cuando esta dentro del tope", () => {
    const videos = [vid("a.mp4", 2, 100), vid("b.mp4", 3, 200)];
    const d = decideQuota(videos, freeCaps);
    expect(d.remove).toEqual([]);
    expect(d.keep).toHaveLength(2);
  });

  it("saca el archivo que excede el tope de TAMANO aunque sea el unico", () => {
    const d = decideQuota([vid("gordo.mp4", 30, 100)], freeCaps);
    expect(d.remove.map((v) => v.name)).toEqual(["gordo.mp4"]);
    expect(d.keep).toEqual([]);
  });

  it("saca exactamente en el borde: maxBytes clavado NO entra", () => {
    // La regla autoriza con `size < maxBytes`, asi que el archivo de
    // exactamente 25 MB da rojo alla. Si aca fuera `>` en vez de `>=`, la CF lo
    // dejaria vivo y las dos capas discreparian justo en el borde — que es el
    // unico lugar donde un off-by-one se nota.
    const d = decideQuota([vid("borde.mp4", 25, 100)], freeCaps);
    expect(d.remove.map((v) => v.name)).toEqual(["borde.mp4"]);

    const justUnder = decideQuota(
      [{ name: "casi.mp4", size: 25 * MB - 1, createdAt: 100 }],
      freeCaps,
    );
    expect(justUnder.remove).toEqual([]);
  });

  it("saca el excedente de CANTIDAD conservando los mas VIEJOS", () => {
    // Los viejos son los que los docs `customExercises` ya referencian por
    // `videoUrl`; los nuevos son los que se colaron por la carrera. Borrar al
    // reves le romperia los ejercicios ya armados.
    const videos = [
      vid("nuevo.mp4", 1, 500),
      vid("viejo.mp4", 1, 100),
      vid("medio.mp4", 1, 300),
      vid("recien.mp4", 1, 700),
    ];
    const d = decideQuota(videos, freeCaps);
    expect(d.keep.map((v) => v.name)).toEqual([
      "viejo.mp4",
      "medio.mp4",
      "nuevo.mp4",
    ]);
    expect(d.remove.map((v) => v.name)).toEqual(["recien.mp4"]);
  });

  it("desempata por nombre cuando dos comparten timestamp", () => {
    // `timeCreated` de GCS tiene resolucion de milisegundos: una rafaga
    // paralela puede dejar dos objetos con el mismo valor. Sin el desempate, el
    // orden seria el del listado y la decision no seria reproducible — la
    // redelivery de Eventarc podria conservar un archivo distinto que la
    // primera pasada y borrar el que ya habia quedado.
    const videos = [
      vid("c.mp4", 1, 100),
      vid("a.mp4", 1, 100),
      vid("d.mp4", 1, 100),
      vid("b.mp4", 1, 100),
    ];
    const d = decideQuota(videos, freeCaps);
    expect(d.keep.map((v) => v.name)).toEqual(["a.mp4", "b.mp4", "c.mp4"]);
    expect(d.remove.map((v) => v.name)).toEqual(["d.mp4"]);
  });

  it("combina los dos filtros: el gordo sale ADEMAS del excedente", () => {
    const videos = [
      vid("gordo.mp4", 40, 50),
      vid("v1.mp4", 1, 100),
      vid("v2.mp4", 1, 200),
      vid("v3.mp4", 1, 300),
      vid("v4.mp4", 1, 400),
    ];
    const d = decideQuota(videos, freeCaps);
    // El gordo no ocupa cupo: sale por tamano, y los 3 mas viejos de los que
    // quedan se conservan. Si el filtro de tamano corriera DESPUES del de
    // cantidad, el gordo se habria comido uno de los tres lugares.
    expect(d.keep.map((v) => v.name)).toEqual(["v1.mp4", "v2.mp4", "v3.mp4"]);
    expect(d.remove.map((v) => v.name).sort()).toEqual([
      "gordo.mp4",
      "v4.mp4",
    ]);
  });

  it("el PF entra con 50 videos y el 51 sobra", () => {
    const videos = Array.from({ length: 51 }, (_, i) =>
      vid(`v${String(i).padStart(3, "0")}.mp4`, 1, i),
    );
    const d = decideQuota(videos, { maxCount: 50, maxBytes: 100 * MB });
    expect(d.keep).toHaveLength(50);
    expect(d.remove.map((v) => v.name)).toEqual(["v050.mp4"]);
  });
});
