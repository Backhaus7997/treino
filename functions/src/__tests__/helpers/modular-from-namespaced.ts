/**
 * helpers/modular-from-namespaced.ts
 *
 * Traduce el doble namespaced de un test a las puertas MODULARES de
 * `firebase-admin`. Un test lo usa así, una línea por subpath:
 *
 *     jest.mock("firebase-admin/app", () =>
 *       require("./helpers/modular-from-namespaced").app());
 *
 * ─── Por qué existe ─────────────────────────────────────────────────────────
 *
 * `jest.mock("firebase-admin", …)` intercepta el specifier EXACTO. Desde que
 * producción importa de `firebase-admin/app` y `/firestore`, ese mock solo deja
 * pasar el SDK REAL por la puerta de al lado — y en esta suite eso no termina en
 * un rojo sino en un VERDE, porque 21 aserciones prueban por AUSENCIA
 * (`not.toHaveBeenCalled` sobre `sendEachForMulticast`) y producción tiene
 * `catch all → log + no rethrow`. Todo el detalle está en
 * `firebase-admin-mock-surface.test.ts`, que es el trinquete que lo fija.
 *
 * Antes esto se escribía a mano en cada test. Trece bloques casi iguales, con
 * tres formas distintas de tipar `ns`, es justo lo que después no se mantiene:
 * el drift entre dobles es el bug que esta migración entera existe para evitar.
 *
 * ─── Por qué DOS variantes de firestore, y no una "inteligente" ─────────────
 *
 * Los dobles de esta suite fingen el App de dos maneras distintas, y las dos son
 * legítimas:
 *
 *   · `desdeNamespaced()` — el test mockea `admin.firestore` como `jest.fn()` y
 *     lo configura con `mockReturnValue`. Producción hacía `admin.firestore(app)`.
 *   · `desdeApp()` — el test arma un objeto `app` con método `.firestore()`.
 *     Producción hacía `app.firestore()`.
 *
 * Se podría escribir una que pruebe la primera y caiga en la segunda. No: un
 * fallback silencioso convierte "el test configuró mal su doble" en "anduvo
 * igual", que es exactamente la clase de verde que no queremos. Que cada test
 * declare cuál usa.
 */

/**
 * El doble namespaced. La intersección no es capricho: `admin.firestore` es
 * función Y namespace a la vez (`Object.assign(jest.fn(), { FieldValue })`), y
 * los tests lo usan de las dos formas.
 */
type DobleNamespaced = Record<
  string,
  ((...a: unknown[]) => unknown) & Record<string, unknown>
>;

/** Se resuelve por llamada, no al importar: los factories corren por demanda. */
function ns(): DobleNamespaced {
  return jest.requireMock("firebase-admin") as DobleNamespaced;
}

/** `firebase-admin/app` — `getApp()` / `initializeApp()`. */
export function app(): Record<string, unknown> {
  return {
    getApp: (...args: unknown[]) => ns().app(...args),
    initializeApp: (...args: unknown[]) => ns().initializeApp(...args),
  };
}

/**
 * `firebase-admin/firestore` para un test que mockea `admin.firestore` como
 * función. `getFirestore(app)` es lo mismo que `admin.firestore(app)` —
 * verificado con `===` contra el paquete instalado.
 */
export function firestoreDesdeNamespaced(): Record<string, unknown> {
  return {
    getFirestore: (...args: unknown[]) => ns().firestore(...args),
    get FieldValue() {
      return ns().firestore.FieldValue;
    },
    get Timestamp() {
      return ns().firestore.Timestamp;
    },
  };
}

/**
 * `firebase-admin/firestore` para un test que arma un `app` con método
 * `.firestore()`. `getFirestore(app)` es lo mismo que `app.firestore()`.
 */
export function firestoreDesdeApp(): Record<string, unknown> {
  return {
    getFirestore: (app: unknown) => (app as { firestore: () => unknown }).firestore(),
    get FieldValue() {
      return ns().firestore.FieldValue;
    },
    get Timestamp() {
      return ns().firestore.Timestamp;
    },
  };
}

/** `firebase-admin/messaging` — `getMessaging()`. */
export function messaging(): Record<string, unknown> {
  return {
    getMessaging: (...args: unknown[]) => ns().messaging(...args),
  };
}

/**
 * El doble namespaced en crudo, para CONFIGURARLO desde un test:
 *
 *     (dobleNamespaced().firestore as jest.Mock).mockReturnValue(db);
 *
 * Antes esto se escribía `admin.firestore as unknown as jest.Mock`, con un
 * `import * as admin from "firebase-admin"` arriba. Desde `firebase-admin@14`
 * eso no compila: el root export son once símbolos y `firestore` no está entre
 * ellos, ni en runtime ni en los TIPOS.
 *
 * `jest.requireMock` esquiva la tipificación del módulo real justamente porque
 * lo que devuelve NO es el módulo real: es el objeto que el factory de
 * `jest.mock("firebase-admin", …)` construyó, y ese objeto tiene la forma que
 * el test le dio.
 */
export function dobleNamespaced(): Record<string, unknown> {
  return jest.requireMock("firebase-admin") as Record<string, unknown>;
}
