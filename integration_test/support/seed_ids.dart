// GENERADO POR scripts/export_seed_ids.js — NO EDITAR A MANO.
//
// Fuente: scripts/lib/e2e_seed_contract.js
// Regenerar: node scripts/export_seed_ids.js
//
// Los identificadores que `scripts/seed_emulator_full.js` deja en el emulador.
// Las suites de `integration_test/` los importan de acá en vez de declararlos
// cada una por su cuenta: mientras vivieron en cinco archivos, cuatro de ellos
// decían `e2e.athlete@treino.test`, un mail que no correspondía a ningún
// usuario sembrado y que fallaba en el login hablando de credenciales.
//
// `scripts/test/e2e_seed_contract.test.js` regenera este archivo en memoria y
// lo compara con esta copia: si el contrato cambió y nadie regeneró, ese test
// se pone rojo en CI antes de que una suite corra con un id fantasma.

/// Una cuenta sembrada por `seed_emulator_full.js`.
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
const String kSeedPassword = 'Emulator1234!';

const SeedUser kMartin = SeedUser(
  uid: 'seed-athlete-001',
  email: 'martin@emulator.treino',
  displayName: 'Martín López',
);

const SeedUser kSofia = SeedUser(
  uid: 'seed-athlete-002',
  email: 'sofia@emulator.treino',
  displayName: 'Sofía Ramírez',
);

const SeedUser kValentina = SeedUser(
  uid: 'seed-athlete-004',
  email: 'valentina@emulator.treino',
  displayName: 'Valentina Peralta',
);

const SeedUser kNicolas = SeedUser(
  uid: 'seed-athlete-005',
  email: 'nicolas@emulator.treino',
  displayName: 'Nicolás Fernández',
);

const SeedUser kLautaro = SeedUser(
  uid: 'seed-coach-001',
  email: 'coach.lautaro@emulator.treino',
  displayName: 'Lautaro Pérez',
);

const SeedUser kDiego = SeedUser(
  uid: 'seed-coach-003',
  email: 'coach.diego@emulator.treino',
  displayName: 'Diego Aguirre',
);

/// Chat de Coach: `linkId` apunta a un `trainer_links` `active`.
const String kCoachChatId = 'seed-athlete-001_seed-coach-001';
const String kCoachChatLinkId = 'seed-link-001';

/// Chat de consulta: `kind: 'inquiry'`, sin vínculo entre las partes.
const String kInquiryChatId = 'seed-athlete-005_seed-coach-003';

/// Chat social: se apoya en el follow mutuo aceptado entre Martín y Sofía.
const String kSocialChatId = 'seed-athlete-001_seed-athlete-002';

/// Rutina `trainer-assigned` de Lautaro a Martín, con 3 semanas de contenido.
const String kAssignedRoutineId = 'seed-routine-001';

/// Plantilla del sistema, sin `assignedTo`.
const String kSystemTemplateRoutineId = 'seed-routine-003';

// ⚠️  NO hay constante de "rutina propia del alumno" porque el seed no siembra
// ninguna: las dos rutinas con contenido son `trainer-assigned` y la tercera es
// una plantilla `system`. `my_routine_edit_test.dart` necesita una rutina de la
// que el alumno sea DUEÑO, y poner acá el id de una asignada haría que esa suite
// abriera el editor sobre algo que el alumno no puede editar — fallaría hablando
// de permisos, que es el peor lugar posible para descubrir que falta un fixture.
