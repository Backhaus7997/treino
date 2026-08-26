#!/usr/bin/env node
/**
 * Auditoría previa al merge de #780 (QA-SEC-013).
 *
 * ¿Por qué existe? Ese PR le agrega `users/{uid}.role == 'trainer'` al
 * `update` de `trainerPublicProfiles`. Eso **congela la edición** de cualquier
 * perfil cuyo dueño no tenga ese rol.
 *
 * Para los perfiles forjados por cuentas `athlete` es exactamente lo que se
 * busca. Para un PF legítimo cuyo `users/{uid}` tuviera el rol mal o ausente
 * sería una regresión: perdería la edición de su propio perfil comercial sin
 * ningún mensaje que se lo explique.
 *
 * Las reglas no pueden distinguir uno de otro, y desde una sesión de desarrollo
 * no hay forma de mirar los datos de producción. Por eso la verificación es
 * manual y va ANTES del merge.
 *
 * Uso:
 *
 *   export GOOGLE_APPLICATION_CREDENTIALS=/ruta/al/service-account.json
 *   node scripts/audit_trainer_profiles.mjs                 # sólo reporta
 *   node scripts/audit_trainer_profiles.mjs --project=X     # proyecto explícito
 *
 * Salida esperada para poder mergear: **cero huérfanos**. Si aparece alguno,
 * hay que decidir caso por caso si es un forjado (se borra) o un PF legítimo
 * con el rol mal seteado (se le corrige el rol) — el script NO escribe nada.
 */

import admin from "firebase-admin";

const projectArg = process.argv.find((a) => a.startsWith("--project="));
const projectId = projectArg ? projectArg.split("=")[1] : undefined;

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS && !projectId) {
  console.error(
    "Falta GOOGLE_APPLICATION_CREDENTIALS (o pasá --project=<id>).\n" +
      "Este script es de sólo lectura, pero necesita credenciales de Admin SDK."
  );
  process.exit(2);
}

admin.initializeApp(
  projectId ? { projectId } : { credential: admin.credential.applicationDefault() }
);

const db = admin.firestore();

const profiles = await db.collection("trainerPublicProfiles").get();
console.log(`trainerPublicProfiles vivos: ${profiles.size}`);

const orphans = [];
const missingUserDoc = [];

// Se leen los `users/{uid}` de a uno en vez de con getAll() a propósito: son
// pocos (el directorio de PFs es chico) y así el reporte puede distinguir
// "el doc privado no existe" de "existe pero el rol no es trainer", que son
// dos problemas distintos con dos arreglos distintos.
for (const doc of profiles.docs) {
  const uid = doc.id;
  const userSnap = await db.collection("users").doc(uid).get();

  if (!userSnap.exists) {
    missingUserDoc.push(uid);
    continue;
  }

  const role = userSnap.get("role");
  if (role !== "trainer") {
    orphans.push({ uid, role: role ?? "(sin campo role)" });
  }
}

console.log("");

if (orphans.length === 0 && missingUserDoc.length === 0) {
  console.log("✅ Cero huérfanos. El gate de `update` se puede mergear sin");
  console.log("   congelarle el perfil a ningún PF legítimo.");
  process.exit(0);
}

console.log("⚠️  NO mergear todavía. Encontrado:");
console.log("");

if (orphans.length > 0) {
  console.log(`  ${orphans.length} perfil(es) cuyo dueño NO tiene role 'trainer':`);
  for (const o of orphans) {
    console.log(`    - ${o.uid}  (users/${o.uid}.role = ${o.role})`);
  }
  console.log("");
  console.log("    Para cada uno hay que decidir a mano:");
  console.log("      · forjado por una cuenta athlete  -> borrar el perfil");
  console.log("      · PF legítimo con el rol mal      -> corregirle el rol");
  console.log("");
}

if (missingUserDoc.length > 0) {
  console.log(`  ${missingUserDoc.length} perfil(es) sin su doc \`users/{uid}\`:`);
  for (const uid of missingUserDoc) {
    console.log(`    - ${uid}`);
  }
  console.log("");
  console.log("    Estos son peores que los de arriba: la regla nueva hace");
  console.log("    get(users/{uid}) y sobre un doc inexistente la evaluación");
  console.log("    FALLA, así que el update se deniega igual. Probablemente");
  console.log("    sean restos de cuentas borradas — verificar contra el");
  console.log("    cascade de borrado antes de tocar nada.");
  console.log("");
}

process.exit(1);
