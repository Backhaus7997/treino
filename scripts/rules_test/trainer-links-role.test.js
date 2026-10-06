'use strict';

/**
 * Firestore Security Rules test suite — `trainer_links` create role gate.
 *
 * `trainer_links/create` es la colección que "rules-hardening Slice C" NO
 * tocó. Las cinco que sí (`payments`, `athlete_billing`, `measurements`,
 * `performance_tests`, `appointments`) exigen
 * `get(users/{uid}).data.role == 'trainer'` sobre el que ESCRIBE; acá el
 * campo no-auto-declarable es el OTRO, el `trainerId`, porque el create lo
 * hace el ATLETA (convención producto: el alumno busca al PF, no al revés).
 *
 * La MISMA pregunta —un atleta inicia contacto con un PF— ya está resuelta en
 * la rama `inquiry` de `chatCreateOk` (firestore.rules ~2485), y mira al otro:
 *
 *     get(/databases/$(database)/documents/users/$(other)).data.role == 'trainer'
 *
 * Qué compraba el agujero, y por qué es seguridad y no forma:
 *
 *   1. RELAY DE MAIL. Un `pending` dispara `notifyOnLinkChange`, que encola
 *      `link-requested` al `trainerId` (functions/.../notify-link-change.ts).
 *      Sin gate de rol ese uid es CUALQUIERA, así que el mail sale desde el
 *      remitente verificado del producto hacia una víctima que nunca fue PF,
 *      con el `displayName` del atacante adentro del cuerpo.
 *   2. PAYWALL DEL ALUMNO. `athletePaywallEnforced` se apaga con un vínculo
 *      activo (`hasActiveTrainerLink`), y ninguna de las dos puntas miraba el
 *      rol: dos cuentas de atleta se aceptaban mutuamente y las dos quedaban
 *      exentas.
 *
 * ALCANCE — rol, NO rol+vínculo-publicado (espeja la decisión AD-1 de Slice C,
 * "ROLE-CHECK ONLY"). El `exists(trainerPublicProfiles/{trainerId})` de la rama
 * `inquiry` NO se replica acá a propósito: el flujo de INVITACIÓN
 * (`invite_dialog.dart` ~65) hace que el atleta cree el vínculo desde el link
 * del PF, y un PF que invita por link no necesariamente publicó su perfil de
 * discovery. Pedirlo rompería ese camino legítimo. SCENARIO-TL-03 es el ancla
 * que lo fija: PF real SIN perfil público puede recibir la solicitud.
 *
 * Run via: bash scripts/test_rules.sh  (trae su propio emulador; Java 21+)
 */

const { initializeTestEnvironment, assertFails, assertSucceeds } =
  require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

const PROJECT_ID = 'treino-test-rules';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(RULES_PATH, 'utf8'),
      host: 'localhost',
      port: 8080,
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedUserRole(uid, role) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc(uid).set({ uid, role });
  });
}

/**
 * Payload COMPLETO y por lo demás válido, modelado sobre `TrainerLink.toJson()`
 * (lib/features/coach/domain/trainer_link.dart) — que es lo que
 * `TrainerLinkRepository.request()` manda con `ref.set(link.toJson())`.
 *
 * Importa que sea completo por la lección de SCENARIO-CC-05 en
 * coach-collections-role.test.js: un `assertFails` que pasa por el motivo
 * equivocado —denegado por forma en vez de por el gate que dice custodiar— no
 * avisa nunca. Acá lo ÚNICO que puede denegar es el rol del `trainerId`.
 */
function linkDoc({ id, trainerId, athleteId }) {
  return {
    id,
    trainerId,
    athleteId,
    status: 'pending',
    requestedAt: new Date(),
    acceptedAt: null,
    terminatedAt: null,
    terminationReason: null,
    pausedAt: null,
    sharedWithTrainer: false,
    entitlement: 'entitled',
    blockedAt: null,
    blockedReason: null,
  };
}

// ---------------------------------------------------------------------------
// SCENARIO-TL-01: el vector de las DOS consecuencias. Un atleta apunta el
// `trainerId` a otra cuenta de ATLETA: eso le manda mail del producto a una
// víctima que no es PF, y —si la contraparte acepta— apaga el paywall de los
// dos. [REQ:trainer-links-role-gate#create exige rol trainer en trainerId]
// ---------------------------------------------------------------------------
test('SCENARIO-TL-01: athlete cannot open a link naming another ATHLETE as trainerId', async () => {
  await seedUserRole('attacker', 'athlete');
  await seedUserRole('victim', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('trainer_links').doc('forgedTL1').set(
      linkDoc({ id: 'forgedTL1', trainerId: 'victim', athleteId: 'attacker' }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TL-02: mismo ataque contra un uid que NO tiene doc en `users`. El
// `get()` de un doc inexistente devuelve null contra el emulador 1.21+ (ver la
// cabecera de scripts/test_rules.sh), así que el gate tiene que denegar sin
// depender de un error de evaluación.
// [REQ:trainer-links-role-gate#create exige rol trainer en trainerId]
// ---------------------------------------------------------------------------
test('SCENARIO-TL-02: athlete cannot open a link naming a uid with no user doc as trainerId', async () => {
  await seedUserRole('attacker', 'athlete');

  const attacker = testEnv.authenticatedContext('attacker');
  await assertFails(
    attacker.firestore().collection('trainer_links').doc('forgedTL2').set(
      linkDoc({ id: 'forgedTL2', trainerId: 'fantasma', athleteId: 'attacker' }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TL-03: ancla del camino legítimo, y del ALCANCE. Un atleta le pide
// vincularse a un PF REAL que NO publicó `trainerPublicProfiles` — el caso del
// flujo de invitación por link. Tiene que seguir verde después del fix: es lo
// que prueba que el gate es de ROL y no de perfil publicado.
// [REQ:trainer-links-role-gate#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-TL-03: athlete CAN request a link to a real trainer with no public profile', async () => {
  await seedUserRole('alumno', 'athlete');
  await seedUserRole('coach', 'trainer');

  const alumno = testEnv.authenticatedContext('alumno');
  await assertSucceeds(
    alumno.firestore().collection('trainer_links').doc('legitTL3').set(
      linkDoc({ id: 'legitTL3', trainerId: 'coach', athleteId: 'alumno' }),
    ),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-TL-04: PF → PF sigue habilitado. Un entrenador puede pedirle
// vincularse a OTRO entrenador como alumno (mismo caso que la rama `inquiry`
// admite). El gate mira el rol del `trainerId`, no el del que escribe, así que
// esto no tiene que romperse. [REQ:trainer-links-role-gate#legit path]
// ---------------------------------------------------------------------------
test('SCENARIO-TL-04: a trainer CAN request a link to another trainer as the athlete side', async () => {
  await seedUserRole('coachA', 'trainer');
  await seedUserRole('coachB', 'trainer');

  const coachA = testEnv.authenticatedContext('coachA');
  await assertSucceeds(
    coachA.firestore().collection('trainer_links').doc('legitTL4').set(
      linkDoc({ id: 'legitTL4', trainerId: 'coachB', athleteId: 'coachA' }),
    ),
  );
});
