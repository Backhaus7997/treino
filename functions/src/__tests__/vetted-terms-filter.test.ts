import { VETTED_CASES } from "../moderation/vetted_terms.g";
import {
  checkText,
  normalize,
  readings,
  type ModerationVerdict,
} from "../moderation/vetted_terms_filter";

/**
 * Conformidad del filtro de terminos vetados — ESPEJO de
 * `test/core/moderation/moderation_filter_test.dart`.
 *
 * El grueso de esta suite NO esta escrito aca: sale de `VETTED_CASES`, que se
 * genera desde `assets/moderation/terminos-vetados.json`. La suite de Dart
 * corre EXACTAMENTE los mismos casos contra las mismas expectativas.
 *
 * Esa es la parte que importa. El algoritmo es lo unico del filtro que esta
 * escrito dos veces, y un modelo con su espejo escrito a mano es como este
 * repo rompio la publicacion de posts durante siete semanas con la suite
 * entera en verde (`Post.reactionCounts`).
 */
describe("corpus de conformidad (generado, compartido con Dart)", () => {
  it("el corpus no esta vacio", () => {
    // Sin esto, borrar los casos del JSON dejaria esta suite en verde sin
    // haber medido nada — y el verde se leeria como "las dos coinciden".
    expect(VETTED_CASES.length).toBeGreaterThanOrEqual(30);
  });

  for (const caso of VETTED_CASES) {
    it(`${caso.espera.padEnd(6)} · "${caso.texto}"`, () => {
      // La forma normalizada se compara ADEMAS del veredicto, y sale de la
      // implementacion de referencia en el generador.
      //
      // Sin esto el corpus solo caza una divergencia cuando llega a voltear un
      // `ok` en `block`: dos normalizaciones distintas que no cruzan ese
      // umbral quedan vivas, con las dos suites en verde.
      expect(normalize(caso.texto)).toBe(caso.normalizado);
      expect(readings(caso.texto)).toEqual(caso.lecturas);

      const obtenido = checkText(caso.texto);
      if (obtenido !== caso.espera) {
        throw new Error(
          `esperaba "${caso.espera}" y dio "${obtenido}".\n` +
            `${caso.por}\n` +
            `normalizado: "${normalize(caso.texto)}"`,
        );
      }
      expect(obtenido).toBe(caso.espera as ModerationVerdict);
    });
  }
});

describe("normalizacion", () => {
  it("minuscula, diacriticos y repeticiones", () => {
    expect(normalize("PÚTOOOO")).toBe("puto");
    expect(normalize("Mogólico")).toBe("mogolico");
  });

  it("colapsa runs de tres o mas, no de dos", () => {
    // `carro`, `perro`, `llave` y `accion` tienen dobles. Colapsarlas
    // romperia el castellano entero.
    expect(normalize("carro")).toBe("carro");
    expect(normalize("perro")).toBe("perro");
    expect(normalize("holaaaa")).toBe("hola");
  });

  it("el leet de simbolos pide letra a los dos lados", () => {
    // Con `!` traducido a lo bruto, `puta!` quedaria `putai` y dejaria de
    // matchear: el falso NEGATIVO mas facil de producir.
    expect(normalize("puta!")).toBe("puta!");
    expect(normalize("p!ja")).toBe("pija");
  });

  it("los digitos se traducen siempre", () => {
    expect(normalize("p0to")).toBe("poto");
    expect(normalize("and4te")).toBe("andate");
  });

  it("un simbolo en el borde se lee de tres formas", () => {
    // `checkText` evalua todas y gana la peor: la estricta caza `pija@` (la
    // `@` es adorno), la adyacente caza `put@` y `put@@` y la total caza
    // `$!do$o`.
    expect(readings("put@")).toEqual(["put@", "puta"]);
    expect(readings("put@@")).toEqual(["put@@", "puta@", "putaa"]);
    expect(readings("pija@")).toEqual(["pija@", "pijaa"]);
    expect(readings("puta!")).toEqual(["puta!", "putai"]);
    expect(readings("te voy @ matar"))
      .toEqual(["te voy @ matar", "te voy a matar"]);
    expect(readings("hola")).toEqual(["hola"]);
  });
});

describe("lo que el filtro NO hace", () => {
  it("no pega el texto entero en la pasada antievasion", () => {
    // `otroloco` contiene `trolo`. La implementacion ingenua —pegar todos los
    // tokens— bloquea castellano corriente.
    expect(checkText("otro loco")).toBe("ok");
    expect(checkText("otro lote")).toBe("ok");
  });

  it("no bloquea el vocabulario del producto", () => {
    // Si esto se cae, el filtro es inusable: `musculo` esta en cada rutina.
    for (const texto of [
      "musculo",
      "musculos",
      "musculacion",
      "cuatro series al musculo dorsal",
      "calculo el volumen semanal",
    ]) {
      expect(checkText(texto)).toBe("ok");
    }
  });

  it("block le gana a review", () => {
    // `pelotudo` es `review`, `puto` es `block`. Juntos tiene que ganar el
    // mas severo, si no la severidad depende del orden del texto.
    expect(checkText("pelotudo puto")).toBe("block");
    expect(checkText("puto pelotudo")).toBe("block");
  });

  it("texto vacio o sin letras pasa", () => {
    expect(checkText("")).toBe("ok");
    expect(checkText("   ")).toBe("ok");
    expect(checkText("!!!")).toBe("ok");
  });
});
