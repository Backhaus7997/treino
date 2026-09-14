#!/usr/bin/env node
/**
 * mp-firma-diagnostico.js — averigua CON QUE arma Mercado Pago el manifest de
 * `x-signature`, probando todas las variantes defendibles contra una firma real.
 *
 * ── Por que existe ──
 *
 * El webhook rechazaba el 100% de las notificaciones del simulador de MP con
 * `firma invalida`, y las tres causas razonables quedaron descartadas una por
 * una: los cuatro componentes del manifest estaban presentes (lo dijo el log),
 * el algoritmo esta fijado contra los fixtures del SDK oficial (los vectores
 * dorados de `mp-webhook.test.ts`), y el id correcto ya se probaba. Con tres
 * versiones distintas del secreto fallando, seguir proponiendo hipotesis era
 * perder el tiempo.
 *
 * Esto invierte el problema: en vez de adivinar como firma MP, se prueban
 * TODAS las formas plausibles hasta encontrar la que reproduce su firma.
 *
 * ── Por que es un script local y no un test ──
 *
 * Porque necesita el SECRETO, y el secreto no puede vivir en el repo, ni pasar
 * por un log, ni llegarle a nadie mas. Corre en la maquina del que lo tiene, lo
 * lee de una variable de entorno, y lo unico que sale de acá es el NOMBRE de la
 * variante ganadora.
 *
 * ── Como se usa ──
 *
 *   1. Dispara el simulador de MP y busca en los logs de `mpWebhook` la linea
 *      `firma invalida` con el objeto `diagnostico`.
 *   2. Copia de ahi los tres valores.
 *   3. Corre:
 *
 *        MP_WEBHOOK_SECRET='<la clave del panel>' \
 *        node scripts/mp-firma-diagnostico.js \
 *          --firma 'ts=1757...,v1=abc...' \
 *          --request-id '...' \
 *          --data-id '2c938084726fca480172750000000000'
 *
 *   4. Si alguna variante matchea, la imprime. Ese es el dato que faltaba.
 *
 * Si NINGUNA matchea, tambien es informacion: significa que el secreto no es el
 * que MP uso para firmar, y el problema no esta en el codigo.
 */

const { createHmac } = require("node:crypto");

function arg(nombre) {
  const i = process.argv.indexOf(`--${nombre}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

const secreto = process.env.MP_WEBHOOK_SECRET;
const firma = arg("firma");
const requestId = arg("request-id");
const dataId = arg("data-id");

if (!secreto || !firma) {
  console.error(
    "Faltan datos.\n\n" +
      "  MP_WEBHOOK_SECRET='<clave>' node scripts/mp-firma-diagnostico.js \\\n" +
      "    --firma 'ts=...,v1=...' --request-id '...' --data-id '...'\n",
  );
  process.exit(1);
}

// El header es `ts=...,v1=...`, en cualquier orden.
let ts = "";
let v1 = "";
for (const parte of firma.split(",")) {
  const i = parte.indexOf("=");
  if (i < 0) continue;
  const k = parte.slice(0, i).trim();
  const v = parte.slice(i + 1).trim();
  if (k === "ts") ts = v;
  else if (k === "v1") v1 = v;
}
if (!ts || !v1) {
  console.error(`No pude sacar ts y v1 de: ${firma}`);
  process.exit(1);
}

/**
 * Las piezas que pueden entrar al manifest, y las formas de combinarlas.
 *
 * Se prueban a lo bruto a proposito: el objetivo no es ser elegante, es que
 * NINGUNA forma razonable quede sin probar. Una sola corrida y se termina la
 * discusion.
 */
const ids = new Map([
  ["nada", undefined],
  ["data-id", dataId],
  ["data-id-minusculas", dataId && dataId.toLowerCase()],
  ["data-id-mayusculas", dataId && dataId.toUpperCase()],
]);

const requestIds = new Map([
  ["nada", undefined],
  ["request-id", requestId],
]);

/** Distintas formas de armar el template, todas vistas en doc o en SDKs. */
const plantillas = [
  ["punto-y-coma-con-cierre", (p) => p.map((x) => x + ";").join("")],
  ["punto-y-coma-sin-cierre", (p) => p.join(";")],
  ["coma", (p) => p.join(",")],
  ["amper", (p) => p.join("&")],
  ["sin-separador", (p) => p.join("")],
];

const secretos = new Map([
  ["tal-cual", secreto],
  ["sin-espacios", secreto.trim()],
]);

const hallazgos = [];
let probadas = 0;

for (const [nSec, sec] of secretos) {
  if (!sec) continue;
  for (const [nId, id] of ids) {
    for (const [nReq, req] of requestIds) {
      for (const [nTpl, armar] of plantillas) {
        const partes = [];
        if (id) partes.push(`id:${id}`);
        if (req) partes.push(`request-id:${req}`);
        partes.push(`ts:${ts}`);
        const manifest = armar(partes);

        for (const digest of ["hex", "base64"]) {
          probadas++;
          const calculada = createHmac("sha256", sec)
            .update(manifest)
            .digest(digest);
          if (calculada === v1) {
            hallazgos.push({
              secreto: nSec,
              id: nId,
              requestId: nReq,
              plantilla: nTpl,
              digest,
              manifest,
            });
          }
        }
      }
    }
  }
}

console.log(`\nProbadas ${probadas} combinaciones.\n`);

if (hallazgos.length === 0) {
  console.log("NINGUNA reprodujo la firma.\n");
  console.log("Eso NO es un callejon sin salida: significa que el problema no");
  console.log("esta en como armamos el manifest, sino en la CLAVE — la que");
  console.log("tenes no es la que Mercado Pago uso para firmar este evento.");
  console.log("\nSiguiente paso: revisar en el panel de MP que la clave sea la");
  console.log("del MISMO modo (prueba / productivo) que la URL a la que se");
  console.log("disparo la notificacion.");
  process.exit(2);
}

console.log("MATCHEO:\n");
for (const h of hallazgos) {
  console.log(`  secreto:   ${h.secreto}`);
  console.log(`  id:        ${h.id}`);
  console.log(`  requestId: ${h.requestId}`);
  console.log(`  plantilla: ${h.plantilla}`);
  console.log(`  digest:    ${h.digest}`);
  console.log(`  manifest:  ${h.manifest}`);
  console.log("");
}
console.log("Pasale ESTO al que este arreglando el webhook. No hace falta que");
console.log("le mandes el secreto ni la firma: con los nombres alcanza.\n");
