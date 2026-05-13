'use strict';

const admin = require('firebase-admin');
admin.initializeApp(); // uses GOOGLE_APPLICATION_CREDENTIALS env var
const db = admin.firestore();

// -- DATA ------------------------------------------------------------------

const exercises = [
  // ── CHEST ──────────────────────────────────────────────────────────────
  {
    id: 'bench-press',
    name: 'Bench Press',
    muscleGroup: 'chest',
    category: 'compound',
    techniqueInstructions: [
      'Acostate en banco plano con los pies firmes en el piso.',
      'Tomá la barra con agarre poco más ancho que los hombros.',
      'Bajá controlado al pecho, empujá hasta extensión completa.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'incline-dumbbell-press',
    name: 'Incline Dumbbell Press',
    muscleGroup: 'chest',
    category: 'compound',
    techniqueInstructions: [
      'Banco inclinado a 30–45°.',
      'Bajá las mancuernas a la altura del pecho con codos a 45°.',
      'Empujá hacia arriba juntando las mancuernas al tope.',
    ],
    defaultRestSeconds: 75,
  },
  {
    id: 'cable-fly',
    name: 'Cable Fly',
    muscleGroup: 'chest',
    category: 'isolation',
    techniqueInstructions: [
      'Poleas altas, un paso adelante con una pierna.',
      'Llevá las manijas hacia el centro con codos ligeramente flexionados.',
      'Sentí el estiramiento en el pecho al abrir.',
    ],
    defaultRestSeconds: 60,
  },

  // ── BACK ───────────────────────────────────────────────────────────────
  {
    id: 'deadlift',
    name: 'Deadlift',
    muscleGroup: 'back',
    category: 'compound',
    techniqueInstructions: [
      'Pies al ancho de caderas, barra sobre el empeine.',
      'Espalda neutra, pecho hacia afuera, caderas atrás.',
      'Empujá el piso y levantá la barra pegada al cuerpo.',
    ],
    defaultRestSeconds: 120,
  },
  {
    id: 'barbell-row',
    name: 'Barbell Row',
    muscleGroup: 'back',
    category: 'compound',
    techniqueInstructions: [
      'Inclinación de torso a ~45°, espalda neutra.',
      'Jalá la barra hacia el ombligo apretando los codos.',
      'Bajá controlado sin soltar la tensión.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'pull-up',
    name: 'Pull-Up',
    muscleGroup: 'back',
    category: 'compound',
    techniqueInstructions: [
      'Agarre pronado, ancho de hombros.',
      'Iniciá el movimiento deprimiendo las escápulas.',
      'Llevá el mentón sobre la barra y bajá controlado.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'lat-pulldown',
    name: 'Lat Pulldown',
    muscleGroup: 'back',
    category: 'compound',
    techniqueInstructions: [
      'Agarre ancho, sentate con los muslos bajo los rodillos.',
      'Jalá la barra hacia el pecho inclinando el torso ligeramente.',
      'Extendé los brazos de forma controlada.',
    ],
    defaultRestSeconds: 75,
  },

  // ── SHOULDERS ──────────────────────────────────────────────────────────
  {
    id: 'overhead-press',
    name: 'Overhead Press',
    muscleGroup: 'shoulders',
    category: 'compound',
    techniqueInstructions: [
      'Barra a la altura del pecho, agarre levemente más ancho que los hombros.',
      'Empujá hacia arriba evitando arquear la espalda baja.',
      'Lockout completo arriba, cabeza ligeramente adelante.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'lateral-raise',
    name: 'Lateral Raise',
    muscleGroup: 'shoulders',
    category: 'isolation',
    techniqueInstructions: [
      'Mancuernas a los costados con codos ligeramente flexionados.',
      'Levantá los brazos hasta paralelo al piso como si derramaras agua.',
      'Bajá controlado sin impulso.',
    ],
    defaultRestSeconds: 60,
  },

  // ── LEGS ───────────────────────────────────────────────────────────────
  {
    id: 'back-squat',
    name: 'Back Squat',
    muscleGroup: 'quads',
    category: 'compound',
    techniqueInstructions: [
      'Barra sobre trapecios, pies al ancho de hombros o un poco más.',
      'Bajá como si fueras a sentarte, rodillas alineadas con los pies.',
      'Subí empujando el piso, sin que las rodillas colapsen hacia adentro.',
    ],
    defaultRestSeconds: 120,
  },
  {
    id: 'leg-press',
    name: 'Leg Press',
    muscleGroup: 'quads',
    category: 'compound',
    techniqueInstructions: [
      'Pies al ancho de hombros en la plataforma.',
      'Bajá el peso hasta que los muslos queden paralelos.',
      'No bloques las rodillas al subir.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'leg-extension',
    name: 'Leg Extension',
    muscleGroup: 'quads',
    category: 'isolation',
    techniqueInstructions: [
      'Sentate con la espalda contra el respaldo y el eje de la máquina alineado con la rodilla.',
      'Extendé las piernas hasta arriba apretando el cuádriceps.',
      'Bajá lentamente sin soltar la tensión.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'romanian-deadlift',
    name: 'Romanian Deadlift',
    muscleGroup: 'hamstrings',
    category: 'compound',
    techniqueInstructions: [
      'Pies al ancho de caderas, barra o mancuernas frente al cuerpo.',
      'Empujá las caderas hacia atrás bajando el peso pegado a las piernas.',
      'Sentí el estiramiento en los isquios y volvé a la posición inicial.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'leg-curl',
    name: 'Leg Curl',
    muscleGroup: 'hamstrings',
    category: 'isolation',
    techniqueInstructions: [
      'Boca abajo en la máquina, eje alineado con la rodilla.',
      'Flexioná las rodillas llevando los talones hacia los glúteos.',
      'Bajá de forma controlada.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'hip-thrust',
    name: 'Hip Thrust',
    muscleGroup: 'glutes',
    category: 'compound',
    techniqueInstructions: [
      'Espalda alta sobre el banco, barra sobre las caderas con amortiguador.',
      'Empujá las caderas hacia arriba hasta que el torso quede paralelo al piso.',
      'Apretá los glúteos en el tope y bajá controlado.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'calf-raise',
    name: 'Calf Raise',
    muscleGroup: 'calves',
    category: 'isolation',
    techniqueInstructions: [
      'Pies al ancho de caderas en el borde de un escalón o plataforma.',
      'Subí en puntillas lo más alto posible apretando las pantorrillas.',
      'Bajá hasta sentir el estiramiento completo.',
    ],
    defaultRestSeconds: 45,
  },

  // ── ARMS — BICEPS ──────────────────────────────────────────────────────
  {
    id: 'barbell-curl',
    name: 'Barbell Curl',
    muscleGroup: 'biceps',
    category: 'isolation',
    techniqueInstructions: [
      'Agarre supino al ancho de hombros.',
      'Flexioná los codos llevando la barra hacia los hombros.',
      'Codos fijos a los costados del torso.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'hammer-curl',
    name: 'Hammer Curl',
    muscleGroup: 'biceps',
    category: 'isolation',
    techniqueInstructions: [
      'Agarre neutro (pulgar arriba) con mancuernas.',
      'Flexioná el codo manteniendo el agarre neutro.',
      'Trabajás bíceps braquial y braquiorradial.',
    ],
    defaultRestSeconds: 60,
  },

  // ── ARMS — TRICEPS ─────────────────────────────────────────────────────
  {
    id: 'tricep-pushdown',
    name: 'Tricep Pushdown',
    muscleGroup: 'triceps',
    category: 'isolation',
    techniqueInstructions: [
      'Polea alta, agarre con barra recta o en V.',
      'Codos fijos a los costados, extendé los brazos hacia abajo.',
      'Apretá los tríceps en la extensión completa.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'skull-crusher',
    name: 'Skull Crusher',
    muscleGroup: 'triceps',
    category: 'isolation',
    techniqueInstructions: [
      'Acostado en banco plano, barra EZ sobre el pecho.',
      'Bajá la barra hacia la frente flexionando solo los codos.',
      'Extendé volviendo a la posición inicial.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'close-grip-bench-press',
    name: 'Close Grip Bench Press',
    muscleGroup: 'triceps',
    category: 'compound',
    techniqueInstructions: [
      'Agarre estrecho (ancho de hombros) en banco plano.',
      'Bajá la barra al pecho con los codos cerca del torso.',
      'Empujá hasta extensión completa enfocando los tríceps.',
    ],
    defaultRestSeconds: 75,
  },

  // ── CORE ───────────────────────────────────────────────────────────────
  {
    id: 'plank',
    name: 'Plank',
    muscleGroup: 'core',
    category: 'isolation',
    techniqueInstructions: [
      'Apoyate en antebrazos y puntas de pies.',
      'Cuerpo en línea recta de la cabeza a los talones.',
      'Apretá el abdomen y los glúteos durante toda la serie.',
    ],
    defaultRestSeconds: 45,
  },
  {
    id: 'cable-crunch',
    name: 'Cable Crunch',
    muscleGroup: 'core',
    category: 'isolation',
    techniqueInstructions: [
      'De rodillas frente a la polea alta con la cuerda detrás de la cabeza.',
      'Flexioná el torso llevando los codos hacia las rodillas.',
      'Contraé el abdomen en el punto más bajo.',
    ],
    defaultRestSeconds: 45,
  },
  {
    id: 'hanging-leg-raise',
    name: 'Hanging Leg Raise',
    muscleGroup: 'core',
    category: 'isolation',
    techniqueInstructions: [
      'Colgado de una barra con agarre pronado.',
      'Llevá las rodillas (o piernas rectas) hacia el pecho.',
      'Bajá de forma controlada sin balancearte.',
    ],
    defaultRestSeconds: 60,
  },

  // ── SHOULDERS — REAR DELT ──────────────────────────────────────────────
  {
    id: 'face-pull',
    name: 'Face Pull',
    muscleGroup: 'shoulders',
    category: 'isolation',
    techniqueInstructions: [
      'Polea alta con cuerda, jalá hacia la cara con codos a 90°.',
      'Rotá externamente los hombros al final del movimiento.',
      'Trabajás deltoides posterior y manguito rotador.',
    ],
    defaultRestSeconds: 60,
  },
];

// PR 2 will add: const routines = [ ... ];

// -- SEEDERS ---------------------------------------------------------------

async function seedExercises() {
  console.log(`Seeding ${exercises.length} exercises...`);
  for (const ex of exercises) {
    await db.collection('exercises').doc(ex.id).set(ex);
  }
  console.log('Exercises seeded.');
}

// PR 2 will add: async function validateRoutineRefs() { ... }
// PR 2 will add: async function seedRoutines() { ... }

// -- ENTRYPOINT ------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const doExercises = args.includes('--exercises') || args.includes('--all');
  // PR 2 will add: const doRoutines = args.includes('--routines') || args.includes('--all');

  if (!doExercises /* && !doRoutines */) {
    console.error('Usage: node seed_workout_catalog.js [--exercises|--routines|--all]');
    process.exit(1);
  }

  if (doExercises) await seedExercises();
  // PR 2: if (doRoutines) await seedRoutines();
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
