#!/usr/bin/env node
/**
 * preflight_deploy.js — chequea, ANTES de que arranque un deploy de functions,
 * las cosas que el 2026-09-15 costaron horas y que ningún test puede ver.
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
 * Este script cubre 1 y 2, más un tercero que se sumó el mismo día y que no
 * había aparecido todavía SÓLO porque faltaban 45 días:
 *
 *   4. `firebase.json` pedía el runtime `nodejs20`, que se decomisiona el
 *      **2026-10-30**. Pasada esa fecha no se puede deployar NINGUNA función
 *      —ni un hotfix—, y el único aviso previo son unos warnings de
 *      deprecación perdidos entre las 48 líneas de un deploy normal.
 *
 * Los tres primeros fallan cuando alguien rompe algo. El cuarto falla cuando
 * pasa el TIEMPO: nadie lo introduce, se pudre solo. Por eso es el único
 * chequeo que corre antes de los `skip()` —no necesita credenciales ni red— y
 * por eso su tabla de fechas se LEE de firebase-tools en vez de copiarse acá.
 *
 * No reemplaza al deploy: le adelanta el diagnóstico con un mensaje que dice
 * QUÉ falta, en vez de un 400 mudo o un error que parece del cambio que uno
 * está haciendo.
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
function moduloDeFirebaseTools(relativo) {
  const intentos = [
    () => require.resolve(`firebase-tools/${relativo}`),
    () =>
      path.join(
        require("child_process")
          .execSync("npm root -g", { encoding: "utf8" })
          .trim(),
        "firebase-tools",
        ...relativo.split("/"),
      ),
  ];
  for (const intento of intentos) {
    try {
      return require(intento());
    } catch {
      // Probamos la siguiente estrategia.
    }
  }
  return null;
}

function authDeFirebaseTools() {
  const mod = moduloDeFirebaseTools("lib/auth.js");
  return mod && typeof mod.getAccessToken === "function" ? mod : null;
}

// ═══════════════════════════════════════════════════════════════════════════
//  3. El runtime configurado sigue estando vivo
// ═══════════════════════════════════════════════════════════════════════════
//
// El 2026-09-15 `firebase.json` pedía `nodejs20`, que se decomisiona el
// 2026-10-30. Después de esa fecha NO SE PUEDE DEPLOYAR NINGUNA FUNCIÓN —ni un
// hotfix— y el aviso previo son unos warnings de deprecación que se pierden
// entre las 48 líneas que escupe un deploy normal.
//
// Misma forma que los otros dos chequeos: el CI no puede verlo porque no es un
// test, y este repo mergea mucho más seguido de lo que deploya. La diferencia
// es que éste tiene FECHA: no falla cuando rompés algo, falla cuando pasa el
// tiempo. Nadie lo introduce; se pudre solo.
//
// ── La tabla de fechas NO se copia acá ──
//
// Se lee de la firebase-tools instalada, que es exactamente la que después va
// a aceptar o rechazar el deploy. Copiarla sería otro cartel con fechas que se
// desactualiza en silencio cada vez que Google mueve una — y este repo ya sabe
// cómo termina eso.

/** Cuánto antes del decommission conviene enterarse. */
const DIAS_DE_AVISO = 180;

/** Los runtimes que pide `firebase.json`, como [{codebase, runtime}]. */
function runtimesConfigurados() {
  const fb = JSON.parse(fs.readFileSync(path.join(ROOT, "firebase.json"), "utf8"));
  const bloques = Array.isArray(fb.functions)
    ? fb.functions
    : fb.functions
      ? [fb.functions]
      : [];
  return bloques
    .filter((b) => b.runtime)
    .map((b) => ({ codebase: b.codebase || b.source || "default", runtime: b.runtime }));
}

/**
 * Chequeos del runtime. Van ANTES que todo lo demás a propósito: no necesitan
 * credenciales, ni red, ni el build hecho, así que son los únicos que corren
 * SIEMPRE. Los otros dos se saltean solos en una máquina sin login, y este no
 * debería irse con ellos — es el que tiene fecha de vencimiento.
 */
function chequearRuntime(problemas) {
  let configurados;
  try {
    configurados = runtimesConfigurados();
  } catch (e) {
    console.log(`preflight: no pude leer el runtime de firebase.json (${e.message})`);
    return;
  }
  if (!configurados.length) return;

  // El engines de `functions/package.json` tiene que decir lo mismo. Son dos
  // lugares para un solo hecho: `firebase.json` decide dónde CORRE y el
  // engines decide contra qué se instala y se testea. Desincronizados, CI
  // valida sobre una versión que producción no usa — y eso sale verde.
  let engines = null;
  let tipos = null;
  try {
    const pkg = JSON.parse(
      fs.readFileSync(path.join(ROOT, "functions", "package.json"), "utf8"),
    );
    engines = pkg.engines && pkg.engines.node;
    tipos = pkg.devDependencies && pkg.devDependencies["@types/node"];
  } catch {
    // Sin package.json legible no hay nada que comparar.
  }
  const mayorDe = (v) => {
    const m = /(\d+)/.exec(String(v || ""));
    return m ? m[1] : null;
  };
  for (const { codebase, runtime } of configurados) {
    const mayor = mayorDe(/^nodejs(\d+)$/.test(runtime) ? runtime : "");
    if (engines && mayor && mayorDe(engines) !== mayor) {
      problemas.push(
        `✗ ${codebase}: firebase.json pide ${runtime} y functions/package.json pide node "${engines}".\n` +
          `    CI instala y testea con el engines; producción corre con el runtime.\n` +
          `    Mientras no coincidan, el verde de CI es sobre otra versión de Node.`,
      );
    }
    // El TERCER lugar donde vive la misma versión, y el más silencioso: si
    // `@types/node` es de una major más nueva que el runtime, `tsc` acepta
    // APIs que en producción NO EXISTEN y el rojo llega recién en runtime.
    // Es exactamente la forma del bug de `module.registerHooks()` que documenta
    // `docs/security.md`. No corta el deploy —no lo rompe— pero sí vuelve el
    // verde de CI menos cierto de lo que parece.
    if (tipos && mayor && mayorDe(tipos) !== mayor) {
      console.warn(
        `\n  ⚠️ ${codebase}: @types/node es "${tipos}" y el runtime es ${runtime}.\n` +
          `     tsc está tipando contra una superficie de Node que no es la que corre.\n`,
      );
    }
  }

  const tabla = moduloDeFirebaseTools(
    "lib/deploy/functions/runtimes/supported/types.js",
  );
  const RUNTIMES = tabla && tabla.RUNTIMES;
  if (!RUNTIMES) {
    console.log("preflight: no pude leer la tabla de runtimes de firebase-tools");
    return;
  }

  const hoy = new Date();
  for (const { codebase, runtime } of configurados) {
    const info = RUNTIMES[runtime];
    if (!info) {
      console.log(`  ? ${codebase}: firebase-tools no conoce el runtime ${runtime}`);
      continue;
    }
    const muere = info.decommissionDate ? new Date(info.decommissionDate) : null;
    const dias = muere ? Math.ceil((muere - hoy) / 86400000) : null;

    if (info.status === "decommissioned" || (dias !== null && dias <= 0)) {
      problemas.push(
        `✗ ${codebase}: el runtime ${runtime} está DECOMISIONADO ` +
          `(${info.decommissionDate}).\n` +
          `    No se puede deployar ninguna función, ni un hotfix, hasta subirlo.\n` +
          `    Se cambia en DOS lugares: firebase.json y functions/package.json.`,
      );
    } else if (info.status === "deprecated" || (dias !== null && dias <= DIAS_DE_AVISO)) {
      console.warn(
        `\n  ⚠️ ${codebase}: el runtime ${runtime} se decomisiona el ` +
          `${info.decommissionDate} — faltan ${dias} días.\n` +
          `     Después de esa fecha no se puede deployar NADA de este codebase.\n` +
          `     Se cambia en firebase.json y en functions/package.json (y CI).\n`,
      );
    } else {
      console.log(
        `  ✓ runtime ${runtime} (${codebase}) — vive hasta ${info.decommissionDate}`,
      );
    }
  }
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

// ═══════════════════════════════════════════════════════════════════════════
//  Cuándo una huérfana deja de ser un estado y pasa a ser podredumbre
// ═══════════════════════════════════════════════════════════════════════════
//
// El mensaje de la guarda de huérfanas dice —bien— que hay DOS lecturas:
// "falta mergear la rama que las trae" o "hay que borrarlas a mano". La
// primera es legítima y TRANSITORIA. La segunda es un endpoint corriendo sin
// fuente auditable.
//
// Lo único que separa una de la otra es el TIEMPO. Una rama que todavía no se
// mergeó lleva horas, o un par de días. Una que lleva una semana desplegada y
// sin mergear no se está por mergear: está muerta, y la función que dejó viva
// hay que borrarla. Las dos lecturas terminan en la misma acción.
//
// Siete días porque es una semana entera: entra un fin de semana largo, una
// licencia corta, y el ciclo de review más lento que este repo tolera. Si a
// los siete días la rama sigue sin mergear, el problema ya no es el timing.
const DIAS_DE_GRACIA_HUERFANA = 7;

/**
 * Hace cuántos días una función quedó huérfana, o `null` si no se pudo datar.
 *
 * ── Por qué NO alcanza con `updateTime` ──
 *
 * `updateTime` es cuándo se deployó por última vez, no cuándo quedó huérfana.
 * Para los dos caminos que crean una huérfana da resultados distintos:
 *
 *   · Deployada desde una rama sin mergear → nació huérfana. `updateTime` ES
 *     la fecha de orfandad. Exacto.
 *   · Su declaración se borró del código (el caso `rcWebhook`, #1206) → vivió
 *     declarada y legítima un montón de tiempo antes de quedar huérfana.
 *     `updateTime` puede ser de hace meses y la orfandad de ayer.
 *
 * Usar `updateTime` solo en el segundo caso haría que el deploy siguiente al
 * merge del PR que borra una función CORTE, por algo que pasó hace una hora.
 * Eso es exactamente la guarda que el equipo aprende a saltear un viernes.
 *
 * ── De dónde sale la fecha buena ──
 *
 * `git log -S<nombre>` devuelve el último commit donde CAMBIÓ la cantidad de
 * apariciones de ese nombre en `functions/src`. Si la función se borró, ése es
 * el commit que la borró: la fecha exacta en que quedó huérfana. Si el nombre
 * nunca existió en esta historia —la rama sin mergear— no devuelve nada, y ahí
 * `updateTime` sí es la respuesta correcta.
 *
 * Se toma el MÁXIMO de las dos: si una función se borró del código y DESPUÉS
 * alguien la redeployó desde una rama, la orfandad vigente arranca en el
 * redeploy. Y el máximo siempre empuja la fecha hacia adelante, o sea hacia
 * MENOS días, o sea hacia no cortar. Cuando el instrumento duda, afloja.
 *
 * ── Los bordes, dichos en voz alta ──
 *
 * El pickaxe cuenta apariciones en todo `functions/src`, no sólo el export: si
 * un test que nombra la función se tocó después del borrado, gana esa fecha
 * más nueva. Vuelve a errar hacia menos días. Es una heurística para una
 * FECHA, no para decidir si hay huérfana —eso ya está decidido comparando la
 * API contra los endpoints compilados, que no es heurístico.
 */
function diasHuerfana(nombre, updateTime) {
  let borrado = null;
  try {
    // `execFileSync` y no `execSync`: sin shell no hay nada que escapar, y
    // `nombre` viene de la API de Google, no de este repo.
    borrado = require("child_process")
      .execFileSync(
        "git",
        ["log", "-1", "--format=%cI", `-S${nombre}`, "--", "functions/src"],
        { cwd: ROOT, encoding: "utf8" },
      )
      .trim();
  } catch {
    // Sin git, o un checkout sin historia: nos queda `updateTime`.
  }
  const fechas = [borrado, updateTime]
    .map((t) => (t ? new Date(t).getTime() : NaN))
    .filter((t) => Number.isFinite(t));
  if (!fechas.length) return null;
  return Math.floor((Date.now() - Math.max(...fechas)) / 86_400_000);
}

/**
 * La firma de un índice, para poder comparar los dos lados.
 *
 * El orden de los campos ES PARTE del índice —`(a, b)` y `(b, a)` son índices
 * distintos y sirven a queries distintas— así que la firma NO se ordena.
 *
 * `__name__` se descarta: Firestore lo agrega solo al final de todo índice
 * compuesto y `firestore.indexes.json` no lo declara. Compararlo haría que
 * TODOS dieran distinto, que es el modo de falla más aburrido posible — el
 * chequeo gritaría siempre y el equipo aprendería a ignorarlo.
 */
function firmaDeIndice(i) {
  const campos = (i.fields || [])
    .filter((f) => f.fieldPath !== "__name__")
    .map((f) => `${f.fieldPath}(${f.order || f.arrayConfig || "?"})`);
  return `${i.collectionGroup}: ${campos.join(", ")}`;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Los avisos que no cortan, pero que no se pueden perder en el scroll
// ═══════════════════════════════════════════════════════════════════════════
//
// El 2026-09-21, al mergear #1206 y deployar, `rcWebhook` quedó viva en
// producción sin una línea de código en `main`: un endpoint HTTP público sin
// fuente auditable. La guarda de huérfanas de más abajo CORRIÓ en ese deploy e
// imprimió el aviso correcto. No sirvió de nada.
//
// El bug no era la detección. Era la POSICIÓN:
//
//   1. El aviso salía en el medio de la salida del preflight.
//   2. Abajo de él, el propio preflight imprimía `preflight: OK`. Lo último
//      que uno lee es verde.
//   3. Encima de eso, `firebase deploy` escupe sus ~48 líneas.
//
// Un aviso tapado por su propio "OK" y por medio kilómetro de scroll no es un
// aviso: es decoración. Este bloque lo corre al final de todo y le pone marco,
// y la línea de cierre del preflight deja de poder decir un verde pelado
// mientras haya algo sin atender.
//
// ── Por qué acá y no un exit code distinto ──
//
// Se evaluó. No existe. `lifecycleHooks.js` de firebase-tools hace
// `else if (code !== 0) reject(...)` sobre el hook de `predeploy`: CUALQUIER
// código distinto de 0 aborta el deploy igual que `fallar()`, sólo que con un
// mensaje peor ("Command terminated with non-zero exit code 2"). No hay un
// escalón intermedio que el runner sepa leer. El único canal que queda para
// "seguí, pero mirá esto" es la salida de texto — así que el trabajo es
// ganarle al scroll, no inventar una señal que nadie escucha.
function resumirAvisos(avisos) {
  if (!avisos.length) return;
  const linea = "═".repeat(74);
  console.warn(
    `\n${linea}\n` +
      `  ⚠️  ${avisos.length} AVISO(S) QUE NO CORTAN ESTE DEPLOY — LEELOS IGUAL\n` +
      linea,
  );
  avisos.forEach((a) => console.warn(`\n  ${a}\n`));
  console.warn(linea);
}

/** Imprime los problemas encontrados y corta el deploy. */
function fallar(problemas) {
  console.error(`\npreflight: ${problemas.length} problema(s) — el deploy va a fallar.\n`);
  problemas.forEach((p) => console.error(`  ${p}\n`));
  process.exit(1);
}

async function main() {
  const problemas = [];
  // Lo que no corta el deploy pero tiene que sobrevivir al scroll. Se junta
  // acá y se imprime al final de todo: ver `resumirAvisos()`.
  const avisos = [];

  // Va primero y fuera de los `skip()` de abajo a propósito: no necesita
  // credenciales ni red, así que es el único chequeo que corre SIEMPRE —
  // incluso en la máquina sin login donde todo lo demás se saltea.
  chequearRuntime(problemas);
  if (problemas.length) fallar(problemas);

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

  // ── 4. Los índices declarados y los que existen dicen lo mismo ──────────
  //
  // El 2026-09-16 producción tenía CINCO índices que `firestore.indexes.json`
  // no declaraba —dos de `posts`, dos de `follows` y uno de `appointments`—,
  // todos en READY y todos con queries vivas detrás. Se acumularon porque un
  // índice nace fácil: alguien pega en el navegador el link que Firestore
  // ofrece cuando una query falla, y listo. Nada lo trae de vuelta al repo.
  //
  // POR QUÉ IMPORTA, en las dos direcciones:
  //
  //   · HUÉRFANO (vive en producción, el repo no lo declara)  →
  //     `firebase deploy --only firestore:indexes` OFRECE BORRARLO. El día que
  //     alguien confirme esa pregunta sin mirar, la query que lo necesita
  //     empieza a fallar en vivo, y falla lejos del deploy que la rompió.
  //   · FANTASMA (el repo lo declara, en producción no está) → hay una query
  //     que YA está fallando, o que va a fallar en cuanto alguien la pise.
  //     Hoy son cero; el día que no lo sean, hay que enterarse acá.
  //
  // Es de la misma familia que los otros tres chequeos de este archivo: nada
  // de esto es un test, así que el CI no puede verlo — y este repo mergea
  // mucho más seguido de lo que deploya.
  //
  // AVISA, NO CORTA. Un índice de más no rompe ningún deploy, y cortarlo por
  // esto sería la guarda que el equipo aprende a saltear un viernes. El
  // fantasma tampoco corta: si la query ya está fallando, frenar el deploy que
  // capaz la arregla es exactamente al revés.
  try {
    const declarados = new Set(
      JSON.parse(
        fs.readFileSync(path.join(ROOT, "firestore.indexes.json"), "utf8"),
      ).indexes.map(firmaDeIndice),
    );
    const res = await fetch(
      `https://firestore.googleapis.com/v1/projects/${project}` +
        "/databases/(default)/collectionGroups/-/indexes",
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const vivos = new Map();
    for (const i of (await res.json()).indexes || []) {
      // El nombre trae la colección embebida: .../collectionGroups/<col>/indexes/<id>
      const col = i.name.split("/collectionGroups/")[1].split("/")[0];
      vivos.set(firmaDeIndice({ collectionGroup: col, fields: i.fields }), i.state);
    }
    const huerfanos = [...vivos.keys()].filter((k) => !declarados.has(k));
    const fantasmas = [...declarados].filter((k) => !vivos.has(k));

    if (!huerfanos.length && !fantasmas.length) {
      console.log(`  ✓ ${vivos.size} índices — el repo y producción dicen lo mismo`);
    }
    // Van al resumen final por la misma razón que las funciones huérfanas: son
    // `console.warn` en el medio de la salida, con un `preflight: OK` abajo y
    // las ~48 líneas del deploy encima. Idéntica forma de perderse. No se les
    // pone escalada por antigüedad porque no hay de dónde sacar la fecha —
    // la API de Firestore no dice desde cuándo vive un índice, y un índice de
    // más tampoco es un endpoint público sin fuente.
    if (huerfanos.length) {
      avisos.push(
        `⚠️ ${huerfanos.length} índice(s) viven en producción y NO están en ` +
          "firestore.indexes.json:\n" +
          huerfanos.map((k) => `       ${k}`).join("\n") +
          "\n\n     Un deploy de índices puede OFRECER borrarlos. Sumalos al archivo.",
      );
    }
    if (fantasmas.length) {
      avisos.push(
        `⚠️ ${fantasmas.length} índice(s) declarados que en producción NO ` +
          "existen:\n" +
          fantasmas.map((k) => `       ${k}`).join("\n") +
          "\n\n     Hay una query que ya falla o va a fallar. Deployá los índices.",
      );
    }
  } catch (e) {
    console.log(`preflight: no pude chequear los índices (${e.message})`);
  }

  // ── 5. Las funciones vivas y las declaradas son las mismas ──────────────
  //
  // El 2026-09-16 producción tenía 50 funciones y `main` declaraba 48.
  // `maintainSessionFeedbackCounters` y `notifyOnSessionFinished` estaban
  // VIVAS y corriendo, y su código no existía en `main`: se habían deployado
  // desde una rama sin mergear. Se arreglaron solas al mergear #1153 y #1154,
  // pero nadie se había enterado hasta que este archivo contó 48 y la API
  // contestó 50.
  //
  // Mismo par de direcciones que los índices, y el mismo gatillo invertido:
  //
  //   · HUÉRFANA (vive, el código no la declara) → un `firebase deploy --only
  //     functions` completo OFRECE BORRARLA. Y mientras tanto corre código que
  //     nadie puede leer en `main`.
  //   · SIN DEPLOYAR (el código la declara, no existe) → normal ANTES de un
  //     deploy: son las que están por nacer. Se avisa igual, sin drama, porque
  //     después del deploy la lista tiene que quedar vacía y ahí sí significa
  //     otra cosa.
  //
  // ── AVISA, Y DESPUÉS DE UNA SEMANA CORTA ──
  //
  // El 2026-09-21 esta guarda funcionó y no sirvió: al mergear #1206 y
  // deployar, `rcWebhook` quedó viva en producción sin código en `main`, y el
  // aviso salió impreso, correcto, y se perdió en el scroll. Hubo que borrarla
  // a mano días después, cuando alguien se acordó.
  //
  // Se consideraron tres formas de arreglarlo, y las tres se escriben acá
  // porque la próxima persona que lea esto va a proponer alguna de las otras:
  //
  //   · Mandarla a `problemas` y listo. NO. El propio mensaje de abajo admite
  //     que una huérfana también puede ser "falta mergear la rama que las
  //     trae", que es legítimo y dura horas. Cortar el deploy de otro por eso
  //     es, palabra por palabra, la guarda que el encabezado de este archivo
  //     se prohíbe a sí mismo en la línea "vale más una guarda que a veces no
  //     opina que una que el equipo aprende a saltear".
  //   · Un exit code distinto para "aviso". NO EXISTE: firebase-tools hace
  //     `if (code !== 0) reject(...)` sobre el hook de predeploy. Está la
  //     evidencia completa arriba de `resumirAvisos()`.
  //   · Resumen al final. Necesario pero INSUFICIENTE solo: el aviso deja de
  //     estar tapado por su propio "OK", pero sigue siendo el mismo aviso con
  //     el mismo peso el día 1 y el día 30. Un cartel que nunca escala es un
  //     cartel que se aprende a ignorar — este repo ya tiene esa cicatriz.
  //
  // Va el resumen final MÁS la escalada por antigüedad, porque resuelven dos
  // mitades distintas del mismo bug: el resumen arregla que no se LEA, la
  // escalada arregla que no se ACTÚE. Y la escalada no rompe la regla de
  // fail-soft, porque no corta por "hay una huérfana": corta por "hace una
  // semana que hay una huérfana", que ya no es ningún estado transitorio.
  // Cómo se data eso, y por qué no alcanza `updateTime`, está en
  // `diasHuerfana()`.
  //
  // `sinDeployar` queda como estaba, en `console.log` sin drama: antes de un
  // deploy es el estado NORMAL —son las que están por nacer— y subirlas al
  // resumen sería llenarlo de ruido esperable. Un resumen que grita todos los
  // días es el mismo bug con otra cara.
  //
  // Va DESPUÉS del chequeo de frescura a propósito: ése ya tiene la lista de
  // funciones desplegadas, pero se pide de nuevo en vez de compartirla — son
  // dos guardas distintas, y cuando una se pone roja conviene leer el nombre y
  // saber cuál. Una llamada más a la API en un deploy no se nota.
  try {
    const r = await fetch(
      `https://cloudfunctions.googleapis.com/v2/projects/${project}` +
        "/locations/-/functions?pageSize=200",
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (!r.ok) throw new Error(`cloudfunctions ${r.status}`);
    // Mapa y no Set: `updateTime` es la mitad de la fecha de orfandad.
    const vivas = new Map(
      ((await r.json()).functions || []).map((f) => [
        f.name.split("/").pop(),
        f.updateTime,
      ]),
    );
    const declaradas = new Set(eps.map(([nombre]) => nombre));
    const huerfanas = [...vivas.keys()]
      .filter((n) => !declaradas.has(n))
      .map((n) => ({ nombre: n, dias: diasHuerfana(n, vivas.get(n)) }));
    const sinDeployar = [...declaradas].filter((n) => !vivas.has(n));

    // `dias === null` es "no la pude datar", y cae del lado de avisar. Una
    // guarda que corta cuando NO PUDO MEDIR es peor que no tenerla: enseña que
    // el rojo no significa nada.
    const podridas = huerfanas.filter(
      (h) => h.dias !== null && h.dias >= DIAS_DE_GRACIA_HUERFANA,
    );
    const frescas = huerfanas.filter((h) => !podridas.includes(h));

    if (!huerfanas.length && !sinDeployar.length) {
      console.log(`  ✓ ${vivas.size} funciones — el código y producción dicen lo mismo`);
    }
    if (frescas.length) {
      avisos.push(
        `⚠️ ${frescas.length} función(es) viven en producción y el código NO ` +
          "las declara:\n" +
          frescas
            .map(
              (h) =>
                `       ${h.nombre} — huérfana hace ` +
                `${h.dias === null ? "no sé cuántos" : h.dias} día(s)`,
            )
            .join("\n") +
          "\n\n     Corren código que no está en `main`. O falta mergear la rama que\n" +
          "     las trae, o hay que borrarlas a mano — un deploy completo va a\n" +
          "     ofrecer lo segundo.\n" +
          `     A los ${DIAS_DE_GRACIA_HUERFANA} días esto deja de ser un aviso ` +
          "y corta el deploy.",
      );
    }
    if (podridas.length) {
      problemas.push(
        `✗ ${podridas.length} función(es) llevan ${DIAS_DE_GRACIA_HUERFANA}+ días vivas en ` +
          "producción sin código en `main`:\n" +
          podridas
            .map((h) => `       ${h.nombre} — huérfana hace ${h.dias} día(s)`)
            .join("\n") +
          "\n    A esta altura ya no es 'falta mergear la rama': una rama que lleva\n" +
          `    ${DIAS_DE_GRACIA_HUERFANA}+ días desplegada y sin mergear está ` +
          "muerta. Son endpoints\n" +
          "    corriendo código que nadie puede auditar en `main`.\n" +
          "    Borralas con:\n" +
          podridas
            .map(
              (h) =>
                `      firebase functions:delete ${h.nombre} --project ${project}`,
            )
            .join("\n") +
          "\n    Si el código TIENE que existir, mergeá la rama y volvé a deployar.",
      );
    }
    if (sinDeployar.length) {
      console.log(
        `  · ${sinDeployar.length} declarada(s) todavía sin deployar: ` +
          `${sinDeployar.join(", ")}`,
      );
    }
  } catch (e) {
    console.log(`preflight: no pude chequear las funciones vivas (${e.message})`);
  }

  // Los avisos van ANTES de `fallar()` y antes del OK, o sea al final de todo
  // lo demás. En el camino que corta, los `problemas` quedan últimos a
  // propósito: son la razón por la que el deploy se muere y tienen que ser lo
  // último que se lee.
  resumirAvisos(avisos);
  if (problemas.length) fallar(problemas);

  // La línea de cierre NO puede ser un verde pelado mientras haya algo sin
  // atender. Ése fue literalmente el bug del 2026-09-21: el aviso de
  // `rcWebhook` se imprimió y abajo decía "preflight: OK".
  console.log(
    avisos.length
      ? `preflight: OK — con ${avisos.length} aviso(s) SIN ATENDER (arriba ↑)`
      : "preflight: OK",
  );
}

main().catch((e) => skip(`error inesperado (${e.message})`));
