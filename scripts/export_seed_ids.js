'use strict';

/**
 * scripts/export_seed_ids.js
 *
 * Genera `integration_test/support/seed_ids.dart` a partir de
 * `lib/e2e_seed_contract.js`, que es la única fuente de los identificadores
 * que `seed_emulator_full.js` le promete a las suites E2E.
 *
 * USO
 *   node scripts/export_seed_ids.js          # escribe el archivo
 *   node scripts/export_seed_ids.js --check  # falla si el commiteado difiere
 *
 * NO toca Firestore, no pide credenciales y no necesita el emulador: sólo lee
 * un módulo puro y escribe un archivo de texto. Por eso no pasa por
 * `lib/admin.js` — no hay ninguna frontera que cruzar.
 *
 * El `--check` es lo que corre `test/e2e_seed_contract.test.js`. Sin él, este
 * generador sería un tercer lugar donde los ids pueden quedar viejos.
 */

const { readFileSync, writeFileSync } = require('fs');
const path = require('path');

const contrato = require('./lib/e2e_seed_contract');

const DESTINO = path.resolve(__dirname, '../integration_test/support/seed_ids.dart');

function dartString(valor) {
  // Los valores del contrato son uids, mails y nombres. Sólo el displayName
  // puede traer comillas o backslash; se escapan igual para todos, porque un
  // generador que asume que su input es inofensivo deja de ser cierto la
  // primera vez que alguien agrega un apellido con apóstrofo.
  return `'${String(valor).replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
}

function renderUsuario(clave, u) {
  return [
    `const SeedUser k${clave[0].toUpperCase()}${clave.slice(1)} = SeedUser(`,
    `  uid: ${dartString(u.uid)},`,
    `  email: ${dartString(u.email)},`,
    `  displayName: ${dartString(u.displayName)},`,
    `);`,
  ].join('\n');
}

function renderDart() {
  const { PASSWORD, USERS, CHATS, ROUTINES, LINKS } = contrato;

  const usuarios = Object.entries(USERS)
    .map(([clave, u]) => renderUsuario(clave, u))
    .join('\n\n');

  return `// GENERADO POR scripts/export_seed_ids.js — NO EDITAR A MANO.
//
// Fuente: scripts/lib/e2e_seed_contract.js
// Regenerar: node scripts/export_seed_ids.js
//
// Los identificadores que \`scripts/seed_emulator_full.js\` deja en el emulador.
// Las suites de \`integration_test/\` los importan de acá en vez de declararlos
// cada una por su cuenta: mientras vivieron en cinco archivos, cuatro de ellos
// decían \`e2e.athlete@treino.test\`, un mail que no correspondía a ningún
// usuario sembrado y que fallaba en el login hablando de credenciales.
//
// \`scripts/test/e2e_seed_contract.test.js\` regenera este archivo en memoria y
// lo compara con esta copia: si el contrato cambió y nadie regeneró, ese test
// se pone rojo en CI antes de que una suite corra con un id fantasma.

/// Una cuenta sembrada por \`seed_emulator_full.js\`.
class SeedUser {
  const SeedUser({
    required this.uid,
    required this.email,
    required this.displayName,
  });

  final String uid;
  final String email;
  final String displayName;
}

/// Password de TODAS las cuentas sembradas. EMULATOR-ONLY.
const String kSeedPassword = ${dartString(PASSWORD)};

${usuarios}

/// Chat de Coach: \`linkId\` apunta a un \`trainer_links\` \`${LINKS.lautaroMartin.status}\`.
const String kCoachChatId = ${dartString(CHATS.coach.chatId)};
const String kCoachChatLinkId = ${dartString(CHATS.coach.linkId)};

/// Chat de consulta: \`kind: 'inquiry'\`, sin vínculo entre las partes.
const String kInquiryChatId = ${dartString(CHATS.inquiry.chatId)};

/// Chat social: se apoya en el follow mutuo aceptado entre Martín y Sofía.
const String kSocialChatId = ${dartString(CHATS.social.chatId)};

/// Rutina \`trainer-assigned\` de Lautaro a Martín, con 3 semanas de contenido.
const String kAssignedRoutineId = ${dartString(ROUTINES.asignadaAMartin.id)};

/// Plantilla del sistema, sin \`assignedTo\`.
const String kSystemTemplateRoutineId = ${dartString(ROUTINES.plantillaSistema.id)};

// ⚠️  NO hay constante de "rutina propia del alumno" porque el seed no siembra
// ninguna: las dos rutinas con contenido son \`trainer-assigned\` y la tercera es
// una plantilla \`system\`. \`my_routine_edit_test.dart\` necesita una rutina de la
// que el alumno sea DUEÑO, y poner acá el id de una asignada haría que esa suite
// abriera el editor sobre algo que el alumno no puede editar — fallaría hablando
// de permisos, que es el peor lugar posible para descubrir que falta un fixture.
`;
}

function main() {
  const generado = renderDart();
  const chequear = process.argv.includes('--check');

  if (chequear) {
    let actual;
    try {
      actual = readFileSync(DESTINO, 'utf8');
    } catch {
      console.error(`FALTA ${path.relative(process.cwd(), DESTINO)}.\nRegeneralo con:  node scripts/export_seed_ids.js`);
      process.exit(1);
    }
    if (actual !== generado) {
      console.error(
        `${path.relative(process.cwd(), DESTINO)} NO está al día con ` +
        'scripts/lib/e2e_seed_contract.js.\n' +
        'Regeneralo con:  node scripts/export_seed_ids.js',
      );
      process.exit(1);
    }
    console.log('seed_ids.dart al día.');
    return;
  }

  writeFileSync(DESTINO, generado, 'utf8');
  console.log(`✓ ${path.relative(process.cwd(), DESTINO)}`);
}

module.exports = { renderDart, DESTINO };

if (require.main === module) main();
