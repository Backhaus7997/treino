/**
 * stub_rules_api.js — un cliente FALSO de la REST API de Firebase Rules para
 * probar QUÉ sube `deploy_rules.js`, sin salir a la red.
 *
 * Se carga con `--require` y se apoya en `stub_firebase_admin.js` para todo lo
 * demás (credencial falsa, `firebase-admin` interceptado). Lo único que cambia
 * es `google-auth-library`: en vez de tirar en `getClient()`, devuelve un
 * cliente que responde la release y el ruleset desplegado y ANOTA cada request
 * en `STUB_RULES_LOG` (una línea JSON por request).
 *
 * - `STUB_DEPLOYED_RULES_FILE`: archivo con el contenido que "está desplegado".
 * - Los POST/PATCH no van a ningún lado: sólo se anotan.
 */

'use strict';

require('./stub_firebase_admin');

const fs = require('fs');
const Module = require('module');

const log = (entrada) => {
  fs.appendFileSync(process.env.STUB_RULES_LOG, `${JSON.stringify(entrada)}\n`);
};

const clienteFalso = {
  async request({ url, method = 'GET', data }) {
    log({ method, url, content: data?.source?.files?.[0]?.content ?? null });
    if (method === 'GET' && url.endsWith('/releases/cloud.firestore')) {
      return { data: { rulesetName: 'projects/stub/rulesets/activo' } };
    }
    if (method === 'GET' && url.endsWith('/rulesets/activo')) {
      const desplegado = fs.readFileSync(process.env.STUB_DEPLOYED_RULES_FILE, 'utf8');
      return { data: { source: { files: [{ content: desplegado }] } } };
    }
    if (method === 'POST') return { data: { name: 'projects/stub/rulesets/nuevo' } };
    return { data: {} };
  },
};

const googleAuthGrabador = {
  GoogleAuth: class {
    async getClient() {
      return clienteFalso;
    }
  },
};

const cargaPrevia = Module._load;
Module._load = function cargaConApiDeReglas(request, ...resto) {
  if (request === 'google-auth-library') return googleAuthGrabador;
  return cargaPrevia.call(this, request, ...resto);
};
