/**
 * lib/credenciales.js
 *
 * #834 — LA FRONTERA DE LA CREDENCIAL.
 *
 * El problema, medido: `scripts/sa-key.json` es la clave privada de
 * `firebase-adminsdk-fbsvc@treino-dev.iam.gserviceaccount.com`, la service
 * account por defecto del Admin SDK, con permisos amplios sobre el proyecto
 * donde viven los usuarios REALES (#826: `treino-dev` ES producción). Vivía
 * adentro del árbol del repo, con permisos 644, alcanzable por ruta relativa
 * desde cualquiera de los 27 worktrees de agente que corren en paralelo.
 *
 * Hoy hay una contención ACCIDENTAL: los scripts resuelven
 * `path.join(__dirname, 'sa-key.json')`, y `git worktree add` no copia
 * untracked, así que un agente adentro de un worktree falla. Pero es frágil:
 * `../../../scripts/sa-key.json` la alcanza igual, y con 644 la lee cualquier
 * proceso del usuario.
 *
 * Este módulo convierte esa contención accidental en contención DECLARADA:
 *
 *   1. La credencial se busca SÓLO en `$TREINO_SA_KEY` o en
 *      `$GOOGLE_APPLICATION_CREDENTIALS`, rutas explícitas. No hay default.
 *      Sin ninguna de las dos, se falla ruidosamente con instrucciones —
 *      nunca se cae a `./sa-key.json`. Ver `VAR_ADC` para por qué la segunda
 *      no se puede ignorar.
 *   2. Ninguna ruta adentro de un árbol de git funciona. Ni la del repo raíz,
 *      ni la de un worktree, ni `../../../scripts/sa-key.json`. Ver
 *      `arbolDeGitQueContiene`.
 *   3. El camino del emulador no toca nada de esto: sin credencial, anda. Pero
 *      "emulador" significa UNA cosa y sólo una: `FIRESTORE_EMULATOR_HOST`
 *      puesta, que es lo único que desvía el destino de estos scripts. Las
 *      otras variables de emulador —Auth, Storage, Realtime Database— sin ésa
 *      son un ambiente que se contradice y ABORTAN. Ver
 *      `VARS_DE_EMULADOR_PARCIALES`.
 *   4. La identidad que se verifica es la EFECTIVA — el `client_email` de la
 *      credencial que realmente se cargó — no el project id declarado. Ver
 *      `evaluarProduccion` y el comentario largo que la precede.
 *
 * ESTE MÓDULO DECIDE; NO APLICA. Quien lo invoca es `lib/admin.js`, la única
 * puerta por la que los 44 scripts inicializan el Admin SDK. La separación es a
 * propósito: acá no hay dependencias ni efectos, así que se testea entero con
 * stubs; allá está lo impuro. Un módulo perfecto sin llamadores no contiene
 * nada — que fue exactamente el estado en el que nació este archivo.
 *
 * Sin dependencias nuevas: `scripts/` sólo tiene `firebase-admin`, y todo acá
 * es `node:fs` / `node:path`. Todo lo observable entra por parámetro
 * (`env`, `existeEntrada`, `leerArchivo`, `modoDeArchivo`) para que
 * `scripts/test/credenciales.test.js` lo ejercite con stubs, sin tocar el
 * filesystem ni necesitar una credencial de verdad.
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

/** La variable canónica que dice dónde está la credencial. No hay default (#834). */
const VAR_RUTA = 'TREINO_SA_KEY';

/**
 * La variable que lee el ADC de Google POR SU CUENTA.
 *
 * No la elegimos nosotros y no la podemos ignorar: `admin.initializeApp()` sin
 * argumentos, `admin.credential.applicationDefault()` y `new GoogleAuth()` la
 * leen del ambiente adentro de la librería, sin pasar por acá. Si la dejáramos
 * afuera del resolutor, `GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json`
 * seguiría cargando la clave de producción desde adentro del repo y la frontera
 * sería decorativa. Por eso se acepta como origen —con las MISMAS reglas que
 * `TREINO_SA_KEY`— y se valida ANTES de inicializar nada.
 */
const VAR_ADC = 'GOOGLE_APPLICATION_CREDENTIALS';

/** Dónde recomendamos guardarla. Fuera del repo, fuera de cualquier worktree. */
const RUTA_RECOMENDADA = path.join('~', '.config', 'treino', 'sa-key.json');

/**
 * La misma ruta, pero para PEGAR EN UNA SHELL.
 *
 * `export VAR="~/x"` NO expande el `~` —está entre comillas— y deja la variable
 * con un tilde literal. Nuestro resolutor lo expande igual, pero cualquier otra
 * herramienta que lea la variable se come el error. Un comando que se ofrece
 * para copiar y pegar tiene que andar sin asteriscos.
 */
const RUTA_RECOMENDADA_SHELL = '"$HOME/.config/treino/sa-key.json"';

/**
 * Proyectos de Firebase donde viven usuarios reales.
 *
 * `treino-dev` está acá a propósito: el nombre dice "dev" por razones
 * históricas (el project ID no se puede cambiar), pero es PRODUCCIÓN (#826).
 * Es exactamente el error que este módulo tiene que frenar.
 *
 * `treino-prod` HOY NO EXISTE —`treino-dev` es el único proyecto Firebase de
 * TREINO, ver scripts/README.md—; queda en la lista para el día que se cree,
 * porque el costo de tenerlo de más es cero y el de tenerlo de menos no.
 */
const PROYECTOS_DE_PRODUCCION = new Set(['treino-dev', 'treino-prod']);

/** Raíz del checkout desde el que se cargó este módulo (`<repo>/scripts/lib`). */
const RAIZ_DEL_REPO = path.resolve(__dirname, '..', '..');

/**
 * LA ÚNICA VARIABLE QUE DESVÍA EL DESTINO DE ESTOS SCRIPTS.
 *
 * Los 44 scripts de `scripts/` escriben en Firestore, y `FIRESTORE_EMULATOR_HOST`
 * es lo único que hace que esa escritura aterrice en localhost. No es una de
 * cuatro variables equivalentes: es LA condición.
 */
const VAR_EMULADOR_FIRESTORE = 'FIRESTORE_EMULATOR_HOST';

/**
 * Las que DICEN emulador y NO desvían Firestore.
 *
 * Cada una redirige otro producto —Auth, Storage, Realtime Database— y ninguna
 * toca Firestore. Un proceso con sólo una de éstas puesta está, para todo lo
 * que estos scripts hacen, apuntando a LA NUBE.
 *
 * Estuvieron en la misma lista que la de arriba, sumadas con un `.some()`, y
 * ese `.some()` era el bug: `FIREBASE_DATABASE_EMULATOR_HOST` —de un producto
 * que TREINO ni usa— alcanzaba para que el contexto dijera `modo: 'emulador'`,
 * y con eso el script se saltea la credencial ENTERA (#834) y apaga el cartel
 * de producción (#826) mientras escribe en el `treino-dev` real. Si la máquina
 * tiene ADC de `gcloud` puesto, esa escritura además AUTENTICA.
 *
 * Es la misma familia que el #838 —una etiqueta que dice EMULADOR mientras los
 * bytes van a producción— y se cierra con la misma regla que `storage_target.js`
 * fijó para el par Firestore/Storage: o todo redirigido, o nada; la mezcla
 * ABORTA antes de la primera escritura. Ver `mensajeEmuladorIncoherente`.
 */
const VARS_DE_EMULADOR_PARCIALES = [
  'FIREBASE_AUTH_EMULATOR_HOST',
  'FIREBASE_STORAGE_EMULATOR_HOST',
  'FIREBASE_DATABASE_EMULATOR_HOST',
];

/**
 * Error con `codigo` estable para que los tests afirmen sobre el caso y no
 * sobre el texto, y el texto pueda mejorar sin romperlos.
 */
class ErrorDeCredencial extends Error {
  constructor(codigo, mensaje) {
    super(mensaje);
    this.name = 'ErrorDeCredencial';
    this.codigo = codigo;
  }
}

// ── Resolución de la ruta ──────────────────────────────────────────────────

/** Expande un `~` inicial. `~` sin barra también, para no sorprender a nadie. */
function expandirHome(ruta, home) {
  if (ruta === '~') return home;
  if (ruta.startsWith(`~${path.sep}`) || ruta.startsWith('~/')) {
    return path.join(home, ruta.slice(2));
  }
  return ruta;
}

/**
 * Devuelve la raíz del árbol de git que contiene `rutaAbsoluta`, o `null`.
 *
 * Sube directorio por directorio buscando una entrada `.git`. Tiene que ser
 * "existe la entrada" y no "es un directorio": en un worktree `.git` es un
 * ARCHIVO con un `gitdir:` adentro. Si sólo miráramos directorios, los 26
 * worktrees pasarían el control — que es justo el agujero que hay que cerrar.
 *
 * Efecto secundario deseado: si alguien guarda la credencial adentro de un
 * repo de dotfiles, también se rechaza. Es correcto: una clave privada viva
 * adentro de cualquier árbol versionado está a un `git add -f` del desastre.
 */
function arbolDeGitQueContiene(rutaAbsoluta, existeEntrada) {
  let dir = path.dirname(rutaAbsoluta);
  for (;;) {
    if (existeEntrada(path.join(dir, '.git'))) return dir;
    const padre = path.dirname(dir);
    if (padre === dir) return null;
    dir = padre;
  }
}

/**
 * EL MENSAJE QUE DECIDE SI LA MIGRACIÓN ES DE UN COMANDO O DE UNA TARDE.
 *
 * Cablear los scripts rompe, a propósito, a todo el que hoy tenga la clave en
 * `scripts/sa-key.json`. Ese corte sólo es defendible si lo primero que ve la
 * persona es el comando exacto que la arregla — no un "credential not found"
 * que la mande a leer el README a ver qué cambió.
 */
function mensajeSinVariable() {
  return [
    '',
    `ERROR: no hay credencial — falta ${VAR_RUTA} (#834).`,
    '',
    'La clave del Admin SDK ya no se busca adentro del repo, y no hay default.',
    '',
    'MIGRACIÓN (una sola vez, copiá y pegá):',
    '',
    '  mkdir -p ~/.config/treino',
    '  mv scripts/sa-key.json ~/.config/treino/sa-key.json',
    '  chmod 600 ~/.config/treino/sa-key.json',
    `  export ${VAR_RUTA}=${RUTA_RECOMENDADA_SHELL}`,
    '',
    'Si ya la tenés guardada afuera del repo, alcanza con la última línea',
    'apuntada a dónde esté. Poné esa línea en tu ~/.zshrc o ~/.bashrc para que',
    'sobreviva a la terminal.',
    '',
    'O, mejor: para desarrollo local no hace falta NINGUNA credencial.',
    '',
    '  ./scripts/emulator.sh',
    '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/<script>.js',
    '',
    `(${VAR_ADC} también sirve como origen, con las mismas reglas: tiene`,
    ' que apuntar afuera de todo árbol de git.)',
    '',
    'Detalle en scripts/README.md → "Credenciales (#834)".',
    '',
  ].join('\n');
}

/**
 * Las dos variables seteadas a archivos distintos.
 *
 * No es un detalle de estilo: nosotros inicializamos el Admin SDK con la ruta
 * que resolvemos, pero cualquier otra librería Google del proceso lee
 * `GOOGLE_APPLICATION_CREDENTIALS` sola. Con dos rutas distintas el mismo
 * proceso corre con DOS identidades según quién pregunte, y cuál escribe en
 * producción depende del orden de las llamadas. Se frena.
 */
function mensajeVariablesEnConflicto(rutaCanonica, rutaAdc) {
  return [
    '',
    `ERROR: ${VAR_RUTA} y ${VAR_ADC} apuntan a archivos distintos (#834).`,
    '',
    `  ${VAR_RUTA} : ${rutaCanonica}`,
    `  ${VAR_ADC} : ${rutaAdc}`,
    '',
    'Con dos rutas distintas el proceso tiene dos identidades: nosotros usamos',
    'la primera y cualquier otra librería Google usa la segunda. Cuál termina',
    'escribiendo depende del orden de las llamadas — eso no se adivina.',
    '',
    'Dejá una sola, o poné las dos en la misma ruta:',
    '',
    `  unset ${VAR_ADC}`,
    '',
  ].join('\n');
}

function mensajeDentroDeGit(ruta, raiz, variable = VAR_RUTA) {
  const esEsteRepo = raiz === RAIZ_DEL_REPO;
  return [
    '',
    `ERROR: ${variable} apunta adentro de un árbol de git. Rechazado (#834).`,
    '',
    `  ruta : ${ruta}`,
    `  repo : ${raiz}${esEsteRepo ? '  (este checkout)' : ''}`,
    '',
    'Una clave privada de producción no puede vivir en un árbol versionado:',
    'la alcanza cualquier worktree por ruta relativa, la lee cualquier proceso,',
    'y está a un `git add -f` de terminar publicada.',
    '',
    'Movela afuera y volvé a apuntar la variable:',
    '',
    '  mkdir -p ~/.config/treino',
    `  mv "${ruta}" ~/.config/treino/sa-key.json`,
    '  chmod 600 ~/.config/treino/sa-key.json',
    `  export ${variable}=${RUTA_RECOMENDADA_SHELL}`,
    '',
  ].join('\n');
}

function mensajeNoExiste(ruta, variable = VAR_RUTA) {
  return [
    '',
    `ERROR: ${variable} apunta a un archivo que no existe (#834).`,
    '',
    `  ruta : ${ruta}`,
    '',
    'Revisá la ruta, o corré contra el emulador y no hace falta credencial:',
    '',
    '  FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/<script>.js',
    '',
  ].join('\n');
}

/**
 * Resuelve DE DÓNDE sale la credencial: `{ ruta, variable }`.
 *
 * Dos orígenes válidos, con reglas idénticas: `TREINO_SA_KEY` (canónica) y
 * `GOOGLE_APPLICATION_CREDENTIALS` (la que el ADC lee solo, ver `VAR_ADC`).
 * La canónica gana; si las dos están y apuntan a archivos distintos, se frena
 * en vez de elegir por nosotros.
 *
 * NO lee el archivo — eso es `cargarCredencial`.
 */
function resolverOrigenCredencial({
  env = process.env,
  existeEntrada = (p) => fs.existsSync(p),
  home = os.homedir(),
} = {}) {
  const crudoCanonico = (env[VAR_RUTA] || '').trim();
  const crudoAdc = (env[VAR_ADC] || '').trim();

  if (!crudoCanonico && !crudoAdc) {
    throw new ErrorDeCredencial('SIN_VARIABLE', mensajeSinVariable());
  }

  const absoluta = (crudo) => path.resolve(expandirHome(crudo, home));

  if (crudoCanonico && crudoAdc) {
    const a = absoluta(crudoCanonico);
    const b = absoluta(crudoAdc);
    if (a !== b) {
      throw new ErrorDeCredencial('VARIABLES_EN_CONFLICTO', mensajeVariablesEnConflicto(a, b));
    }
  }

  const variable = crudoCanonico ? VAR_RUTA : VAR_ADC;
  const ruta = absoluta(crudoCanonico || crudoAdc);

  // El control del árbol de git va ANTES del de existencia a propósito: si
  // alguien apunta a `scripts/sa-key.json`, el mensaje útil es "esa ruta está
  // prohibida y acá está cómo migrarla", no "no existe".
  const raiz = arbolDeGitQueContiene(ruta, existeEntrada);
  if (raiz) {
    throw new ErrorDeCredencial('DENTRO_DEL_REPO', mensajeDentroDeGit(ruta, raiz, variable));
  }

  if (!existeEntrada(ruta)) {
    throw new ErrorDeCredencial('NO_EXISTE', mensajeNoExiste(ruta, variable));
  }

  return { ruta, variable };
}

/** La ruta sola, para el que no necesita saber de qué variable salió. */
function resolverRutaCredencial(io = {}) {
  return resolverOrigenCredencial(io).ruta;
}

// ── Carga y permisos ───────────────────────────────────────────────────────

/**
 * `true` si el archivo es legible por el grupo o por el resto del mundo.
 * Con 644 —lo que había— la lee cualquier proceso del usuario y cualquier
 * herramienta que ande hurgando el filesystem.
 */
function permisosDemasiadoAbiertos(modo) {
  return typeof modo === 'number' && (modo & 0o077) !== 0;
}

/**
 * Lee y parsea la credencial. Devuelve `{ ruta, credencial, avisos }`.
 *
 * `avisos` son cosas que NO justifican frenar el script pero sí gritar: hoy,
 * permisos más abiertos que 600.
 */
function cargarCredencial({
  env = process.env,
  existeEntrada = (p) => fs.existsSync(p),
  leerArchivo = (p) => fs.readFileSync(p, 'utf8'),
  modoDeArchivo = (p) => fs.statSync(p).mode,
  home = os.homedir(),
} = {}) {
  const { ruta, variable } = resolverOrigenCredencial({ env, existeEntrada, home });

  let credencial;
  try {
    credencial = JSON.parse(leerArchivo(ruta));
  } catch (err) {
    throw new ErrorDeCredencial(
      'ILEGIBLE',
      `\nERROR: no se pudo leer ${variable} como JSON (#834).\n\n  ruta : ${ruta}\n  causa: ${err.message}\n`,
    );
  }

  if (!credencial || typeof credencial !== 'object' || !credencial.client_email) {
    throw new ErrorDeCredencial(
      'SIN_CLIENT_EMAIL',
      [
        '',
        `ERROR: la credencial de ${variable} no tiene \`client_email\` (#834).`,
        '',
        `  ruta : ${ruta}`,
        '',
        'Sin `client_email` no se puede verificar la identidad EFECTIVA, que es',
        'lo único que distingue producción de cualquier otra cosa. Se frena.',
        '',
      ].join('\n'),
    );
  }

  const avisos = [];
  let modo = null;
  try {
    modo = modoDeArchivo(ruta);
  } catch {
    // No poder stat-ear no es motivo para frenar; el aviso se pierde y ya.
  }
  if (permisosDemasiadoAbiertos(modo)) {
    avisos.push(
      `AVISO (#834): ${ruta} es legible por otros (modo ${(modo & 0o777).toString(8)}). ` +
        `Cerralo con:  chmod 600 "${ruta}"`,
    );
  }

  return { ruta, variable, credencial, avisos };
}

// ── Identidad efectiva ─────────────────────────────────────────────────────

/**
 * Proyecto al que pertenece la service account, deducido del `client_email`.
 *
 * Dos formas que emite Google:
 *   firebase-adminsdk-fbsvc@<proyecto>.iam.gserviceaccount.com  ← la nuestra
 *   <proyecto>@appspot.gserviceaccount.com                      ← la de App Engine
 *
 * Devuelve `null` si no matchea ninguna (p. ej. `<num>-compute@developer...`),
 * y ahí el que decide es `evaluarProduccion` con lo que le quede.
 */
function proyectoDeLaIdentidad(clientEmail) {
  if (typeof clientEmail !== 'string') return null;
  const iam = /@([a-z0-9][a-z0-9-]*)\.iam\.gserviceaccount\.com$/i.exec(clientEmail);
  if (iam) return iam[1].toLowerCase();
  const appspot = /^([a-z0-9][a-z0-9-]*)@appspot\.gserviceaccount\.com$/i.exec(clientEmail);
  if (appspot) return appspot[1].toLowerCase();
  return null;
}

/**
 * ¿Esto es producción?
 *
 * LA PREGUNTA NO ES "¿A QUÉ PROJECT ID APUNTA?", ES "¿QUIÉN SOY?".
 *
 * El guard viejo miraba el project id, y el revisor de #843 encontró por dónde
 * se escapa: `firebase use` escribe `activeProjects` en
 * `~/.config/configstore/firebase-tools.json`, ese valor le gana al default de
 * `.firebaserc`, y no deja NINGÚN rastro adentro del repo. Mirando el proyecto
 * declarado no hay forma de saberlo.
 *
 * La identidad no se escapa: una credencial de
 * `…@treino-dev.iam.gserviceaccount.com` sólo puede escribir en `treino-dev`,
 * diga lo que diga el project id que la acompaña. Si la SA es de un proyecto de
 * producción, ESTO ES PRODUCCIÓN, venga de donde venga la configuración.
 *
 * Por eso el `||`: la identidad manda, y el project id declarado sólo puede
 * SUMAR sospecha (una credencial rara apuntada a un proyecto real), nunca
 * restarla.
 *
 * @returns {{produccion: boolean, motivo: string|null, proyectoDeLaIdentidad: string|null, projectIdDeclarado: string|null}}
 */
function evaluarProduccion(credencial, { projectIdDeclarado = null } = {}) {
  const cred = credencial || {};
  const identidad = proyectoDeLaIdentidad(cred.client_email);
  const declarado = (projectIdDeclarado || cred.project_id || null) &&
    String(projectIdDeclarado || cred.project_id).toLowerCase();

  if (identidad && PROYECTOS_DE_PRODUCCION.has(identidad)) {
    return {
      produccion: true,
      motivo:
        `la service account \`${cred.client_email}\` pertenece a \`${identidad}\`, ` +
        `que es PRODUCCIÓN (#826)` +
        (declarado && declarado !== identidad
          ? ` — el project id declarado dice \`${declarado}\`, y NO manda: ` +
            `la credencial sólo puede escribir en \`${identidad}\``
          : ''),
      proyectoDeLaIdentidad: identidad,
      projectIdDeclarado: declarado,
    };
  }

  if (declarado && PROYECTOS_DE_PRODUCCION.has(declarado)) {
    return {
      produccion: true,
      motivo: `el proyecto declarado es \`${declarado}\`, que es PRODUCCIÓN (#826)`,
      proyectoDeLaIdentidad: identidad,
      projectIdDeclarado: declarado,
    };
  }

  return {
    produccion: false,
    motivo: null,
    proyectoDeLaIdentidad: identidad,
    projectIdDeclarado: declarado,
  };
}

// ── Emulador ───────────────────────────────────────────────────────────────

/**
 * `true` si el DESTINO DE ESTOS SCRIPTS —Firestore— está redirigido al emulador.
 *
 * No es "¿alguna variable sugiere emulador?". Es la pregunta exacta que el
 * llamador necesita responder, porque de esto cuelgan las dos decisiones más
 * peligrosas del módulo: saltear la credencial (#834) y apagar el cartel de
 * producción (#826). Una condición más laxa que el redirect real convierte las
 * dos en una mentira — ver `VARS_DE_EMULADOR_PARCIALES`.
 *
 * Vacío o whitespace NO cuenta: exportar la variable en blanco no desvía nada.
 *
 * Se chequea ANTES que la credencial en todo el flujo: contra el emulador no
 * hay nada que proteger y no debe hacer falta ninguna variable (#834, (c)).
 */
function usandoEmulador(env = process.env) {
  return Boolean((env[VAR_EMULADOR_FIRESTORE] || '').trim());
}

/** Las variables de emulador PARCIAL que están puestas. Lista, para nombrarlas. */
function emuladoresParcialesPuestos(env = process.env) {
  return VARS_DE_EMULADOR_PARCIALES.filter((v) => Boolean((env[v] || '').trim()));
}

/**
 * EL MENSAJE DEL DESFASAJE: el ambiente dice emulador y Firestore no lo está.
 *
 * Se ABORTA en vez de seguir por el camino de la nube, aunque seguir sería
 * "seguro" (pediría credencial y gritaría el cartel). El motivo es el mismo por
 * el que `storage_target.js` aborta en vez de auto-redirigir: quien exportó
 * `FIREBASE_AUTH_EMULATOR_HOST` cree que está corriendo local, y una corrida que
 * escribe en producción mientras el operador cree otra cosa es el #838 exacto.
 * Entre romper la corrida y ejecutarla contra un destino que nadie eligió, se
 * rompe la corrida.
 */
function mensajeEmuladorIncoherente(puestas) {
  return [
    '',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '⛔  ABORTADO: el ambiente dice EMULADOR pero Firestore NO está redirigido.',
    '⛔',
    ...puestas.map((v) => `⛔    ${v} = puesta`),
    `⛔    ${VAR_EMULADOR_FIRESTORE} = NO PUESTA  ← la única que desvía Firestore`,
    '⛔',
    '⛔  Estos scripts escriben en Firestore. Ninguna de las variables de arriba',
    '⛔  lo desvía: Auth, Storage y Realtime Database van cada uno por su lado.',
    '⛔  Sin la de Firestore, esta corrida escribe en `treino-dev`, que ES',
    '⛔  PRODUCCIÓN (#826) — y lo haría sin cartel y sin pedir credencial,',
    '⛔  porque el proceso se cree local.',
    '⛔',
    '⛔  Si querés el emulador, agregá la que falta:',
    `⛔    export ${VAR_EMULADOR_FIRESTORE}=localhost:8080`,
    '⛔',
    '⛔  Si querés correr contra la nube, sacá las otras del ambiente y leé el',
    '⛔  cartel que sale después: es producción.',
    `⛔    unset ${puestas.join(' ')}`,
    '⛔',
    '⛔  Contexto: #834 / #838 / AGENTS.md → Entornos',
    '⛔ ─────────────────────────────────────────────────────────────────────',
    '',
  ].join('\n');
}

/**
 * En modo emulador NO se exige credencial — pero si HAY una variable apuntando
 * adentro de un árbol de git, se frena igual.
 *
 * `FIRESTORE_EMULATOR_HOST` desvía Firestore a localhost y NADA MÁS. Storage y
 * Auth de Admin siguen yendo a la nube con lo que resuelva el ADC. O sea que
 * `FIRESTORE_EMULATOR_HOST=… GOOGLE_APPLICATION_CREDENTIALS=scripts/sa-key.json`
 * es un camino real a producción con la clave leída desde adentro del repo —
 * justo lo que este issue elimina, disfrazado de "corriendo local".
 *
 * Sólo se rechaza ESE caso. Que la variable falte, que apunte a un archivo que
 * no existe o que las dos discrepen no frena nada: contra el emulador no hacen
 * falta credenciales y romper el desarrollo local por una variable vieja sería
 * cobrarle a todo el mundo un riesgo que no existe.
 */
function rechazarSiApuntaAlRepo(io) {
  try {
    resolverOrigenCredencial(io);
  } catch (err) {
    // Sólo se tragan los veredictos del resolutor. Cualquier otra excepción
    // —un error de filesystem, un bug acá adentro— se propaga: un `catch` que
    // se come todo convierte un error real en un silencio, y este archivo
    // decide si algo escribe en producción.
    if (!(err instanceof ErrorDeCredencial)) throw err;
    if (err.codigo === 'DENTRO_DEL_REPO') throw err;
    // El resto (falta la variable, no existe el archivo, discrepan) es
    // irrelevante sin credencial: contra el emulador no hace falta ninguna.
  }
}

// ── Punto de entrada para los scripts ──────────────────────────────────────

/**
 * Lo que un script necesita saber antes de inicializar el Admin SDK.
 *
 * Emulador  → `{ modo: 'emulador', projectId, produccion: false }`, sin tocar
 *             el resolutor ni pedir credencial. SÓLO con Firestore redirigido:
 *             es lo único que hace que `modo: 'emulador'` sea cierto para lo
 *             que estos scripts escriben.
 * Si no     → `{ modo: 'credencial', ruta, credencial, produccion, motivo, … }`
 *             o `ErrorDeCredencial` con el mensaje de qué hacer.
 */
function resolverContexto({
  env = process.env,
  projectIdEmulador = 'treino-dev',
  ...io
} = {}) {
  // La coherencia va PRIMERO: si el ambiente se contradice, el error útil es
  // "tu emulador no desvía Firestore", no "falta la credencial". El segundo
  // manda a exportar la clave de producción para arreglar una corrida que la
  // persona quería local.
  const parciales = emuladoresParcialesPuestos(env);
  if (!usandoEmulador(env) && parciales.length > 0) {
    throw new ErrorDeCredencial('EMULADOR_INCOHERENTE', mensajeEmuladorIncoherente(parciales));
  }

  if (usandoEmulador(env)) {
    rechazarSiApuntaAlRepo({ env, ...io });
    return {
      modo: 'emulador',
      projectId: projectIdEmulador,
      produccion: false,
      motivo: null,
      avisos: [],
    };
  }

  const { ruta, variable, credencial, avisos } = cargarCredencial({ env, ...io });
  const veredicto = evaluarProduccion(credencial);

  return {
    modo: 'credencial',
    ruta,
    variable,
    credencial,
    avisos,
    ...veredicto,
  };
}

module.exports = {
  VAR_RUTA,
  VAR_ADC,
  VAR_EMULADOR_FIRESTORE,
  VARS_DE_EMULADOR_PARCIALES,
  RUTA_RECOMENDADA,
  RUTA_RECOMENDADA_SHELL,
  PROYECTOS_DE_PRODUCCION,
  RAIZ_DEL_REPO,
  ErrorDeCredencial,
  arbolDeGitQueContiene,
  resolverOrigenCredencial,
  resolverRutaCredencial,
  permisosDemasiadoAbiertos,
  cargarCredencial,
  proyectoDeLaIdentidad,
  evaluarProduccion,
  usandoEmulador,
  emuladoresParcialesPuestos,
  rechazarSiApuntaAlRepo,
  resolverContexto,
};
