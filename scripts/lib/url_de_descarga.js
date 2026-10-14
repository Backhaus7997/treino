'use strict';

/**
 * lib/url_de_descarga.js
 *
 * LA URL DE DESCARGA que estampan los cuatro scripts que suben a Storage, armada
 * desde el MISMO plan que decidió el destino (`planDeStorage` de
 * `lib/storage_target.js`). Puro: sin `firebase-admin`, sin red.
 *
 * Por qué existe: los cuatro armaban la URL a mano con el host de producción
 * fijo —`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/…`—, también
 * cuando corrían contra el emulador. El archivo subía al emulador de Storage y la
 * URL que quedaba en el Firestore local apuntaba a Google. Medido el 2026-10-14:
 * `extract_exercise_thumbnails.js --upload` contra el emulador estampó la
 * primera URL de abajo, y `CachedNetworkImage` (lo que pinta `thumbnailUrl` en
 * `ExerciseAssetImage`) pidió cada una con HTTP real:
 *
 *   host real, bucket `demo-treino…`  → 404 de Google (la que estampaba)
 *   host real, bucket `treino-dev…`   → 403 de Google: el pedido llega al
 *                                       Storage de PRODUCCIÓN con un token que
 *                                       allá no existe (la misma con el bucket
 *                                       que le da al emulador el #1442)
 *   host del emulador, mismo token    → 200, imagen 256x256
 *
 * Y el error no se ve: el `errorWidget` de `ExerciseAssetImage` cae al asset
 * local del ejercicio, así que la corrida contra el emulador "anda" y lo que se
 * ve es otra imagen. Con el bucket de producción la URL estampada es, además,
 * idéntica a una de producción a simple vista.
 *
 * ─── POR QUÉ NO `getDownloadURL` DEL SDK ────────────────────────────────────
 *
 * `firebase-admin/storage` tiene `getDownloadURL(file)` y elige el host solo
 * (`STORAGE_EMULATOR_HOST` o Google). Se midió y contra el emulador de este repo
 * FALLA: hace un GET de metadata por `/v0/`, el emulador lo evalúa contra
 * `storage.rules`, y el catch-all `allow read, write: if false` lo deniega —
 * `403 Permission denied. No READ permission.` Además, en la nube agrega un GET
 * autenticado por archivo y un modo de falla nuevo (`no-download-token`) a un
 * camino que no se puede probar sin tocar producción.
 *
 * Así que la URL se sigue armando a mano, con el mismo formato que usa ese
 * `getDownloadURL` (`${endpoint}/v0/b/${bucket}/o/${encodeURIComponent(name)}
 * ?alt=media&token=${token}`), y lo único que cambia es el HOST — que sale del
 * plan, no de una segunda lectura del ambiente.
 */

/** El host de las URLs de descarga de Firebase Storage en la nube. */
const HOST_DE_LA_NUBE = 'https://firebasestorage.googleapis.com';

/**
 * El origen (`http://host:puerto`) del emulador de Storage, o `null` si no hay
 * uno usable.
 *
 * Mismo orden que `firebase-admin/lib/storage/storage.js`: si está
 * `STORAGE_EMULATOR_HOST` gana, y si no, `FIREBASE_STORAGE_EMULATOR_HOST` con
 * `http://` adelante (el SDK rechaza que esa traiga protocolo). Así la URL
 * nombra el mismo host al que el SDK acaba de subir el archivo.
 *
 * Un valor que no es una URL http(s) —uno en blanco, o `localhost:9199` en
 * `STORAGE_EMULATOR_HOST`, que `new URL` lee como esquema `localhost:`—
 * devuelve `null` en vez de adivinar.
 */
function origenDelEmulador(env = process.env) {
  const crudo = env.STORAGE_EMULATOR_HOST
    ? env.STORAGE_EMULATOR_HOST
    : env.FIREBASE_STORAGE_EMULATOR_HOST
      ? `http://${env.FIREBASE_STORAGE_EMULATOR_HOST}`
      : '';
  try {
    const url = new URL(String(crudo).trim());
    return (url.protocol === 'http:' || url.protocol === 'https:') && url.host ? url.origin : null;
  } catch {
    return null;
  }
}

/**
 * El host que va en las URLs de esta corrida. Tira si no hay uno honesto.
 *
 * Contra el emulador NUNCA cae al host de la nube: ése es exactamente el bug.
 * Si el plan dice emulador y no se puede leer de qué host, la corrida no
 * estampa nada — mejor un error antes de la primera subida que una URL que se
 * ve de producción.
 */
function hostDeDescarga(plan, env = process.env) {
  if (!plan || !plan.coherente || !plan.bucket) {
    throw new Error(
      'url_de_descarga: el plan de Storage no es coherente o no tiene bucket — ' +
        'exigirDestinoCoherente tendría que haber abortado antes (#838).',
    );
  }
  if (!plan.contraEmulador) return HOST_DE_LA_NUBE;

  const origen = origenDelEmulador(env);
  if (!origen) {
    throw new Error(
      'url_de_descarga: el destino es el EMULADOR pero no pude leer su host de ' +
        'FIREBASE_STORAGE_EMULATOR_HOST / STORAGE_EMULATOR_HOST. No estampo una ' +
        `URL de ${HOST_DE_LA_NUBE} para un archivo que vive en el emulador.`,
    );
  }
  return origen;
}

/**
 * Resuelve el host UNA vez y devuelve la función que arma cada URL.
 *
 * Se llama justo después de `exigirDestinoCoherente` y antes de la primera
 * subida, para que un host ilegible corte la corrida ahí y no en el archivo 37
 * con 36 ya subidos.
 */
function armadorDeUrlDeDescarga(plan, env = process.env) {
  const host = hostDeDescarga(plan, env);
  const { bucket } = plan;
  return ({ destino, token }) =>
    `${host}/v0/b/${bucket}/o/${encodeURIComponent(destino)}?alt=media&token=${token}`;
}

module.exports = {
  HOST_DE_LA_NUBE,
  armadorDeUrlDeDescarga,
  hostDeDescarga,
  origenDelEmulador,
};
