/**
 * store-account-token.test.ts — el UUID por usuario.
 *
 * LOCAL, sin emulador: la decisión de si hay que emitir un token es una
 * función pura, y esa es toda la lógica del módulo.
 *
 * Lo que estos tests cuidan:
 *
 *   1. Que el token tenga forma de **UUID v4**. No es cosmético: Apple exige
 *      que `appAccountToken` sea un UUID, y si el string no parsea el plugin
 *      lo descarta **sin excepción ni warning**. La compra sale igual y queda
 *      sin dueño. El síntoma aparece en producción, con plata adentro.
 *
 *   2. Que no se re-emita si ya hay uno válido. Sin eso el trigger se
 *      re-dispara a sí mismo en loop, y además le cambiaría el token a alguien
 *      que ya compró — que es exactamente perder el mapeo que este campo
 *      existe para conservar.
 *
 *   3. Que SÍ se re-emita si lo que hay tiene la forma equivocada. Un token
 *      mal formado es peor que ninguno, por el punto 1.
 */

import { necesitaToken, UUID_V4 } from "../subscriptions/store-account-token";

describe("store-account-token — cuándo hay que emitir", () => {
  it("un documento sin token necesita uno", () => {
    expect(necesitaToken({ role: "athlete" })).toBe(true);
  });

  it("un documento con un UUID válido NO necesita otro", () => {
    // Si esto diera true, el trigger se re-dispararía a sí mismo en loop —y,
    // peor, le cambiaría el token a alguien que ya compró.
    expect(
      necesitaToken({ storeAccountToken: "3f2504e0-4f89-41d3-9a0c-0305e82c3301" }),
    ).toBe(false);
  });

  it("un documento BORRADO no necesita nada", () => {
    // `after` es undefined en un delete. Escribirle un campo a algo que ya no
    // está lo resucitaría.
    expect(necesitaToken(undefined)).toBe(false);
  });

  it("EL TEST QUE IMPORTA: un token con forma equivocada se re-emite", () => {
    // Un token que no parsea como UUID hace que Apple lo descarte EN SILENCIO
    // y la compra quede sin dueño. Tenerlo mal es peor que no tenerlo.
    const malos = [
      "", // vacío
      "abc", // cualquier cosa
      "aBcDeFgH1234567890aBcDeFgH12", // un uid de Firebase: 28 alfanuméricos
      "3f2504e0-4f89-41d3-9a0c", // truncado
      "3f2504e0-4f89-11d3-9a0c-0305e82c3301", // v1, no v4
      "3f2504e0-4f89-41d3-0a0c-0305e82c3301", // variante inválida
      "3F2504E0-4F89-41D3-9A0C-0305E82C3301", // mayúsculas
    ];
    for (const malo of malos) {
      expect(necesitaToken({ storeAccountToken: malo })).toBe(true);
    }
  });

  it("un token que no es string se re-emite", () => {
    for (const raro of [42, true, null, {}, []]) {
      expect(necesitaToken({ storeAccountToken: raro })).toBe(true);
    }
  });
});

describe("store-account-token — la forma del UUID", () => {
  it("el uid de Firebase NO pasa como UUID, y por eso existe este campo", () => {
    // 28 caracteres alfanuméricos. Es LA razón de todo el módulo: si el uid
    // sirviera, no haría falta nada de esto.
    expect(UUID_V4.test("aBcDeFgH1234567890aBcDeFgH12")).toBe(false);
  });

  it("acepta lo que genera `crypto.randomUUID()`", () => {
    // El contrato con Node, verificado y no asumido: si alguna vez cambiara el
    // formato que produce, este test lo dice antes que la App Store.
    const { randomUUID } = jest.requireActual("node:crypto") as {
      randomUUID: () => string;
    };
    for (let i = 0; i < 50; i++) {
      expect(UUID_V4.test(randomUUID())).toBe(true);
    }
  });
});
