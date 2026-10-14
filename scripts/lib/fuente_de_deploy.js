/**
 * lib/fuente_de_deploy.js — ¿lo que estoy por deployar es lo que está en `develop`?
 *
 * El 2026-10-13 se deployaron las reglas de Firestore desde un checkout 58
 * commits atrás de `main`. Producción perdió en silencio las reglas de #1387
 * (`'no-gym'`) y #1395 (rangos de levantamiento): un rollback sin conflicto,
 * sin aviso y con el deploy en verde. Los deploys de reglas e índices son
 * manuales —ningún job de CI los hace—, así que la única barrera posible está
 * en el momento del deploy.
 *
 * La invariante: **cada archivo que se va a subir tiene que ser idéntico al de
 * `origin/develop`, recién fetcheado.** Frena las dos maneras de subir algo
 * que no corresponde:
 *
 *   - una rama VIEJA → revierte reglas que ya están en producción;
 *   - un cambio SIN MERGEAR (commiteado o no) → sube reglas que nadie revisó.
 *
 * Por qué `develop` y no "HEAD contiene `origin/main`": todo cambio de reglas
 * entra por `develop`, y producción puede ir adelante de `main` —#1431 y #1432
 * se deployaron desde `develop` antes del release—. Un guard contra `main`
 * dejaría pasar justo el rollback de esos fixes.
 *
 * Lógica pura: git y el filesystem entran por parámetro. El cableado real vive
 * en `scripts/guard_fuente_de_deploy.js` (hooks de `firebase.json`) y en
 * `scripts/deploy_rules.js`.
 */
'use strict';

const REF_FUENTE = 'origin/develop';

// Escape de emergencia. Deja pasar el deploy, pero no esconde las diferencias:
// se imprimen igual. Sólo "1" exacto, para que un `=true` o `=0` no lo prenda
// por accidente.
const VAR_OVERRIDE = 'TREINO_DEPLOY_FUERA_DE_DEVELOP';

// CRLF → LF. Con `core.autocrlf=true` (lo normal en Windows en este repo) el
// working tree está en CRLF y `git show` escribe LF: comparar bytes crudos
// daría "distinto" en TODO deploy desde Windows (AGENTS.md §11.2), y un guard
// que grita siempre se apaga.
function normalizar(texto) {
  return String(texto).replace(/\r\n/g, '\n');
}

/**
 * @param {object} p
 * @param {string[]} p.archivos   rutas relativas a la raíz del repo
 * @param {() => void} p.actualizarRemoto  trae `origin/develop` (git fetch); tira si no puede
 * @param {(archivo: string) => string} p.leerLocal   contenido en el working tree
 * @param {(archivo: string) => string} p.leerRemoto  contenido en `origin/develop`; tira si no existe
 * @param {Record<string, string|undefined>} p.env
 * @returns {{ ok: boolean, override: boolean, problemas: {archivo: string, motivo: string}[] }}
 */
function verificarFuente({ archivos, actualizarRemoto, leerLocal, leerRemoto, env }) {
  const pidioOverride = env[VAR_OVERRIDE] === '1';
  const problemas = [];

  try {
    actualizarRemoto();
  } catch (e) {
    // Falla CERRADO: con un `origin/develop` local viejo, comparar contra él
    // es comparar contra una mentira — justo el caso que esto existe para
    // atrapar. Sin red el deploy tampoco va a poder salir, así que no frena
    // nada que fuera a funcionar.
    problemas.push({
      archivo: '(todos)',
      motivo: `no pude actualizar ${REF_FUENTE}: ${primeraLinea(e)}`,
    });
    return resultado(problemas, pidioOverride);
  }

  for (const archivo of archivos) {
    let remoto;
    try {
      remoto = leerRemoto(archivo);
    } catch (e) {
      problemas.push({
        archivo,
        motivo: `no pude leer ${archivo} en ${REF_FUENTE} (¿no existe ahí?): ${primeraLinea(e)}`,
      });
      continue;
    }
    let local;
    try {
      local = leerLocal(archivo);
    } catch (e) {
      problemas.push({ archivo, motivo: `no pude leer ${archivo} local: ${primeraLinea(e)}` });
      continue;
    }
    if (normalizar(local) !== normalizar(remoto)) {
      problemas.push({ archivo, motivo: `difiere de ${REF_FUENTE}` });
    }
  }

  return resultado(problemas, pidioOverride);
}

function resultado(problemas, pidioOverride) {
  const hayProblemas = problemas.length > 0;
  return {
    ok: !hayProblemas || pidioOverride,
    override: hayProblemas && pidioOverride,
    problemas,
  };
}

function primeraLinea(e) {
  return String((e && e.message) || e).split('\n')[0];
}

module.exports = { REF_FUENTE, VAR_OVERRIDE, normalizar, verificarFuente };
