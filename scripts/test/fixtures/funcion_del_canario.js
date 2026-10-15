/**
 * La función que `scripts/check_emulator_sin_produccion.js` levanta en el
 * emulador. NO es un script: corre adentro del runtime de Functions del
 * emulador, con la credencial que le haya dejado `cerrar_produccion`.
 *
 * Informa las dos cosas que el canario mide: el valor del secreto (que tiene
 * que venir del Secret Manager falso) y con qué credencial arrancó
 * `firebase-admin` (que tiene que ser la falsa del repo, no el `firebase
 * login` que el CLI podría inyectarle).
 *
 * El nombre del secreto tiene que coincidir con SECRETO del canario.
 */
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');

const S = defineSecret('CANARIO_SECRETO_FALSO');
const app = initializeApp();

exports.canario = onRequest({ secrets: [S] }, (req, res) => {
  const c = app.options.credential;
  res.json({
    secreto: S.value(),
    credencial: c && c.constructor.name,
    clientId: c && c.refreshToken ? c.refreshToken.clientId : null,
  });
});
