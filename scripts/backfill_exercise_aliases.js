'use strict';

/**
 * Backfill script — adds `aliases` field (Spanish synonyms) to every doc
 * in `exercises`. Used so the Coach Hub Excel importer matches against
 * common Spanish names like "Sentadilla con barra" → "Back Squat".
 *
 * Usage:
 *   set GOOGLE_APPLICATION_CREDENTIALS=scripts/treino-dev-service-account.json
 *   node scripts/backfill_exercise_aliases.js
 *
 * Idempotent: overwrites the `aliases` field every time. Safe to re-run.
 */

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

const aliasesById = {
  'bench-press': ['Press banca', 'Press de banca', 'Press plano', 'Press de banca plano', 'Press de pecho'],
  'incline-dumbbell-press': ['Press inclinado con mancuernas', 'Press inclinado mancuernas', 'Press inclinado', 'Press inclinado DB', 'Press inclinado de mancuernas', 'Press en banco inclinado'],
  'cable-fly': ['Cruce de poleas', 'Cruces en polea', 'Aperturas en polea', 'Aperturas con poleas', 'Cruces de cable', 'Cruces poleas'],

  'deadlift': ['Peso muerto', 'Peso muerto convencional', 'Peso muerto con barra', 'Muerto'],
  'barbell-row': ['Remo con barra', 'Remo barra', 'Remo inclinado con barra', 'Remo Pendlay', 'Remo con barra al pecho', 'Remo agarre pronado'],
  'pull-up': ['Dominadas', 'Dominada', 'Pull up', 'Pull ups', 'Dominada pronada', 'Dominadas pronadas'],
  'lat-pulldown': ['Jalón al pecho', 'Polea al pecho', 'Jalón frontal', 'Polea dorsal', 'Jalón dorsal', 'Polea al pecho con barra', 'Pulldown'],

  'overhead-press': ['Press militar', 'Press de hombros', 'Press de pie', 'Press hombro con barra', 'Press militar de pie', 'OHP', 'Press de hombro'],
  'lateral-raise': ['Elevaciones laterales', 'Vuelos laterales', 'Laterales con mancuernas', 'Elevaciones laterales con mancuernas', 'Aperturas laterales', 'Laterales'],
  'face-pull': ['Jalón al rostro', 'Jalón a la cara', 'Face pull con cuerda', 'Polea cara con cuerda', 'Jalón facial'],

  'back-squat': ['Sentadilla', 'Sentadilla con barra', 'Sentadilla trasera', 'Squat', 'Squat trasero', 'Sentadilla libre', 'Sentadilla profunda', 'Sentadilla con barra trasera'],
  'leg-press': ['Prensa de piernas', 'Prensa', 'Prensa 45', 'Prensa horizontal', 'Press de pierna', 'Prensa de pierna'],
  'leg-extension': ['Extensión de cuádriceps', 'Extensión de piernas', 'Cuádriceps en máquina', 'Camilla de cuádriceps', 'Silla de cuádriceps', 'Extensiones de cuadriceps'],
  'romanian-deadlift': ['Peso muerto rumano', 'Peso muerto a piernas rectas', 'Rumano', 'RDL', 'Peso muerto piernas semi-rígidas', 'Peso muerto rumano con barra'],
  'leg-curl': ['Curl femoral', 'Camilla femoral', 'Femoral acostado', 'Femoral en máquina', 'Flexión de pierna en máquina', 'Curl de pierna acostado', 'Femoral'],
  'hip-thrust': ['Empuje de cadera', 'Empuje de caderas', 'Empuje pélvico', 'Hip thrust con barra', 'Glute bridge con barra', 'Puente de glúteos con barra'],
  'calf-raise': ['Elevación de pantorrillas', 'Gemelos de pie', 'Pantorrilla en máquina', 'Elevaciones de gemelos', 'Gemelos', 'Pantorrillas'],

  'barbell-curl': ['Curl con barra', 'Curl de bíceps con barra', 'Bíceps con barra', 'Curl barra recta', 'Curl barra'],
  'hammer-curl': ['Curl martillo', 'Curl tipo martillo', 'Martillo con mancuernas', 'Curl neutro', 'Curl de bíceps martillo'],

  'tricep-pushdown': ['Jalón de tríceps', 'Extensión de tríceps en polea', 'Tríceps en polea', 'Polea de tríceps', 'Pushdown', 'Extensión polea alta', 'Tríceps polea'],
  'skull-crusher': ['Press francés', 'Rompecráneos', 'Frances', 'Press francés con barra EZ', 'Extensión de tríceps acostado', 'Press francés acostado'],
  'close-grip-bench-press': ['Press cerrado', 'Press banca cerrado', 'Press agarre cerrado', 'Press de banca agarre cerrado', 'Press banca tríceps'],

  'plank': ['Plancha', 'Plancha frontal', 'Plancha abdominal', 'Plancha isométrica'],
  'cable-crunch': ['Crunch en polea', 'Abdominales en polea', 'Crunch con cuerda', 'Abdominal polea alta', 'Abdominales con polea'],
  'hanging-leg-raise': ['Elevación de piernas colgado', 'Elevaciones de piernas colgado', 'Piernas en barra', 'Elevación de piernas en barra', 'Elevación de rodillas colgado'],
};

async function run() {
  console.log(`Backfilling aliases for ${Object.keys(aliasesById).length} exercises…`);
  let updated = 0;
  let missing = 0;

  for (const [id, aliases] of Object.entries(aliasesById)) {
    const ref = db.collection('exercises').doc(id);
    const snap = await ref.get();
    if (!snap.exists) {
      console.warn(`  ⚠  exercise "${id}" not found in Firestore — skipping`);
      missing++;
      continue;
    }
    await ref.update({ aliases });
    console.log(`  ✓  ${id} (${aliases.length} aliases)`);
    updated++;
  }

  console.log(`\nDone. Updated: ${updated} · Missing: ${missing}`);
  process.exit(0);
}

run().catch((err) => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
