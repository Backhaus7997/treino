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
      const nombre = /color:#2CE5A2;">([^<]+)<\/div>/.exec(trozo);
      const detalle = /padding-top:2px;[^"]*">([^<]+)<\/div>/.exec(trozo);
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

  it("una card por plan, de Free a Plan 3, con su cupo de alumnos", () => {
    expect(cards(html).map((c) => [c.nombre, c.detalle])).toEqual([
      ["Free", "2 alumnos"],
      ["Plan 1", "7 alumnos"],
      ["Plan 2", "15 alumnos"],
      ["Plan 3", "Alumnos sin límite"],
    ]);
  });

  it("los pagos llevan el precio por mes a la derecha; el Free no lleva precio", () => {
    const [free, plan1, plan2, plan3] = cards(html);
    expect(free.precio).toBeUndefined();
    expect(plan1.precio).toMatch(/^\$\s?12\.000$/);
    expect(plan2.precio).toMatch(/^\$\s?22\.000$/);
    expect(plan3.precio).toMatch(/^\$\s?39\.000$/);
    expect([plan1, plan2, plan3].map((c) => c.periodo)).toEqual(["por mes", "por mes", "por mes"]);
  });

  it("en el HTML los planes ya no son párrafos", () => {
    expect(html).not.toMatch(/<p[^>]*><strong[^>]*>Plan 1<\/strong>/);
    expect(html).not.toMatch(/<p[^>]*><strong[^>]*>Free<\/strong>/);
  });

  it("el texto plano sigue igual: una línea por plan, en minúscula dentro de la frase", () => {
    expect(text).toContain("Free · 2 alumnos");
    expect(text).toMatch(/Plan 1 · 7 alumnos · \$\s?12\.000 por mes/);
    expect(text).toMatch(/Plan 3 · alumnos sin límite · \$\s?39\.000 por mes/);
    expect(text).toContain("Cada plan también se puede pagar por año.");
  });

  it("el código sigue después de los planes", () => {
    expect(html.indexOf("048213")).toBeGreaterThan(html.lastIndexOf("background:#1D2321"));
  });
});

describe("planes del alumno", () => {
  it("el mail del código: el gratis y TREINO Pro, sin precio a la derecha", () => {
    const { html } = renderMail("email-code-athlete", { codigo: "048213", showPlans: "1" }, PIE);
    const [gratis, pro] = cards(html);

    expect(cards(html)).toHaveLength(2);
    expect(gratis).toEqual({ nombre: "Gratis", detalle: "El que tenés hoy" });
    expect(pro.nombre).toBe("TREINO Pro");
    expect(pro.detalle).toMatch(/^\$\s?3\.500 por mes o \$\s?35\.000 por año$/);
    expect(pro.precio).toBeUndefined();
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
