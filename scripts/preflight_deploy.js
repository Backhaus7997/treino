#!/usr/bin/env node
/**
 * preflight_deploy.js — chequea, ANTES de que arranque un deploy de functions,
 * las dos cosas que el 2026-09-15 costaron horas y que ningún test puede ver.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUÉ EXISTE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Ese día, deployar cuatro Cloud Functions triviales destapó TRES bloqueos que
 * llevaban días esperando. Los tres tenían la misma forma: **fallas que sólo
 * existen en el momento del deploy**, y este repo mergea mucho más seguido de
 * lo que deploya. El CI estaba verde con los tres puestos, porque ninguno es
 * un test.
 *
 *   1. `RC_API_KEY` declarado con `defineSecret()` y sin versión en Secret
 *      Manager. Rompía **TODOS** los deploys de functions —no sólo el de esa
 *      función— porque Firebase resuelve los params de todo el codebase antes
 *      de aplicar `--only`. Cuatro días latente.
 *   2. Los triggers de Storage en `southamerica-east1` y el bucket en
 *      `us-east1`. El error lo dice claro, pero recién cuando deployás.
 *   3. `firestore.rules` pasado de 256 KiB. Ese ya tiene su guarda en
 *      `scripts/strip_rules.js` + el job `rules-size` de CI.
 *
 * Este script cubre 1 y 2. No reemplaza al deploy: le adelanta el diagnóstico
 * con un mensaje que dice QUÉ falta, en vez de un 400 mudo o un error que
 * parece del cambio que uno está haciendo.
 *
 * ── La fuente de verdad es `functions/lib`, no el código fuente ──
 *
 * No grepea `defineSecret(` ni `region:`. Carga `functions/lib/index.js` y lee
 * el `__endpoint` de cada export — la MISMA estructura que lee firebase-tools
 * para armar el deploy. Un regex sobre el fuente se equivoca con un secreto
 * declarado en una constante, una región en una variable, o un export
 * comentado; el endpoint compilado no.
 *
 * ── Fail-soft a propósito ──
 *
 * Si no hay credenciales, no hay red, o la API contesta cualquier cosa, este
 * script **avisa y deja pasar** (exit 0). Sólo falla (exit 1) cuando pudo
 * verificar y encontró un problema real.
 *
 * El motivo: una guarda que puede romper el deploy por razones ajenas a lo que
 * chequea termina desactivada por el primero que la sufre un viernes. Vale más
 * una guarda que a veces no opina que una que el equipo aprende a saltear.
 *
 * Uso:
 *   node scripts/preflight_deploy.js      # lo corre el predeploy de functions
 */

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const LIB = path.join(ROOT, "functions", "lib", "index.js");
const CONFIGSTORE = path.join(
  os.homedir(),
  ".config",
  "configstore",
  "firebase-tools.json",
);

/** Sale sin fallar, avisando por qué no pudo chequear. */
function skip(motivo) {
  console.log(`preflight: SALTEADO — ${motivo}`);
  process.exit(0);
}

/**
 * El módulo de auth de la firebase-tools que está corriendo este predeploy.
 *
 * Se resuelve en vez de reimplementar el refresh de OAuth a mano, y NO es una
 * cuestión de elegancia: la versión anterior de este script hardcodeaba el
 * `client_secret` público de firebase-tools, y `gitleaks` la rechazó con
 * `generic-api-key`. Tenía razón — un literal llamado CLIENT_SECRET es
 * exactamente lo que un scanner tiene que marcar, sin ponerse a evaluar si ese
 * valor puntual es público. Delegar no deja nada que marcar.
 *
 * De paso se hereda el manejo de `invalid_rapt` y del refresh de la CLI, que
 * es la que de verdad sabe cómo está guardada la sesión.
 */
function authDeFirebaseTools() {
  const intentos = [
    () => require.resolve("firebase-tools/lib/auth.js"),
    () =>
      path.join(
        require("child_process")
          .execSync("npm root -g", { encoding: "utf8" })
          .trim(),
        "firebase-tools",
        "lib",
        "auth.js",
      ),
  ];
  for (const intento of intentos) {
    try {
      const mod = require(intento());
      if (typeof mod.getAccessToken === "function") return mod;
    } catch {
      // Probamos la siguiente estrategia.
    }
  }
  return null;
}

async function accessToken() {
  const auth = authDeFirebaseTools();
  if (!auth) throw new Error("no pude resolver firebase-tools/lib/auth");
  const cfg = JSON.parse(fs.readFileSync(CONFIGSTORE, "utf8"));
  const refresh = cfg.tokens && cfg.tokens.refresh_token;
  if (!refresh) throw new Error("el configstore no tiene refresh_token");
  const r = await auth.getAccessToken(refresh, []);
  const token = typeof r === "string" ? r : r && r.access_token;
  if (!token) throw new Error("firebase-tools no devolvió un access token");
  return token;
}

/** El bucket por defecto del proyecto, o null si no se puede resolver. */
async function bucketPorDefecto(token, project) {
  const r = await fetch(
    `https://firebasestorage.googleapis.com/v1beta/projects/${project}/buckets`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!r.ok) return null;
  const buckets = ((await r.json()).buckets || []).map((b) =>
    String(b.name).split("/").pop(),
  );
  // Los `gcf-*` son los internos de Cloud Functions, no el del producto.
  return buckets.find((b) => !b.startsWith("gcf-")) || buckets[0] || null;
}

/** Región de un bucket de GCS, en minúsculas. */
async function regionDelBucket(token, bucket) {
  const r = await fetch(
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}?fields=location`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!r.ok) return null;
  return String((await r.json()).location || "").toLowerCase();
}

/** Los secretos con al menos una versión ENABLED. */
async function secretosVivos(token, project, nombres) {
  const vivos = new Set();
  for (const n of nombres) {
    const r = await fetch(
      `https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${n}/versions?pageSize=50`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (!r.ok) continue; // 404 = no existe el secreto; queda fuera del set
    const vs = (await r.json()).versions || [];
    if (vs.some((v) => v.state === "ENABLED")) vivos.add(n);
  }
  return vivos;
}

/**
 * Los endpoints compilados.
 *
 * `FIREBASE_CONFIG` hace falta porque los triggers de Storage resuelven el
 * bucket al cargarse: sin él, `onObjectFinalized` tira «Missing bucket name».
 * Es el mismo motivo por el que existe el helper
 * `functions/src/__tests__/helpers/storage-trigger-env.ts`.
 */
function endpoints(project, bucket) {
  process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || project;
  process.env.FIREBASE_CONFIG =
    process.env.FIREBASE_CONFIG ||
    JSON.stringify({ projectId: project, storageBucket: bucket });
  const mod = require(LIB);
  return Object.entries(mod)
    .filter(([, v]) => v && v.__endpoint)
    .map(([nombre, v]) => [nombre, v.__endpoint]);
}

/**
 * Qué archivo define cada función exportada, según el `from` de su `export` en
 * `functions/src/index.ts`.
 *
 * Se lee el índice y no el filesystem porque el índice ES el contrato: una
 * función que no está exportada ahí no se deploya, exista o no su archivo.
 */
function fuentePorFuncion() {
  const idx = fs.readFileSync(
    path.join(ROOT, "functions", "src", "index.ts"),
    "utf8",
  );
  const mapa = new Map();
  const re = /export\s*\{([^}]+)\}\s*from\s*"([^"]+)"/g;
  let m;
  while ((m = re.exec(idx))) {
    const archivo =
      m[2].replace(/^\.\//, "functions/src/") + ".ts";
    for (const nombre of m[1]
      .split(",")
      .map((x) => x.trim())
      .filter(Boolean)) {
      mapa.set(nombre, archivo);
    }
  }
  return mapa;
}

/** Las funciones cuyo archivo tiene commits posteriores a su último deploy. */
async function funcionesConCodigoViejo(eps, token, project) {
  const { execSync } = require("child_process");
  const r = await fetch(
    `https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/-/functions?pageSize=200`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!r.ok) throw new Error(`cloudfunctions ${r.status}`);
  const desplegadas = new Map(
    ((await r.json()).functions || []).map((f) => [
      f.name.split("/").pop(),
      f.updateTime,
    ]),
  );

  const mapa = fuentePorFuncion();
  const viejas = [];
  for (const [nombre] of eps) {
    const desplegada = desplegadas.get(nombre);
    const archivo = mapa.get(nombre);
    // Sin deploy previo no está vieja: está por nacer, y de eso se ocupa este
    // mismo deploy.
    if (!desplegada || !archivo) continue;
    let commit;
    try {
      commit = execSync(`git log -1 --format=%cI -- "${archivo}"`, {
        cwd: ROOT,
        encoding: "utf8",
      }).trim();
    } catch {
      continue;
    }
    if (!commit) continue;
    // Las dos fechas llevan zona horaria (`Z` una, offset la otra), así que
    // `Date` las compara bien. Compararlas como texto NO funcionaría.
    if (new Date(commit) > new Date(desplegada)) {
      viejas.push({
        nombre,
        deploy: desplegada.slice(0, 19) + "Z",
        commit,
      });
    }
  }
  return viejas;
}

async function main() {
  const project = process.env.GCLOUD_PROJECT;
  if (!project) skip("no sé contra qué proyecto (falta GCLOUD_PROJECT)");
  if (!fs.existsSync(LIB)) skip(`no existe ${path.relative(ROOT, LIB)} — falta build`);
  if (!fs.existsSync(CONFIGSTORE)) skip("no encuentro las credenciales de firebase-tools");

  let token;
  try {
    token = await accessToken();
  } catch (e) {
    skip(`no pude autenticarme (${e.message}). Si esto persiste: firebase login --reauth`);
  }

  const bucket = await bucketPorDefecto(token, project);
  if (!bucket) skip(`no pude resolver el bucket por defecto de ${project}`);

  let eps;
  try {
    eps = endpoints(project, bucket);
  } catch (e) {
    skip(`no pude cargar los endpoints compilados (${e.message})`);
  }

  console.log(`preflight: ${eps.length} funciones · proyecto ${project} · bucket ${bucket}`);
  const problemas = [];

  // ── 1. Todo `defineSecret` tiene que tener una versión ENABLED ──────────
  const declarados = new Map(); // secreto -> [funciones que lo usan]
  for (const [nombre, ep] of eps) {
    for (const s of ep.secretEnvironmentVariables || []) {
      if (!declarados.has(s.key)) declarados.set(s.key, []);
      declarados.get(s.key).push(nombre);
    }
  }
  if (declarados.size) {
    const vivos = await secretosVivos(token, project, [...declarados.keys()]);
    for (const [secreto, fns] of declarados) {
      if (vivos.has(secreto)) {
        console.log(`  ✓ ${secreto} (${fns.length} función/es)`);
      } else {
        problemas.push(
          `✗ ${secreto} no tiene ninguna versión ENABLED en Secret Manager.\n` +
            `    Lo declaran: ${fns.join(", ")}\n` +
            `    ⚠️ Esto rompe TODOS los deploys de functions, no sólo el de esas:\n` +
            `       Firebase resuelve los params del codebase entero antes de --only.\n` +
            `    Cargalo con:  firebase functions:secrets:set ${secreto} --project ${project}`,
        );
      }
    }
  }

  // ── 2. Los triggers de Storage van en la región del bucket ──────────────
  const deStorage = eps.filter(
    ([, ep]) => ep.eventTrigger && /storage/i.test(ep.eventTrigger.eventType || ""),
  );
  if (deStorage.length) {
    const regiones = new Map();
    for (const [nombre, ep] of deStorage) {
      const b = (ep.eventTrigger.eventFilters || {}).bucket || bucket;
      if (!regiones.has(b)) regiones.set(b, await regionDelBucket(token, b));
      const esperada = regiones.get(b);
      const tiene = [].concat(ep.region || []).map((r) => String(r).toLowerCase());
      if (!esperada) {
        console.log(`  ? ${nombre}: no pude leer la región de ${b}`);
      } else if (tiene.includes(esperada)) {
        console.log(`  ✓ ${nombre} en ${esperada}, igual que ${b}`);
      } else {
        problemas.push(
          `✗ ${nombre} está en [${tiene.join(", ")}] y el bucket ${b} en ${esperada}.\n` +
            `    Un trigger de Storage DEBE estar en la región del bucket:\n` +
            `    «A function in region X cannot listen to a bucket in region Y».\n` +
            `    Cambiá el \`region:\` del trigger a "${esperada}".`,
        );
      }
    }
  }

  // ── 3. Funciones deployadas que corren código MÁS VIEJO que `main` ──────
  //
  // ⚠️ Esto AVISA, no falla, y la distinción es deliberada.
  //
  // Deployar un subconjunto es legítimo y pasa todo el tiempo. Si esto
  // bloqueara, el primero que corra un `--only functions:unaSola` con otra
  // función atrasada se comería un rojo que no tiene nada que ver con lo suyo —
  // y la guarda terminaría desactivada, que es el destino de toda guarda que
  // opina de más.
  //
  // El caso que SÍ vale la pena avisar: venís a deployar X y hace una semana
  // que Y está mergeada sin subir. Ese fue el estado real del proyecto el
  // 2026-09-15 — ocho funciones en `main` sin deployar, una de ellas la mitad
  // del bloqueo de usuarios — y el chequeo de «¿falta alguna?» NO lo ve: la
  // función existe, sólo que no es la que está en el repo.
  //
  // ── Lo que este chequeo NO ve ──
  //
  // Mapea cada función a SU archivo (el `from` de su `export` en `index.ts`),
  // así que **no detecta un cambio en un módulo compartido**: tocar
  // `mail/format.ts` deja viejas a todas las que lo importan y acá no aparece
  // ninguna. Detecta el caso común, no el transitivo. Preferí un chequeo
  // parcial que se entiende a uno completo que nadie pueda razonar.
  try {
    const viejas = await funcionesConCodigoViejo(eps, token, project);
    if (viejas.length) {
      console.warn(
        `\n⚠ ${viejas.length} función(es) deployadas corren código más viejo que main:`,
      );
      for (const v of viejas) {
        console.warn(`    ${v.nombre} — deploy ${v.deploy}, último commit ${v.commit}`);
      }
      console.warn(
        "  Si son las que estás deployando ahora, ignoralo: salen solas de la lista.\n",
      );
    }
  } catch (e) {
    console.log(`preflight: no pude chequear frescura (${e.message})`);
  }

  if (problemas.length) {
    console.error(`\npreflight: ${problemas.length} problema(s) — el deploy va a fallar.\n`);
    problemas.forEach((p) => console.error(`  ${p}\n`));
    process.exit(1);
  }
  console.log("preflight: OK");
}

main().catch((e) => skip(`error inesperado (${e.message})`));
