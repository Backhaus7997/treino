'use strict';

/**
 * lib/e2e_seed_contract.js
 *
 * LOS IDENTIFICADORES QUE `seed_emulator_full.js` LE PROMETE A LAS SUITES E2E.
 *
 * Por qué existe este archivo
 * ───────────────────────────
 * Las cinco suites de `integration_test/` declaraban sus ids a mano, cada una
 * por su cuenta:
 *
 *     const String kChatId = 'REPLACE_WITH_SEEDED_CHAT_ID';
 *     const String kSeedEmail = 'e2e.athlete@treino.test';
 *
 * El segundo es peor que el primero, y por eso este archivo. Un
 * `REPLACE_WITH_*` es honesto: grita que falta algo. Un mail plausible que no
 * corresponde a NINGÚN usuario sembrado —el seed usa `martin@emulator.treino`—
 * se lee como un valor real y falla recién en el login, con un error que habla
 * de credenciales y no de seed. Es el §11.1 de AGENTS.md aplicado a un
 * fixture: una advertencia falsa desactiva la sospecha justo donde hacía falta.
 *
 * Cómo no se desincroniza
 * ───────────────────────
 * Este módulo es la ÚNICA fuente. De él salen dos consumidores:
 *
 *   · `seed_emulator_full.js` lo requiere para construir lo que siembra.
 *   · `export_seed_ids.js` genera `integration_test/support/seed_ids.dart`,
 *     que es lo que importan las suites.
 *
 * El archivo Dart es un GENERADO commiteado, y lo que impide que mienta es
 * `test/e2e_seed_contract.test.js`: regenera en memoria y compara contra el
 * commiteado. Si alguien cambia un uid acá y no regenera, ese test se pone
 * rojo en el job `scripts-test` de CI. Sin ese test, este archivo sería la
 * tercera copia del problema que vino a resolver.
 *
 * Es PURO a propósito: sin `require` de nada, sin `process.env`, sin efectos.
 * Tiene que poder cargarse desde un test sin emulador y sin credenciales.
 */

/// Orden de `members` y doc id de un chat.
///
/// Se escribe con `<` y no con `localeCompare` porque acá el orden ES la regla:
/// `firestore.rules:2296` exige `members[0] < members[1]`, que en CEL compara
/// code units, no locale. Para los uids de este seed las dos dan igual, pero el
/// día que un uid traiga un acento o un dígito raro, `localeCompare` diría que
/// sí y la regla que no.
function chatMembers(a, b) {
  return a < b ? [a, b] : [b, a];
}

function chatIdOf(a, b) {
  return chatMembers(a, b).join('_');
}

/// Doc id de una arista de follow: NO se ordena (`Follow.edgeId`,
/// lib/features/feed/domain/follow.dart:46). `{A}_{B}` y `{B}_{A}` son
/// documentos distintos — ahí vive la asimetría del modelo.
function followEdgeId(follower, followee) {
  return `${follower}_${followee}`;
}

/// Password de TODAS las cuentas sembradas. EMULATOR-ONLY, en texto plano a
/// propósito: este seed sólo corre contra el emulador (guard en
/// `seed_emulator_full.js`).
const PASSWORD = 'Emulator1234!';

/// Los usuarios que las suites necesitan nombrar. NO es el padrón completo —
/// el seed crea 3 PF y 13 alumnos. Acá están los que aparecen en algún flujo
/// E2E, y agregar uno es gratis; lo que cuesta es que un id viva en dos lados.
const USERS = {
  // Alumno principal: vinculado a Lautaro, con rutina asignada, sesiones
  // históricas, follow mutuo con Sofía y los tres tipos de post.
  martin: { uid: 'seed-athlete-001', email: 'martin@emulator.treino', displayName: 'Martín López' },
  // Sofía: follow mutuo con Martín. Es la contraparte del chat social.
  sofia: { uid: 'seed-athlete-002', email: 'sofia@emulator.treino', displayName: 'Sofía Ramírez' },
  // Valentina: sigue a Martín y él NO la sigue. Es la única arista de una vía,
  // y por lo tanto el único caso que distingue `follows` de `friendships`.
  valentina: { uid: 'seed-athlete-004', email: 'valentina@emulator.treino', displayName: 'Valentina Peralta' },
  // Nicolás: sin PF. Es quien manda la consulta a Diego.
  nicolas: { uid: 'seed-athlete-005', email: 'nicolas@emulator.treino', displayName: 'Nicolás Fernández' },
  // Lautaro: PF de Martín, vínculo `active`. Contraparte del chat de Coach.
  lautaro: { uid: 'seed-coach-001', email: 'coach.lautaro@emulator.treino', displayName: 'Lautaro Pérez' },
  // Diego: PF sin gym, acepta consultas. Contraparte del chat de consulta.
  diego: { uid: 'seed-coach-003', email: 'coach.diego@emulator.treino', displayName: 'Diego Aguirre' },
};

/// Vínculos PF↔alumno. Sólo `active`/`paused` habilitan un chat de Coach
/// (`firestore.rules:2215`), así que el status es parte del contrato.
const LINKS = {
  lautaroMartin: { id: 'seed-link-001', status: 'active' },
  diegoValentina: { id: 'seed-link-004', status: 'pending' },
};

/// Los tres chats sembrados, uno por cada rama EXCLUYENTE de `chatCreateOk`.
/// `otherUid` es lo que la ruta `/coach/chat/:chatId?other=:otherUid` espera.
const CHATS = {
  coach: {
    chatId: chatIdOf(USERS.martin.uid, USERS.lautaro.uid),
    members: chatMembers(USERS.martin.uid, USERS.lautaro.uid),
    linkId: LINKS.lautaroMartin.id,
  },
  inquiry: {
    chatId: chatIdOf(USERS.nicolas.uid, USERS.diego.uid),
    members: chatMembers(USERS.nicolas.uid, USERS.diego.uid),
    kind: 'inquiry',
  },
  social: {
    chatId: chatIdOf(USERS.martin.uid, USERS.sofia.uid),
    members: chatMembers(USERS.martin.uid, USERS.sofia.uid),
  },
};

/// Rutinas sembradas.
///
/// ⚠️  NO hay ninguna rutina de la que el alumno sea DUEÑO. Las dos rutinas con
/// contenido son `trainer-assigned` y la tercera es una plantilla `system`. Por
/// eso `my_routine_edit_test.dart` sigue con su `REPLACE_WITH_SEEDED_SELF_
/// ROUTINE_ID` sin llenar: no existe el documento que pide, y poner acá el id
/// de una asignada sería exactamente la mentira plausible que este archivo vino
/// a evitar — la suite abriría un editor sobre una rutina que el alumno no
/// puede editar, y fallaría hablando de permisos.
const ROUTINES = {
  asignadaAMartin: { id: 'seed-routine-001', name: 'Fuerza Base – 3 semanas' },
  plantillaSistema: { id: 'seed-routine-003', name: 'Full Body Principiante' },
};

module.exports = {
  PASSWORD,
  USERS,
  LINKS,
  CHATS,
  ROUTINES,
  chatMembers,
  chatIdOf,
  followEdgeId,
};
