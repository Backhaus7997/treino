/**
 * Los planes de los mails dibujados como cards.
 *
 * Pure — no emulator, no network. Run with plain `npx jest mail-planes-cards`.
 *
 * La card es SÓLO presentación: el HTML dibuja cada plan como card en vez de
 * como párrafo, y el text/plain sigue diciendo exactamente lo mismo que antes,
 * plan por plan. Los textos de siempre ya los cubren `mail-templates`,
 * `trainer-limit-mail` y `free-limit-mail`; acá se cubre la card.
 */

import { renderMail } from "../mail/templates";

const PIE = {
  bajaDePromocionales: "https://gettreino.com/es/correos-promocionales/baja#t=v1.abc.def.ghi",
};

interface Card {
  nombre: string;
  detalle: string;
  precio?: string;
  periodo?: string;
}

/**
 * Las cards de un HTML, en orden. El relleno `#1D2321` sólo lo usan las cards
 * (`PLAN_CARD`), así que partir por ahí separa una de otra.
 */
function cards(html: string): Card[] {
  return html
    .split("background:#1D2321")
    .slice(1)
    .map((trozo) => {
      const nombre = /color:#(?:2CE5A2|FFFFFF|D457EC);">([^<]+)<\/div>/.exec(trozo);
      const detalle = /(?:padding-top:2px;|padding-top:8px;font-size:28px;)[^"]*">([^<]+)<\/div>/.exec(trozo);
      const precio = /<td align="right"[^>]*><div[^>]*>([^<]+)<\/div><div[^>]*>([^<]+)<\/div>/.exec(trozo);
      return {
        nombre: nombre ? nombre[1] : "",
        detalle: detalle ? detalle[1] : "",
        ...(precio ? { precio: precio[1], periodo: precio[2] } : {}),
      };
    });
}

describe("planes del PF en el mail del código", () => {
  const { html, text } = renderMail("email-code-trainer", { codigo: "048213", showPlans: "1" }, PIE);

  it("una card por plan, de Free a Plan 3, con su cupo de alumnos y SIN precio", () => {
    expect(cards(html).map((c) => [c.nombre, c.detalle])).toEqual([
      ["Free", "Gratis"],
      ["Plan 1", "Hasta 7 alumnos"],
      ["Plan 2", "Hasta 15 alumnos"],
      ["Plan 3", "Alumnos sin tope"],
    ]);
  });

  it("ninguna card lleva precio, ni en el HTML ni en el texto plano", () => {
    expect(cards(html).every((c) => c.precio === undefined)).toBe(true);
    expect(html).not.toMatch(/\$\s?\d/);
    expect(text).not.toMatch(/\$\s?\d/);
    expect(text).not.toMatch(/por mes|por año/);
  });

  it("cada card detalla ejercicios propios y plantillas", () => {
    expect(html).toContain("Ejercicios propios: <strong style=\"color:#FFFFFF;\">20</strong>");
    expect(html).toContain("Plantillas: <strong style=\"color:#FFFFFF;\">3</strong>");
    expect(html).toContain("Plantillas: <strong style=\"color:#FFFFFF;\">Sin tope</strong>");
    expect(html).toContain("Hasta 2 alumnos activos");
  });

  it("Plan 1 va destacada con borde mint, como la recomendada de la pantalla de planes", () => {
    const trozos = html.split("background:#1D2321").slice(1);
    expect(trozos.map((t) => t.includes("border:1.5px solid #2CE5A2"))).toEqual([false, true, false, false]);
  });

  it("en el HTML los planes ya no son párrafos", () => {
    expect(html).not.toMatch(/<p[^>]*><strong[^>]*>Plan 1<\/strong>/);
    expect(html).not.toMatch(/<p[^>]*><strong[^>]*>Free<\/strong>/);
  });

  it("el texto plano: una línea por plan, en minúscula dentro de la frase", () => {
    expect(text).toContain("Free · Gratis · Hasta 2 alumnos activos · cada alumno pausado cuenta 0,5 · Ejercicios propios: 20 · Plantillas: 3");
    expect(text).toContain("Plan 3 · Alumnos sin tope · Ejercicios propios: Sin tope · Plantillas: Sin tope");
  });

  it("el código sigue después de los planes", () => {
    expect(html.indexOf("048213")).toBeGreaterThan(html.lastIndexOf("background:#1D2321"));
  });
});

describe("colores del mail del código", () => {
  it("el titular queda blanco, con y sin planes", () => {
    const con = renderMail("email-code-athlete", { codigo: "048213", showPlans: "1" }, PIE).html;
    const sin = renderMail("email-code-athlete", { codigo: "048213", showPlans: "0" }, PIE).html;
    expect(con).toMatch(/<h1[^>]*color:#FFFFFF;/);
    expect(sin).toMatch(/<h1[^>]*color:#FFFFFF;/);
  });

  it("alumno: el nombre del plan va en morado y el título grande en verde, igual que el PF", () => {
    const { html } = renderMail("email-code-athlete", { codigo: "048213", showPlans: "1" }, PIE);
    expect(html).toMatch(/color:#D457EC;">Gratis<\/div>/);
    expect(html).toMatch(/color:#D457EC;">TREINO Pro<\/div>/);
    expect(html).toMatch(/color:#2CE5A2;">El que tenés hoy<\/div>/);
    expect(html).toMatch(/color:#2CE5A2;">Sin los topes del plan gratis<\/div>/);
    expect(html).not.toMatch(/color:#D457EC;">(El que|Sin los)/);
  });

  it("entrenador: el nombre del plan va en morado y el héroe en verde", () => {
    const { html } = renderMail("email-code-trainer", { codigo: "048213", showPlans: "1" }, PIE);
    for (const plan of ["Free", "Plan 1", "Plan 2", "Plan 3"]) {
      expect(html).toContain(`color:#D457EC;">${plan}</div>`);
    }
    expect(html).toMatch(/color:#2CE5A2;">Hasta 15 alumnos<\/div>/);
    expect(html).toMatch(/color:#2CE5A2;">Gratis<\/div>/);
    expect(html).not.toMatch(/color:#D457EC;">Hasta/);
  });

  it("entrenador: cada fila de las cards lleva su ✓", () => {
    const { html } = renderMail("email-code-trainer", { codigo: "048213", showPlans: "1" }, PIE);
    const filas = html.match(/&#10003;<\/span>&nbsp; (Ejercicios propios|Plantillas): /g) ?? [];
    expect(filas).toHaveLength(8); // 4 planes × 2 filas
  });
});

describe("planes del alumno", () => {
  it("el mail del código: el gratis y TREINO Pro con sus beneficios, sin precio", () => {
    const { html } = renderMail("email-code-athlete", { codigo: "048213", showPlans: "1" }, PIE);
    const [gratis, pro] = cards(html);

    expect(cards(html)).toHaveLength(2);
    expect(gratis).toEqual({ nombre: "Gratis", detalle: "El que tenés hoy" });
    expect(pro.nombre).toBe("TREINO Pro");
    expect(pro.detalle).toBe("Sin los topes del plan gratis");
    expect(pro.precio).toBeUndefined();
    expect(html).toContain("&#10003;</span>&nbsp; Rutinas de hasta 7 días");
    expect(html).toContain("Hasta 16 semanas, con periodización");
    expect(html).toContain("Hasta 10 rutinas propias");
    expect(html).toContain("border:1.5px solid #2CE5A2");
    expect(html).not.toMatch(/\$\s?\d/);
  });

  it("el mail del tope: una sola card, la de TREINO Pro", () => {
    const { html } = renderMail("free-limit-reached", {}, PIE);
    expect(cards(html).map((c) => c.nombre)).toEqual(["TREINO Pro"]);
  });
});

describe("planes con más lugar en los mails de tope del PF", () => {
  it("plantillas: los tres pagos, con «Plantillas sin límite» como título", () => {
    const { html, text } = renderMail("template-limit-reached", { limit: 3 }, PIE);

    expect(cards(html).map((c) => [c.nombre, c.detalle])).toEqual([
      ["Plan 1", "Plantillas sin límite"],
      ["Plan 2", "Plantillas sin límite"],
      ["Plan 3", "Plantillas sin límite"],
    ]);
    expect(text).toMatch(/Plan 1 · plantillas sin límite · \$\s?12\.000 por mes/);
  });

  it("ejercicios: sólo los planes que traen más lugar que el tope que chocó", () => {
    const { html } = renderMail("exercise-limit-reached", { limit: 60 }, PIE);
    expect(cards(html).map((c) => c.nombre)).toEqual(["Plan 2", "Plan 3"]);
  });

  it("alumnos: las cards dicen el cupo de alumnos", () => {
    const { html } = renderMail("student-limit-reached", { limit: 2 }, PIE);
    expect(cards(html).map((c) => c.detalle)).toEqual(["7 alumnos", "15 alumnos", "Alumnos sin límite"]);
  });

  it("si su plan ya no tiene tope, no hay cards: queda la frase de siempre", () => {
    const { html } = renderMail("template-limit-reached", { limit: "sin-tope" }, PIE);
    expect(cards(html)).toEqual([]);
    expect(html).toContain("Si necesitás más lugar, hay planes más grandes.");
  });

  it("sin lo comercial, el bloque de venta se va entero: tampoco hay cards", () => {
    const { html } = renderMail("limit-reached", { limit: 2, blockedCount: 1 }, { comercial: false });
    expect(cards(html)).toEqual([]);
  });
});
