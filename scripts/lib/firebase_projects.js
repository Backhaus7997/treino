'use strict';

/**
 * lib/firebase_projects.js
 *
 * QUÉ project ids de Firebase son PRODUCCIÓN. Nada más que eso, y a propósito.
 *
 * Por qué existe (#826): TREINO tiene UN SOLO proyecto Firebase y se llama
 * `treino-dev`. No hay `treino-prod`, no hay un entorno de desarrollo separado
 * en la nube, y en `treino-dev` viven los usuarios reales. El nombre invita al
 * error exacto que hay que evitar — cualquiera que lea `--project treino-dev`
 * asume "descartable".
 *
 * El caso concreto que motivó el módulo: `backfill_gym_ids.js` y
 * `backfill_gym_names.js` traían un guard que se negaba a correr si el project
 * id NO contenía "dev". Contra `treino-dev` ese guard PASA — o sea que la única
 * salvaguarda de dos scripts que escriben sobre `users/` y `userPublicProfiles/`
 * estaba, por construcción, apagada justo contra producción. No protegía nada;
 * peor, tranquilizaba.
 *
 * Decisión deliberada de #826: acá NO se cambia la decisión de correr o no
 * correr (los exit codes de esos scripts quedan idénticos). Lo que se agrega es
 * que el operador VEA la verdad antes de que el script escriba. Cambiar el
 * guard para que `treino-dev` requiera `--allow-prod` rompería la invocación
 * documentada de ambos scripts, y eso es un cambio de conducta que no entra en
 * un PR de documentación — va con el renombre del proyecto o con el entorno de
 * dev real (alcances 2 y 3 del issue).
 *
 * Vive separado y puro —sin `firebase-admin`, sin I/O— por el mismo motivo que
 * `dedupe_setlogs_plan.js`: la regla se mide en milisegundos y sin emulador,
 * y así cualquier script nuevo la hereda con un `require` en vez de recopiar
 * una heurística sobre el nombre.
 */

/**
 * Los project ids que son producción. Es una LISTA EXPLÍCITA, no una heurística
 * sobre el nombre: la heurística es exactamente lo que falló (#826). Si algún
 * día existe `treino-prod`, se agrega acá; `treino-dev` NO se saca hasta que
 * deje de servir usuarios reales.
 */
const PROYECTOS_DE_PRODUCCION = Object.freeze(['treino-dev']);

/**
 * ¿Este project id es producción?
 *
 * Tolerante con la entrada (espacios, mayúsculas) porque el valor llega de
 * `sa-key.json` o de `--project=`, no de nosotros. Cualquier cosa que no sea
 * string es `false`: el que no sabe contra qué proyecto está no puede afirmar
 * que es producción, y el llamador ya imprime el `project_id` crudo aparte.
 */
function esProduccion(projectId) {
  if (typeof projectId !== 'string') return false;
  return PROYECTOS_DE_PRODUCCION.includes(projectId.trim().toLowerCase());
}

/**
 * El cartel que ve el operador, o `null` si no hay nada que advertir.
 *
 * `contraEmulador` existe para no gritar en falso: los scripts fijan
 * `projectId: 'treino-dev'` también cuando apuntan al emulador, y ahí ese id
 * es apenas un namespace local. Un cartel que aparece cuando no corresponde
 * se aprende a ignorar, y entonces tampoco se lee cuando corresponde.
 */
function bannerDeProduccion(projectId, { contraEmulador = false } = {}) {
  if (contraEmulador) return null;
  if (!esProduccion(projectId)) return null;
  return [
    '',
    '🚨 ─────────────────────────────────────────────────────────────────────',
    `🚨  "${projectId}" IS PRODUCTION. The name says "dev"; the data is real.`,
    '🚨  It is TREINO\'s only Firebase project — there is no treino-prod, and',
    '🚨  no declared backup. Admin SDK writes bypass the Firestore rules.',
    '🚨',
    '🚨  Emulator instead:  FIRESTORE_EMULATOR_HOST=localhost:8080 node <script>',
    '🚨  Context: issue #826 / AGENTS.md → Entornos',
    '🚨 ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
}

module.exports = { PROYECTOS_DE_PRODUCCION, esProduccion, bannerDeProduccion };
