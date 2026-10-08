#!/usr/bin/env node
/**
 * verify_athlete_checkout.js — el checkout del alumno, end-to-end contra el
 * emulador y contra el SANDBOX REAL de Mercado Pago.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  POR QUE ESTE SCRIPT EXISTE Y NO ALCANZA CON `npm test`
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * Los tests de `mp-create-athlete-preapproval.test.ts` corren contra un doble
 * de `MpClient`: verifican NUESTRA logica —el gate de rol, que el monto salga
 * del servidor, la huella anti-doble-click— pero nunca le hablan a Mercado
 * Pago. Son verdes desde el dia uno y no prueban que MP acepte el body que le
 * mandamos.
 *
 * Eso importa mas de lo normal acá: el parseo de RevenueCat estaba calcado de
 * la documentacion y no de una respuesta observada, y por eso nunca se supo si
 * andaba. Este camino no puede repetir ese error.
 *
 * Lo que este script SI prueba, y ningun test unitario puede:
 *
 *   1. Que MP acepte el `preapproval_plan` que arma `create-athlete-preapproval`
 *      con un token real (de prueba), y devuelva un `init_point` navegable.
 *   2. Que el plan quede escrito en `mp_plans` con `producto: 'athlete'` — el
 *      discriminador sin el cual un plan de alumno reconciliado por el camino
 *      del PF le escribiria un `subscription` de entrenador.
 *   3. Que el monto que viajo a MP sea el del SERVIDOR y no uno del cliente.
 *
 * ── Lo que NO prueba, y hay que saberlo ──
 *
 * El webhook. `mpWebhook` necesita que MP pueda alcanzarlo por una URL publica,
 * y el emulador no lo es. La mitad "el pago acredita" queda afuera de este
 * script por construccion, no por olvido.
 *
 * ═══════════════════════════════════════════════════════════════════════════
 *  COMO SE CORRE
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *   1. `functions/.secret.local` con el Access Token de PRUEBA de MP:
 *
 *        MP_ACCESS_TOKEN=APP_USR-...
 *
 *      Sale de: MP Developers -> tu app -> Credenciales de PRUEBA -> Access
 *      Token. **No la Public Key**, que esta justo arriba y empieza igual.
 *
 *      ⚠️ Los dos tipos de credencial usan el MISMO prefijo `APP_USR-`, asi
 *      que mirandolas no se distinguen. Con la de produccion este script abre
 *      un `preapproval_plan` REAL en la cuenta que factura. Por eso el chequeo
 *      de abajo le pregunta a MP de quien es el token en vez de adivinar.
 *
 *   2. El emulador arriba, con functions:
 *
 *        ./scripts/emulator.sh
 *
 *   3. Y acá:
 *
 *        FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *        FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *        node scripts/verify_athlete_checkout.js
 *
 *      Opcional: `CICLO=annual` para probar el anual (default `monthly`).
 */

const { inicializarAdmin, PROJECT_ID_EMULADOR } = require("./lib/admin");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const fs = require("fs");
const path = require("path");

// ── Guarda de entorno, con el mismo molde que `seed_emulator_full.js` ──
//
// Sin estas variables el Admin SDK sale a PRODUCCION: crearia un usuario real
// y le abriria un cobro real. Falla cerrado y explica como arrancar.
if (
  !process.env.FIREBASE_AUTH_EMULATOR_HOST ||
  !process.env.FIRESTORE_EMULATOR_HOST
) {
  console.error(
    "\n  Faltan las variables del emulador. Sin ellas esto toca PRODUCCION.\n\n" +
      "  FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \\\n" +
      "  FIRESTORE_EMULATOR_HOST=localhost:8080 \\\n" +
      "  node scripts/verify_athlete_checkout.js\n",
  );
  process.exit(1);
}

/**
 * Que el emulador esté cargado con el token de PRUEBA y no con el de producción.
 *
 * Este script no consume el token —lo consume el emulador— pero lee el mismo
 * archivo para poder frenar antes de tocar nada. Con un token de producción,
 * `createAthletePreapproval` abre un `preapproval_plan` REAL en la cuenta real
 * de Mercado Pago: no cobra sin que alguien pague, pero deja basura en una
 * cuenta que factura y un `init_point` vivo que alguien puede pagar.
 *
 * ── ⚠️ Acá había un chequeo de PREFIJO, y estaba mal ──
 *
 * Decía: «los de prueba empiezan con `TEST-`». **No es cierto.** Medido el
 * 2026-09-22 contra el panel real: la pantalla «Credenciales de prueba» de una
 * aplicación de MP muestra una Public Key `APP_USR-421c07cf-…`. Los dos tipos
 * de credencial usan HOY el mismo prefijo; el `TEST-` es del modelo viejo de
 * sandbox.
 *
 * O sea que aquel chequeo hacía las dos cosas mal a la vez: rechazaba un token
 * de prueba legítimo, y —peor— no habría podido distinguir uno de producción,
 * porque se ven igual.
 *
 * El error de fondo es el mismo que el del `endsWith` de `esHostDeMercadoPago`,
 * treinta líneas más abajo: **validar la forma del valor en vez de preguntarle
 * a la fuente.** Los dos se escribieron el mismo día.
 *
 * ── Lo que sí distingue, porque lo dice MP ──
 *
 * `GET /users/me` devuelve la cuenta dueña del token, y las de prueba traen
 * `test_user` en `tags`. Verificado contra la cuenta de prueba de TREINO:
 *
 *   { id: 3671163614, nickname: "TESTUSER1735334405…",
 *     tags: ["user_product_seller", "test_user", "normal"] }
 *
 * Es una llamada de red en un script que ya depende de la red, y a cambio la
 * respuesta es del emisor de la credencial en vez de una inferencia sobre un
 * string. El id se imprime para poder cruzarlo contra el que muestra el panel.
 *
 * Nunca imprime el token.
 */
async function exigirTokenDePrueba() {
  const ruta = path.join(__dirname, "..", "functions", ".secret.local");
  if (!fs.existsSync(ruta)) {
    console.error(
      "\n  No existe `functions/.secret.local`.\n\n" +
        "  El emulador de functions lee los `defineSecret()` de ahí. Sin ese\n" +
        "  archivo, `MP_ACCESS_TOKEN` llega vacío y el callable falla con un\n" +
        "  error de Mercado Pago que no dice cuál es el problema real.\n\n" +
        "  Crealo con el Access Token de PRUEBA (MP Developers → tu app →\n" +
        "  Credenciales de prueba):\n\n" +
        "    MP_ACCESS_TOKEN=APP_USR-…\n",
    );
    process.exit(1);
  }

  const linea = fs
    .readFileSync(ruta, "utf8")
    .split(/\r?\n/)
    .find((l) => l.trimStart().startsWith("MP_ACCESS_TOKEN="));

  if (!linea) {
    console.error(
      "\n  `functions/.secret.local` existe pero no define MP_ACCESS_TOKEN.\n",
    );
    process.exit(1);
  }

  const valor = linea.slice(linea.indexOf("=") + 1).trim().replace(/^["']|["']$/g, "");

  let cuenta;
  try {
    const r = await fetch("https://api.mercadopago.com/users/me", {
      headers: { Authorization: `Bearer ${valor}` },
    });
    cuenta = await r.json();
    if (!r.ok || !cuenta?.id) {
      console.error(
        `\n  ✗ Mercado Pago rechazó el token (HTTP ${r.status}).\n\n` +
          `  ${JSON.stringify(cuenta).slice(0, 200)}\n\n` +
          "  Revisá que sea el ACCESS TOKEN y no la Public Key: están uno\n" +
          "  debajo del otro en el panel y los dos empiezan con `APP_USR-`.\n",
      );
      process.exit(1);
    }
  } catch (e) {
    console.error(
      `\n  ✗ No se pudo consultar /users/me: ${e.message}\n\n` +
        "  Este chequeo necesita red. Es a propósito: no hay forma local de\n" +
        "  distinguir un token de prueba de uno de producción.\n",
    );
    process.exit(1);
  }

  const tags = Array.isArray(cuenta.tags) ? cuenta.tags : [];
  if (!tags.includes("test_user")) {
    console.error(
      "\n  ✗ El token NO es de una cuenta de prueba.\n\n" +
        `  Pertenece a: ${cuenta.nickname || "?"} (id ${cuenta.id})\n` +
        `  tags: ${JSON.stringify(tags)}\n\n` +
        "  Una cuenta de prueba trae `test_user` ahí. Con este token, el script\n" +
        "  abriría un preapproval_plan REAL en la cuenta que factura.\n\n" +
        "  El correcto sale de: MP Developers → tu app → Credenciales de prueba\n" +
        "  → Access Token. En esa misma pantalla, «Datos de las credenciales de\n" +
        "  prueba» muestra el User ID que tiene que coincidir con el de arriba.\n",
    );
    process.exit(1);
  }

  ok(`token de PRUEBA — cuenta ${cuenta.id} (${cuenta.nickname})`);
}

const PROJECT_ID = PROJECT_ID_EMULADOR;
const REGION = "southamerica-east1";
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST || "localhost:5001";
const CICLO = process.env.CICLO || "monthly";

// Un uid fijo y reconocible: el script es idempotente y se puede correr las
// veces que haga falta sin ensuciar el emulador con usuarios nuevos.
const UID = "verify-athlete-checkout";
const EMAIL = "verify-athlete-checkout@example.test";

// Credenciales: la UNICA puerta (#834). `scripts/test/frontera.test.js`
// verifica que ningun script de `scripts/` resuelva la credencial por su
// cuenta, y este archivo entro en rojo por llamar a `initializeApp` directo.
// El guard tenia razon: el punto de `lib/admin` es que exista UN solo lugar
// que decide contra que proyecto se escribe.
const { app } = inicializarAdmin({ projectId: PROJECT_ID });
const db = getFirestore(app);
const auth = getAuth(app);

const ok = (m) => console.log(`  ✓ ${m}`);
const info = (m) => console.log(`  · ${m}`);
function fallar(m, detalle) {
  console.error(`\n  ✗ ${m}`);
  if (detalle !== undefined) {
    console.error(
      `\n${typeof detalle === "string" ? detalle : JSON.stringify(detalle, null, 2)}\n`,
    );
  }
  process.exit(1);
}

/**
 * Deja al alumno en el unico estado en el que el callable lo deja comprar.
 *
 * Son TRES condiciones y la segunda es la que sorprende: un alumno con un
 * `trainer_links` activo NO puede suscribirse, y el callable lo rechaza con
 * `failed-precondition` diciendo "tu entrenador ya paga tu lugar". Es correcto
 * —el vinculado no paga nunca, su PF ya paga ese cupo— pero significa que un
 * alumno tomado del seed normal, que viene vinculado, hace fallar este script
 * por una razon que no tiene nada que ver con el checkout.
 */
async function prepararAlumno() {
  try {
    await auth.deleteUser(UID);
  } catch {
    // No existia. Es el caso normal de la primera corrida.
  }
  // Sin password A PROPOSITO: el ingreso es por custom token, asi que ninguna
  // hace falta. Habia un literal aca y `gitleaks` lo marco — con razon, aunque
  // fuera de un usuario descartable: la regla no puede distinguirlos, y un
  // repo que amnistia literales de password deja de detectar los que importan.
  await auth.createUser({ uid: UID, email: EMAIL });

  await db.collection("users").doc(UID).set({
    role: "athlete",
    firstName: "Verificador",
    lastName: "De Checkout",
    email: EMAIL,
  });

  // Que no arrastre vinculos ni suscripcion de una corrida anterior.
  const vinculos = await db
    .collection("trainer_links")
    .where("athleteId", "==", UID)
    .get();
  await Promise.all(vinculos.docs.map((d) => d.ref.delete()));

  const planesViejos = await db.collection("mp_plans").where("uid", "==", UID).get();
  await Promise.all(planesViejos.docs.map((d) => d.ref.delete()));

  ok(`alumno listo: ${UID} (role: athlete, sin vinculo, sin planes)`);
}

/** Un ID token del emulador de Auth, que es lo que el callable espera. */
async function idToken() {
  const custom = await auth.createCustomToken(UID);
  const r = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/` +
      `v1/accounts:signInWithCustomToken?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  const j = await r.json();
  if (!r.ok || !j.idToken) fallar("no se pudo obtener un idToken del emulador", j);
  return j.idToken;
}

/** Llama al callable por HTTP, que es como lo llama la landing. */
async function llamarCallable(token) {
  const url = `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/createAthletePreapproval`;
  info(`POST ${url}`);

  let r;
  try {
    r = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ data: { cycle: CICLO, locale: "es" } }),
    });
  } catch (e) {
    fallar(
      `no se pudo llegar al emulador de functions en ${FUNCTIONS_HOST}. ` +
        "¿Está levantado con `./scripts/emulator.sh`?",
      e.message,
    );
  }

  const j = await r.json().catch(() => null);
  if (!r.ok || j?.error) {
    // El mensaje de MP viaja adentro del error y es lo unico que dice por que
    // rechazo el body. Sin imprimirlo, un fallo acá es indistinguible de otro.
    fallar(`el callable devolvio ${r.status}`, j ?? "(respuesta ilegible)");
  }
  return j.result;
}

/**
 * Si un hostname es REALMENTE de Mercado Pago.
 *
 * ── Por qué no alcanza con `endsWith` ──
 *
 * Acá decía `hostname.endsWith("mercadopago.com")`, y eso da **true** para
 * `fake-mercadopago.com`: el sufijo puede venir precedido por cualquier cosa.
 * Lo marcó CodeQL como `js/incomplete-url-substring-sanitization`, severidad
 * alta, y tenía razón.
 *
 * El error de fondo no es el operador: es validar la FORMA del valor en vez de
 * compararlo contra una lista. Es exactamente lo que `src/lib/destinos.ts` de
 * la landing existe para no hacer con el `?next=`.
 *
 * Por eso: igualdad exacta contra los dominios conocidos, o subdominio con el
 * PUNTO adelante —`auth.mercadopago.com.ar` sí, `evilmercadopago.com.ar` no—.
 * El punto es lo único que separa un subdominio de un prefijo arbitrario.
 *
 * Que acá el valor venga de una respuesta de MP y no de un usuario no cambia
 * nada: una aserción que se puede satisfacer con un host ajeno no está
 * verificando lo que dice verificar.
 */
const DOMINIOS_DE_MP = ["mercadopago.com.ar", "mercadopago.com"];

function esHostDeMercadoPago(hostname) {
  const h = String(hostname).toLowerCase();
  return DOMINIOS_DE_MP.some((d) => h === d || h.endsWith(`.${d}`));
}

async function main() {
  console.log(`\nVerificando el checkout del alumno — ciclo ${CICLO}\n`);

  // Primero de todo: que el token sea de prueba. Antes de crear el usuario y
  // mucho antes de llamar al callable, que es lo que abriría el plan en MP.
  await exigirTokenDePrueba();

  await prepararAlumno();

  const resultado = await llamarCallable(await idToken());

  // ── 1. El init_point ──
  const init = resultado?.init_point ?? resultado?.initPoint;
  if (typeof init !== "string" || !init) {
    fallar("el callable no devolvio un init_point", resultado);
  }
  let destino;
  try {
    destino = new URL(init);
  } catch {
    fallar(`el init_point no es una URL: ${init}`);
  }
  if (!esHostDeMercadoPago(destino.hostname)) {
    fallar(`el init_point NO apunta a Mercado Pago: ${destino.hostname}`);
  }
  // ⚠️ La URL **entera**, con su query string.
  //
  // Acá decía `${destino.origin}${destino.pathname}`, que imprime
  // `https://www.mercadopago.com.ar/subscriptions/checkout` y se COME el
  // `?preapproval_plan_id=…` — que es lo único que identifica el plan. El
  // resultado era un link que no se puede abrir: el script terminaba diciendo
  // "abrí el init_point" después de haberlo recortado.
  //
  // Un valor sensible se recorta al imprimirlo; este no lo es —es una URL de
  // checkout pública, la misma que el alumno recibe— y sin el query no sirve
  // para nada.
  ok("init_point de Mercado Pago:");
  console.log(`\n    ${init}\n`);

  // ── 2. El discriminador, que es la pieza central del diseño ──
  //
  // Sin `producto: 'athlete'`, `reconcile-my-checkout.ts` consulta `mp_plans`
  // por uid SIN filtrar por tipo, y un plan de alumno reconciliado por el
  // camino del PF le escribiria un `subscription` de entrenador.
  const planes = await db.collection("mp_plans").where("uid", "==", UID).get();
  if (planes.empty) fallar("no se escribio ningun documento en mp_plans");
  if (planes.size !== 1) {
    fallar(`se esperaba UN plan y hay ${planes.size}`, planes.docs.map((d) => d.id));
  }
  const plan = planes.docs[0].data();

  if (plan.producto !== "athlete") {
    fallar(
      `mp_plans.producto es ${JSON.stringify(plan.producto)} y tiene que ser "athlete"`,
      plan,
    );
  }
  ok(`mp_plans/${planes.docs[0].id} — producto: "athlete", cycle: "${plan.cycle}"`);

  if (plan.cycle !== CICLO) {
    fallar(`el ciclo guardado (${plan.cycle}) no es el pedido (${CICLO})`);
  }

  // ── 3. El monto salio del servidor ──
  //
  // El cliente manda `{cycle, locale}` y nada mas. Que el monto exista y sea
  // positivo es la unica prueba desde acá de que lo puso el backend.
  const monto = plan.amount ?? plan.transactionAmount ?? plan.montoArs;
  if (monto !== undefined && (typeof monto !== "number" || monto <= 0)) {
    fallar(`el monto guardado es invalido: ${JSON.stringify(monto)}`, plan);
  }
  if (monto !== undefined) ok(`monto del servidor: ARS ${monto}`);
  else info("el plan no guarda el monto — vive sólo en MP, ver el init_point");

  console.log(
    `\n  Listo. Abrí el init_point con una CUENTA DE PRUEBA compradora y pagá` +
      `\n  con una tarjeta de prueba (titular APRO para que apruebe).\n` +
      `\n  Lo que sigue —que el pago acredite— NO lo cubre este script: el` +
      `\n  webhook necesita una URL pública y el emulador no lo es.\n`,
  );
}

main().catch((e) => fallar("error inesperado", e.stack || e.message));
