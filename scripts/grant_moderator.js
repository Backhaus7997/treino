#!/usr/bin/env node
/**
 * Otorga o revoca el claim `moderator: true` de un usuario.
 *
 *   node scripts/grant_moderator.js --uid=<uid>            # otorga
 *   node scripts/grant_moderator.js --uid=<uid> --revoke   # revoca
 *   node scripts/grant_moderator.js --list                 # quien lo tiene
 *
 * ## Por que esto es un script y no un callable
 *
 * Un callable que otorga el permiso de moderar ES el permiso de moderar: quien
 * pueda invocarlo se lo otorga a si mismo. La unica forma de que el claim
 * signifique algo es que su unica via de escritura este fuera del alcance de
 * cualquier usuario.
 *
 * Por eso vive aca, corre a mano, y exige la credencial de Admin SDK — la
 * misma frontera de #834: la ruta sale de `$TREINO_SA_KEY` y cualquier ruta
 * adentro de un arbol de git se rechaza antes de inicializar nada.
 *
 * ## Que habilita el claim
 *
 * Los tres callables de `functions/src/moderation/report-review.ts`:
 * `listPendingReports`, `resolveReport` y `moderationStats`. Nada mas. NO
 * abre ninguna coleccion en `firestore.rules` — `reports` y `report_reviews`
 * siguen con `allow read: if false` para todo cliente, moderador incluido.
 * El moderador lee por el Admin SDK, del otro lado del callable.
 *
 * ## Como se revoca
 *
 * Con `--revoke`. OJO: los custom claims viajan adentro del ID token, que dura
 * hasta una hora. Revocar NO corta la sesion en curso — el token viejo sigue
 * siendo valido hasta que expira. Si hace falta cortar YA, ademas de revocar
 * hay que invalidar los refresh tokens:
 *
 *     firebase auth:revoke-refresh-tokens <uid> --project prod
 *
 * ## Cuantos moderadores
 *
 * Uno para empezar. No hace falta un sistema de roles, y un sistema de roles
 * que nadie usa es superficie de ataque sin contraparte.
 */

const { inicializarAdmin } = require('./lib/admin');
const { getAuth } = require('firebase-admin/auth');

function arg(nombre) {
  const hit = process.argv.find((a) => a.startsWith(`--${nombre}=`));
  return hit ? hit.slice(nombre.length + 3) : null;
}

async function main() {
  const { app } = inicializarAdmin();
  const auth = getAuth(app);

  if (process.argv.includes('--list')) {
    // `listUsers` pagina de a 1000. Con un solo moderador esperado, una pagina
    // alcanza; si algun dia no alcanza, el contador de abajo lo va a decir.
    const page = await auth.listUsers(1000);
    const mods = page.users.filter((u) => u.customClaims?.moderator === true);
    console.log(`moderadores: ${mods.length} (de ${page.users.length} usuarios revisados)`);
    for (const u of mods) console.log(`  ${u.uid}  ${u.email ?? '(sin email)'}`);
    if (page.pageToken) {
      console.log('\n[!] Hay mas de 1000 usuarios: esta lista esta INCOMPLETA.');
      process.exitCode = 1;
    }
    return;
  }

  const uid = arg('uid');
  if (!uid) {
    console.error('Falta --uid=<uid>. Con --list se ve quien lo tiene hoy.');
    process.exitCode = 2;
    return;
  }

  const revocar = process.argv.includes('--revoke');
  const user = await auth.getUser(uid);

  // Los claims se REEMPLAZAN, no se mergean: `setCustomUserClaims` pisa el
  // objeto entero. Sin este spread, otorgar `moderator` borraria cualquier otro
  // claim que el usuario tuviera — hoy no hay ninguno, pero el dia que lo haya
  // el bug seria silencioso y aparecería lejos de acá.
  const claims = { ...(user.customClaims ?? {}) };
  if (revocar) delete claims.moderator;
  else claims.moderator = true;

  await auth.setCustomUserClaims(uid, claims);

  console.log(`${revocar ? 'revocado' : 'otorgado'}: moderator para ${uid} (${user.email ?? 'sin email'})`);
  console.log(`claims ahora: ${JSON.stringify(claims)}`);
  if (revocar) {
    console.log('\n[!] El claim viaja en el ID token, que dura hasta 1 hora.');
    console.log('    La sesion en curso SIGUE siendo moderadora hasta que expire.');
    console.log('    Para cortar ya: firebase auth:revoke-refresh-tokens ' + uid + ' --project prod');
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exitCode = 1;
});
