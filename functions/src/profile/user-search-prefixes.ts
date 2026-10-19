/**
 * user-search-prefixes.ts — el UNICO escritor de
 * `userPublicProfiles/{uid}.searchPrefixes` (#1478).
 *
 * El problema: "martin" no encontraba a "Martín López", y "lopez" tampoco. La
 * busqueda era un rango de prefijo sobre `displayNameLowercase`: solo desde el
 * principio del nombre completo y sin plegar tildes. Con nombres en español es
 * la mitad de las busquedas.
 *
 * La solucion: un campo nuevo con los prefijos de cada palabra del nombre,
 * plegados ("Martín López" → ma, mar, …, martin, lo, …, lopez), y la app busca
 * con `array-contains`. NO se reusa `displayNameLowercase`: ese campo tambien
 * decide la unicidad del @handle (`isDisplayNameTaken`) y ordena el directorio
 * de PFs.
 *
 * Por que lo escribe una Cloud Function y no la app:
 *   - Cubre a TODO el que cambia el nombre: la app de hoy, las versiones
 *     viejas que no conocen el campo, el Coach Hub, la cuarentena de
 *     moderacion (`quarantine-vetted-content.ts`, que redacta el nombre: si no
 *     se recalculara, el nombre vetado seguiria encontrandose por sus
 *     prefijos) y los scripts.
 *   - Nadie puede inyectarse prefijos para aparecer en busquedas ajenas: las
 *     reglas no dejan que el cliente lo cree ni lo cambie (mismo patron que
 *     `squatRank`).
 *
 * Idempotente y auto-sanador: compara lo que el documento TIENE con lo que
 * DEBERIA tener, no el antes/despues del nombre. Su propia escritura vuelve a
 * disparar el trigger, ve que ya coincide y no escribe. Un perfil que nunca
 * paso por el backfill se completa en la proxima escritura que reciba.
 *
 * ⚠️ ORDEN DE DEPLOY: reglas ANTES que functions. Las reglas de
 * `userPublicProfiles` validan el documento ENTERO con `keys().hasOnly`: si
 * esta funcion escribe el campo y las reglas desplegadas todavia no lo
 * conocen, se rechaza TODA actualizacion de ese perfil hecha desde la app.
 *
 * PARIDAD: el plegado vive en tres lugares — aca, `scripts/lib/
 * user_search_terms.js` (backfill y seed) y `lib/features/profile/domain/
 * user_search_terms.dart` (la consulta de la app). Los tres leen los mismos
 * vectores de `test/fixtures/search/user_search_terms.json`. Mismo esquema que
 * el `normalize()` de `add-alias.ts` (ADR-CXP-006): clases de caracteres
 * explicitas, y todo lo que no sea `[a-z0-9]` separa palabras, asi que los
 * tokens quedan en ASCII y los tres lenguajes cortan exactamente igual.
 */

import { getApp, initializeApp, type App } from "firebase-admin/app";
import { getFirestore, type Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

/** Prefijo mas corto que se guarda; la app no busca con menos de 2 letras. */
export const SEARCH_PREFIX_MIN = 2;

/**
 * Prefijo mas largo que se guarda. La app trunca la consulta a este largo y
 * termina de filtrar en el cliente, asi que un nombre de 20 letras se sigue
 * encontrando entero.
 */
export const SEARCH_PREFIX_MAX = 15;

/**
 * Palabras (de 2 letras o mas) que se indexan. Con el tope de largo da como
 * mucho 6 × 14 = 84 entradas, ~1 KB por perfil.
 */
export const SEARCH_MAX_TOKENS = 6;

/** Codigo gRPC de `FAILED_PRECONDITION` (el doc cambio despues del evento). */
const FAILED_PRECONDITION = 9;
/** Codigo gRPC de `NOT_FOUND` (el doc se borro despues del evento). */
const NOT_FOUND = 5;

/**
 * Palabras de [text], plegadas: minusculas, sin tildes ni dieresis, `ñ`→`n`,
 * `ç`→`c`, y cortadas en todo lo que no sea `[a-z0-9]`. Sin repetidas, en el
 * orden en que aparecen.
 *
 * El orden de las operaciones importa: primero minusculas (para que `Á` sea
 * `á` antes de reemplazarla), despues las marcas combinantes sueltas (un
 * teclado que manda "i" + U+0301 en vez de "í"), despues las letras con tilde,
 * y recien al final el corte, que si fuera antes se comeria las letras con
 * tilde como separadores.
 */
export function searchTokens(text: unknown): string[] {
  if (typeof text !== "string") return [];
  const folded = text
    .toLowerCase()
    .replace(/[̀-ͯ]/g, "")
    .replace(/[áàäâãå]/g, "a")
    .replace(/[éèëê]/g, "e")
    .replace(/[íìïî]/g, "i")
    .replace(/[óòöôõ]/g, "o")
    .replace(/[úùüû]/g, "u")
    .replace(/[ýÿ]/g, "y")
    .replace(/ñ/g, "n")
    .replace(/ç/g, "c");
  const tokens: string[] = [];
  for (const t of folded.split(/[^a-z0-9]+/)) {
    if (t !== "" && !tokens.includes(t)) tokens.push(t);
  }
  return tokens;
}

/**
 * Lo que tiene que guardar `searchPrefixes` para el nombre [displayName]: los
 * prefijos de largo [SEARCH_PREFIX_MIN]..[SEARCH_PREFIX_MAX] de las primeras
 * [SEARCH_MAX_TOKENS] palabras de 2 letras o mas, sin repetidos.
 */
export function searchPrefixesFor(displayName: unknown): string[] {
  const out: string[] = [];
  const seen = new Set<string>();
  const tokens = searchTokens(displayName)
    .filter((t) => t.length >= SEARCH_PREFIX_MIN)
    .slice(0, SEARCH_MAX_TOKENS);
  for (const t of tokens) {
    const top = Math.min(t.length, SEARCH_PREFIX_MAX);
    for (let n = SEARCH_PREFIX_MIN; n <= top; n++) {
      const p = t.slice(0, n);
      if (!seen.has(p)) {
        seen.add(p);
        out.push(p);
      }
    }
  }
  return out;
}

function mismaLista(a: unknown[], b: string[]): boolean {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

/**
 * Que escribir en `searchPrefixes` para un perfil con estos [data], o `null`
 * si no hay que escribir nada: el doc no existe, o ya tiene lo que debe.
 *
 * Un perfil SIN el campo y sin nombre buscable no se toca: escribirle `[]`
 * seria una escritura por cada perfil anonimo, sin cambiar ninguna busqueda.
 */
export function searchPrefixesToWrite(
  data: Record<string, unknown> | undefined,
): string[] | null {
  if (data === undefined) return null;
  const wanted = searchPrefixesFor(data.displayName);
  const current = data.searchPrefixes;
  if (current === undefined || current === null) {
    return wanted.length === 0 ? null : wanted;
  }
  if (Array.isArray(current) && mismaLista(current, wanted)) return null;
  return wanted;
}

/** Lo que el trigger necesita del snapshot `after` del evento. */
export interface PerfilEscrito {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
  updateTime?: Timestamp;
}

/**
 * Logica del trigger, separada para testearla sin emulador. Escribe con
 * precondicion `lastUpdateTime`: si el perfil cambio despues del evento, NO se
 * pisa con prefijos de un nombre viejo — esa escritura nueva disparo su propio
 * trigger y se recalcula ahi.
 */
export async function aplicarSearchPrefixes(
  app: App,
  uid: string,
  after: PerfilEscrito | undefined,
): Promise<"escrito" | "sin-cambios" | "obsoleto"> {
  if (!after?.exists) return "sin-cambios";
  const wanted = searchPrefixesToWrite(after.data());
  if (wanted === null) return "sin-cambios";

  try {
    await getFirestore(app)
      .doc(`userPublicProfiles/${uid}`)
      .update(
        { searchPrefixes: wanted },
        after.updateTime ? { lastUpdateTime: after.updateTime } : {},
      );
    return "escrito";
  } catch (err) {
    const code = (err as { code?: number }).code;
    if (code === FAILED_PRECONDITION || code === NOT_FOUND) {
      logger.info("searchPrefixes: el perfil cambio, lo recalcula su propio evento",
        { uid });
      return "obsoleto";
    }
    throw err;
  }
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * Recalcula `searchPrefixes` en cada escritura de un perfil publico. La
 * mayoria de las invocaciones (contadores, racha, opt-in de rankings) no
 * cambian el nombre y terminan sin escribir nada.
 *
 * Deployed to southamerica-east1 per ADR-RV-003.
 */
export const userSearchPrefixesOnWrite = onDocumentWritten(
  { document: "userPublicProfiles/{uid}", region: "southamerica-east1" },
  async (event) => {
    await aplicarSearchPrefixes(ensureApp(), event.params.uid, event.data?.after);
  },
);
