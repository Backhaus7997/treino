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
 *   1. `functions/.secret.local` con el access token de PRUEBA de MP:
 *
 *        MP_ACCESS_TOKEN=TEST-xxxxxxxx-xxxxxx-...
 *
 *      ⚠️ El de PRUEBA, que empieza con `TEST-`. Con el de produccion este
 *      script abre un cobro REAL en la cuenta real. El chequeo de abajo lo
 *      frena, pero el chequeo esta para el descuido, no para reemplazar el
 *      cuidado.
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

const { initializeApp } = require("firebase-admin/app");
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
 * Nunca imprime el valor. Sólo mira el prefijo, que es público por diseño: MP
 * distingue los tokens de prueba con `TEST-` justo para que se puedan chequear
 * sin exponerlos.
 */
function exigirTokenDePrueba() {
  const ruta = path.join(__dirname, "..", "functions", ".secret.local");
  if (!fs.existsSync(ruta)) {
    console.error(
      "\n  No existe `functions/.secret.local`.\n\n" +
        "  El emulador de functions lee los `defineSecret()` de ahí. Sin ese\n" +
        "  archivo, `MP_ACCESS_TOKEN` llega vacío y el callable falla con un\n" +
        "  error de Mercado Pago que no dice cuál es el problema real.\n\n" +
        "  Crealo con el access token de PRUEBA:\n\n" +
        "    MP_ACCESS_TOKEN=TEST-xxxxxxxx-xxxxxx-...\n",
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
  if (!valor.startsWith("TEST-")) {
    console.error(
      "\n  ✗ MP_ACCESS_TOKEN NO es un token de prueba.\n\n" +
        "  Los de prueba empiezan con `TEST-`. Con el de producción este script\n" +
        "  abre un preapproval_plan REAL en la cuenta que factura.\n\n" +
        "  El de prueba sale de: MP Developers → tu app → Credenciales de prueba.\n",
    );
    process.exit(1);
  }
}

exigirTokenDePrueba();

const PROJECT_ID = "treino-dev";
const REGION = "southamerica-east1";
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST || "localhost:5001";
const CICLO = process.env.CICLO || "monthly";

// Un uid fijo y reconocible: el script es idempotente y se puede correr las
// veces que haga falta sin ensuciar el emulador con usuarios nuevos.
const UID = "verify-athlete-checkout";
const EMAIL = "verify-athlete-checkout@example.test";

initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();
const auth = getAuth();

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
  await auth.createUser({ uid: UID, email: EMAIL, password: "verificador-123" });

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

async function main() {
  console.log(`\nVerificando el checkout del alumno — ciclo ${CICLO}\n`);

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
  if (!destino.hostname.endsWith("mercadopago.com.ar") &&
      !destino.hostname.endsWith("mercadopago.com")) {
    fallar(`el init_point NO apunta a Mercado Pago: ${destino.hostname}`);
  }
  ok(`init_point de Mercado Pago: ${destino.origin}${destino.pathname}`);

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
