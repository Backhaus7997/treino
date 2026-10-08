'use strict';

/**
 * El generado `integration_test/support/seed_ids.dart` tiene que estar al día
 * con `lib/e2e_seed_contract.js`.
 *
 * Sin este test, el contrato sería la TERCERA copia del problema que vino a
 * resolver: alguien cambia un uid en el módulo, no regenera, y las suites
 * siguen importando el valor viejo. Y el modo de falla no es un rojo claro —
 * es un login que falla hablando de credenciales, o un deep link a un chat que
 * no existe.
 *
 * Corre en el job `scripts-test` de CI (`npm --prefix scripts test`), sin
 * emulador y sin credenciales: el módulo del contrato es puro a propósito.
 */

const test = require('node:test');
const assert = require('node:assert');
const { readFileSync } = require('fs');

const { renderDart, DESTINO } = require('../export_seed_ids');
const contrato = require('../lib/e2e_seed_contract');

test('seed_ids.dart está al día con e2e_seed_contract.js', () => {
  const commiteado = readFileSync(DESTINO, 'utf8');
  assert.strictEqual(
    commiteado,
    renderDart(),
    'seed_ids.dart quedó viejo. Regeneralo con: node scripts/export_seed_ids.js',
  );
});

// ── Control negativo ────────────────────────────────────────────────────────
//
// El test de arriba en verde no prueba que el guard FUNCIONE: probaría lo mismo
// si `renderDart()` devolviera siempre el contenido del archivo. Este de acá
// abajo obliga a que la comparación sepa decir que no.
test('el guard detecta una divergencia (control negativo)', () => {
  const commiteado = readFileSync(DESTINO, 'utf8');
  const adulterado = renderDart().replace(
    contrato.USERS.martin.uid,
    'seed-athlete-999',
  );
  assert.notStrictEqual(
    adulterado,
    renderDart(),
    'el reemplazo no cambió nada: el uid de Martín ya no aparece en el render, ' +
      'así que este control dejó de controlar algo',
  );
  assert.notStrictEqual(
    commiteado,
    adulterado,
    'el guard no distingue un uid cambiado del contenido real',
  );
});

// ── Invariantes del contrato que las rules dan por ciertas ───────────────────
//
// Estas no son gustos de estilo: son cosas que `firestore.rules` exige y que,
// si se rompen, el seed escribe igual (el Admin SDK saltea las rules) y el
// fallo aparece recién cuando un cliente intenta usar el documento.

test('el doc id de cada chat es members[0]_members[1], con members ordenado', () => {
  for (const [nombre, chat] of Object.entries(contrato.CHATS)) {
    assert.strictEqual(chat.members.length, 2, `${nombre}: members tiene que ser de 2`);
    assert.ok(
      chat.members[0] < chat.members[1],
      `${nombre}: members[0] < members[1] — lo exige firestore.rules:2296`,
    );
    assert.strictEqual(
      chat.chatId,
      `${chat.members[0]}_${chat.members[1]}`,
      `${nombre}: el doc id tiene que ser members[0]+'_'+members[1]`,
    );
  }
});

test('las tres ramas de chatCreateOk están cubiertas y son excluyentes', () => {
  const { coach, inquiry, social } = contrato.CHATS;

  assert.ok(coach.linkId, 'la rama Coach necesita linkId');
  assert.ok(!coach.kind, 'un chat de Coach no lleva kind: las ramas son excluyentes');

  assert.strictEqual(inquiry.kind, 'inquiry');
  assert.ok(!inquiry.linkId, 'una consulta no lleva linkId');

  assert.ok(!social.linkId && !social.kind, 'el chat social no lleva ninguna de las dos marcas');
});

test('el chat de Coach se apoya en un vínculo que la regla acepta', () => {
  // firestore.rules:2215 — sólo 'active' y 'paused'. 'pending' y 'terminated' no.
  const link = Object.values(contrato.LINKS).find((l) => l.id === contrato.CHATS.coach.linkId);
  assert.ok(link, 'el linkId del chat de Coach tiene que estar declarado en LINKS');
  assert.ok(
    ['active', 'paused'].includes(link.status),
    `el vínculo del chat de Coach está '${link.status}': la regla sólo acepta active/paused`,
  );
});

test('los uids no llevan guión bajo', () => {
  // `chatId.split('_')` (firestore.rules:2291) y `followId.split('_')`
  // (:1997) asumen exactamente UN separador. Un uid con guión bajo rompe los
  // dos acotes de QA-SEC-010 sin que nada lo avise.
  for (const [clave, u] of Object.entries(contrato.USERS)) {
    assert.ok(
      !u.uid.includes('_'),
      `${clave}: el uid '${u.uid}' tiene guión bajo y rompería split('_') en las rules`,
    );
  }
});
