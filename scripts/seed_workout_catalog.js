'use strict';

const admin = require('firebase-admin');
admin.initializeApp(); // uses GOOGLE_APPLICATION_CREDENTIALS env var
const db = admin.firestore();

// -- DATA ------------------------------------------------------------------

const exercises = [
  // ── CHEST ──────────────────────────────────────────────────────────────
  {
    id: 'bench-press',
    name: 'Press de banca',
    muscleGroup: 'chest',
    category: 'compound',
    aliases: ['Press banca', 'Press de banca', 'Press plano', 'Press de banca plano', 'Press de pecho'],
    techniqueInstructions: [
      'Acostate en banco plano con los pies firmes en el piso.',
      'Tomá la barra con agarre poco más ancho que los hombros.',
      'Bajá controlado al pecho, empujá hasta extensión completa.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'incline-dumbbell-press',
    name: 'Press inclinado con mancuernas',
    muscleGroup: 'chest',
    category: 'compound',
    aliases: ['Press inclinado con mancuernas', 'Press inclinado mancuernas', 'Press inclinado', 'Press inclinado DB', 'Press inclinado de mancuernas', 'Press en banco inclinado'],
    techniqueInstructions: [
      'Banco inclinado a 30–45°.',
      'Bajá las mancuernas a la altura del pecho con codos a 45°.',
      'Empujá hacia arriba juntando las mancuernas al tope.',
    ],
    defaultRestSeconds: 75,
  },
  {
    id: 'cable-fly',
    name: 'Cruces en polea',
    muscleGroup: 'chest',
    category: 'isolation',
    aliases: ['Cruce de poleas', 'Cruces en polea', 'Aperturas en polea', 'Aperturas con poleas', 'Cruces de cable', 'Cruces poleas'],
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
    name: 'Peso muerto',
    muscleGroup: 'back',
    category: 'compound',
    aliases: ['Peso muerto', 'Peso muerto convencional', 'Peso muerto con barra', 'Muerto'],
    techniqueInstructions: [
      'Pies al ancho de caderas, barra sobre el empeine.',
      'Espalda neutra, pecho hacia afuera, caderas atrás.',
      'Empujá el piso y levantá la barra pegada al cuerpo.',
    ],
    defaultRestSeconds: 120,
  },
  {
    id: 'barbell-row',
    name: 'Remo con barra',
    muscleGroup: 'back',
    category: 'compound',
    aliases: ['Remo con barra', 'Remo barra', 'Remo inclinado con barra', 'Remo Pendlay', 'Remo con barra al pecho', 'Remo agarre pronado'],
    techniqueInstructions: [
      'Inclinación de torso a ~45°, espalda neutra.',
      'Jalá la barra hacia el ombligo apretando los codos.',
      'Bajá controlado sin soltar la tensión.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'pull-up',
    name: 'Dominadas',
    muscleGroup: 'back',
    category: 'compound',
    aliases: ['Dominadas', 'Dominada', 'Pull up', 'Pull ups', 'Dominada pronada', 'Dominadas pronadas'],
    techniqueInstructions: [
      'Agarre pronado, ancho de hombros.',
      'Iniciá el movimiento deprimiendo las escápulas.',
      'Llevá el mentón sobre la barra y bajá controlado.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'lat-pulldown',
    name: 'Jalón al pecho',
    muscleGroup: 'back',
    category: 'compound',
    aliases: ['Jalón al pecho', 'Polea al pecho', 'Jalón frontal', 'Polea dorsal', 'Jalón dorsal', 'Polea al pecho con barra', 'Pulldown'],
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
    name: 'Press militar',
    muscleGroup: 'shoulders',
    category: 'compound',
    aliases: ['Press militar', 'Press de hombros', 'Press de pie', 'Press hombro con barra', 'Press militar de pie', 'OHP', 'Press de hombro'],
    techniqueInstructions: [
      'Barra a la altura del pecho, agarre levemente más ancho que los hombros.',
      'Empujá hacia arriba evitando arquear la espalda baja.',
      'Lockout completo arriba, cabeza ligeramente adelante.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'lateral-raise',
    name: 'Elevaciones laterales',
    muscleGroup: 'shoulders',
    category: 'isolation',
    aliases: ['Elevaciones laterales', 'Vuelos laterales', 'Laterales con mancuernas', 'Elevaciones laterales con mancuernas', 'Aperturas laterales', 'Laterales'],
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
    name: 'Sentadilla',
    muscleGroup: 'quads',
    category: 'compound',
    aliases: ['Sentadilla', 'Sentadilla con barra', 'Sentadilla trasera', 'Squat', 'Squat trasero', 'Sentadilla libre', 'Sentadilla profunda', 'Sentadilla con barra trasera'],
    techniqueInstructions: [
      'Barra sobre trapecios, pies al ancho de hombros o un poco más.',
      'Bajá como si fueras a sentarte, rodillas alineadas con los pies.',
      'Subí empujando el piso, sin que las rodillas colapsen hacia adentro.',
    ],
    defaultRestSeconds: 120,
  },
  {
    id: 'leg-press',
    name: 'Prensa de piernas',
    muscleGroup: 'quads',
    category: 'compound',
    aliases: ['Prensa de piernas', 'Prensa', 'Prensa 45', 'Prensa horizontal', 'Press de pierna', 'Prensa de pierna'],
    techniqueInstructions: [
      'Pies al ancho de hombros en la plataforma.',
      'Bajá el peso hasta que los muslos queden paralelos.',
      'No bloques las rodillas al subir.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'leg-extension',
    name: 'Extensión de cuádriceps',
    muscleGroup: 'quads',
    category: 'isolation',
    aliases: ['Extensión de cuádriceps', 'Extensión de piernas', 'Cuádriceps en máquina', 'Camilla de cuádriceps', 'Silla de cuádriceps', 'Extensiones de cuadriceps'],
    techniqueInstructions: [
      'Sentate con la espalda contra el respaldo y el eje de la máquina alineado con la rodilla.',
      'Extendé las piernas hasta arriba apretando el cuádriceps.',
      'Bajá lentamente sin soltar la tensión.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'romanian-deadlift',
    name: 'Peso muerto rumano',
    muscleGroup: 'hamstrings',
    category: 'compound',
    aliases: ['Peso muerto rumano', 'Peso muerto a piernas rectas', 'Rumano', 'RDL', 'Peso muerto piernas semi-rígidas', 'Peso muerto rumano con barra'],
    techniqueInstructions: [
      'Pies al ancho de caderas, barra o mancuernas frente al cuerpo.',
      'Empujá las caderas hacia atrás bajando el peso pegado a las piernas.',
      'Sentí el estiramiento en los isquios y volvé a la posición inicial.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'leg-curl',
    name: 'Curl femoral',
    muscleGroup: 'hamstrings',
    category: 'isolation',
    aliases: ['Curl femoral', 'Camilla femoral', 'Femoral acostado', 'Femoral en máquina', 'Flexión de pierna en máquina', 'Curl de pierna acostado', 'Femoral'],
    techniqueInstructions: [
      'Boca abajo en la máquina, eje alineado con la rodilla.',
      'Flexioná las rodillas llevando los talones hacia los glúteos.',
      'Bajá de forma controlada.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'hip-thrust',
    name: 'Empuje de cadera',
    muscleGroup: 'glutes',
    category: 'compound',
    aliases: ['Empuje de cadera', 'Empuje de caderas', 'Empuje pélvico', 'Hip thrust con barra', 'Glute bridge con barra', 'Puente de glúteos con barra'],
    techniqueInstructions: [
      'Espalda alta sobre el banco, barra sobre las caderas con amortiguador.',
      'Empujá las caderas hacia arriba hasta que el torso quede paralelo al piso.',
      'Apretá los glúteos en el tope y bajá controlado.',
    ],
    defaultRestSeconds: 90,
  },
  {
    id: 'calf-raise',
    name: 'Elevación de pantorrillas',
    muscleGroup: 'calves',
    category: 'isolation',
    aliases: ['Elevación de pantorrillas', 'Gemelos de pie', 'Pantorrilla en máquina', 'Elevaciones de gemelos', 'Gemelos', 'Pantorrillas'],
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
    name: 'Curl con barra',
    muscleGroup: 'biceps',
    category: 'isolation',
    aliases: ['Curl con barra', 'Curl de bíceps con barra', 'Bíceps con barra', 'Curl barra recta', 'Curl barra'],
    techniqueInstructions: [
      'Agarre supino al ancho de hombros.',
      'Flexioná los codos llevando la barra hacia los hombros.',
      'Codos fijos a los costados del torso.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'hammer-curl',
    name: 'Curl martillo',
    muscleGroup: 'biceps',
    category: 'isolation',
    aliases: ['Curl martillo', 'Curl tipo martillo', 'Martillo con mancuernas', 'Curl neutro', 'Curl de bíceps martillo'],
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
    name: 'Extensión de tríceps en polea',
    muscleGroup: 'triceps',
    category: 'isolation',
    aliases: ['Jalón de tríceps', 'Extensión de tríceps en polea', 'Tríceps en polea', 'Polea de tríceps', 'Pushdown', 'Extensión polea alta', 'Tríceps polea'],
    techniqueInstructions: [
      'Polea alta, agarre con barra recta o en V.',
      'Codos fijos a los costados, extendé los brazos hacia abajo.',
      'Apretá los tríceps en la extensión completa.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'skull-crusher',
    name: 'Press francés',
    muscleGroup: 'triceps',
    category: 'isolation',
    aliases: ['Press francés', 'Rompecráneos', 'Frances', 'Press francés con barra EZ', 'Extensión de tríceps acostado', 'Press francés acostado'],
    techniqueInstructions: [
      'Acostado en banco plano, barra EZ sobre el pecho.',
      'Bajá la barra hacia la frente flexionando solo los codos.',
      'Extendé volviendo a la posición inicial.',
    ],
    defaultRestSeconds: 60,
  },
  {
    id: 'close-grip-bench-press',
    name: 'Press cerrado',
    muscleGroup: 'triceps',
    category: 'compound',
    aliases: ['Press cerrado', 'Press banca cerrado', 'Press agarre cerrado', 'Press de banca agarre cerrado', 'Press banca tríceps'],
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
    name: 'Plancha',
    muscleGroup: 'core',
    category: 'isolation',
    aliases: ['Plancha', 'Plancha frontal', 'Plancha abdominal', 'Plancha isométrica'],
    techniqueInstructions: [
      'Apoyate en antebrazos y puntas de pies.',
      'Cuerpo en línea recta de la cabeza a los talones.',
      'Apretá el abdomen y los glúteos durante toda la serie.',
    ],
    defaultRestSeconds: 45,
  },
  {
    id: 'cable-crunch',
    name: 'Crunch en polea',
    muscleGroup: 'core',
    category: 'isolation',
    aliases: ['Crunch en polea', 'Abdominales en polea', 'Crunch con cuerda', 'Abdominal polea alta', 'Abdominales con polea'],
    techniqueInstructions: [
      'De rodillas frente a la polea alta con la cuerda detrás de la cabeza.',
      'Flexioná el torso llevando los codos hacia las rodillas.',
      'Contraé el abdomen en el punto más bajo.',
    ],
    defaultRestSeconds: 45,
  },
  {
    id: 'hanging-leg-raise',
    name: 'Elevación de piernas colgado',
    muscleGroup: 'core',
    category: 'isolation',
    aliases: ['Elevación de piernas colgado', 'Elevaciones de piernas colgado', 'Piernas en barra', 'Elevación de piernas en barra', 'Elevación de rodillas colgado'],
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
    name: 'Jalón al rostro',
    muscleGroup: 'shoulders',
    category: 'isolation',
    aliases: ['Jalón al rostro', 'Jalón a la cara', 'Face pull con cuerda', 'Polea cara con cuerda', 'Jalón facial'],
    techniqueInstructions: [
      'Polea alta con cuerda, jalá hacia la cara con codos a 90°.',
      'Rotá externamente los hombros al final del movimiento.',
      'Trabajás deltoides posterior y manguito rotador.',
    ],
    defaultRestSeconds: 60,
  },
];

// -- ROUTINES DATA ---------------------------------------------------------

const routines = [
  // ── 1. PUSH / PULL / LEGS — PRINCIPIANTE (3 days) ─────────────────────
  {
    id: 'ppl-beginner',
    name: 'Push Pull Legs — Principiante',
    split: 'PPL',
    level: 'beginner',
    estimatedMinutesPerDay: 60,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Push',
        estimatedMinutes: 60,
        slots: [
          { exerciseId: 'bench-press',          exerciseName: 'Press de banca',          muscleGroup: 'chest',     targetSets: 4, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'incline-dumbbell-press', exerciseName: 'Press inclinado con mancuernas', muscleGroup: 'chest',  targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 75,  targetWeightKg: null, notes: null },
          { exerciseId: 'overhead-press',        exerciseName: 'Press militar',        muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise',         exerciseName: 'Elevaciones laterales',         muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'tricep-pushdown',       exerciseName: 'Extensión de tríceps en polea',       muscleGroup: 'triceps',  targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'skull-crusher',         exerciseName: 'Press francés',         muscleGroup: 'triceps',  targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Pull',
        estimatedMinutes: 60,
        slots: [
          { exerciseId: 'deadlift',      exerciseName: 'Peso muerto',      muscleGroup: 'back',    targetSets: 4, targetRepsMin: 5,  targetRepsMax: 6,  restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-row',   exerciseName: 'Remo con barra',   muscleGroup: 'back',    targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',  exerciseName: 'Jalón al pecho',  muscleGroup: 'back',    targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75,  targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-curl',  exerciseName: 'Curl con barra',  muscleGroup: 'biceps',  targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'hammer-curl',   exerciseName: 'Curl martillo',   muscleGroup: 'biceps',  targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'face-pull',     exerciseName: 'Jalón al rostro',     muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 60, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 3,
        name: 'Legs',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'back-squat',        exerciseName: 'Sentadilla',        muscleGroup: 'quads',      targetSets: 4, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-press',         exerciseName: 'Prensa de piernas',         muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-curl',          exerciseName: 'Curl femoral',          muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'hip-thrust',        exerciseName: 'Empuje de cadera',        muscleGroup: 'glutes',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'calf-raise',        exerciseName: 'Elevación de pantorrillas',        muscleGroup: 'calves',     targetSets: 4, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null, notes: null },
        ],
      },
    ],
  },

  // ── 2. FULL BODY PRINCIPIANTE (3 days) ────────────────────────────────
  {
    id: 'full-body-3day',
    name: 'Full Body Principiante',
    split: 'Full Body',
    level: 'beginner',
    estimatedMinutesPerDay: 55,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Día 1',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'back-squat',    exerciseName: 'Sentadilla',    muscleGroup: 'quads',    targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'bench-press',   exerciseName: 'Press de banca',   muscleGroup: 'chest',    targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-row',   exerciseName: 'Remo con barra',   muscleGroup: 'back',     targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'overhead-press', exerciseName: 'Press militar', muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 8, targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'plank',         exerciseName: 'Plancha',         muscleGroup: 'core',     targetSets: 3, targetRepsMin: 30, targetRepsMax: 45, restSeconds: 45,  targetWeightKg: null, notes: 'segundos' },
        ],
      },
      {
        dayNumber: 2,
        name: 'Día 2',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'leg-press',         exerciseName: 'Prensa de piernas',         muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'incline-dumbbell-press', exerciseName: 'Press inclinado con mancuernas', muscleGroup: 'chest', targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',      exerciseName: 'Jalón al pecho',      muscleGroup: 'back',       targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise',     exerciseName: 'Elevaciones laterales',     muscleGroup: 'shoulders',  targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'cable-crunch',      exerciseName: 'Crunch en polea',      muscleGroup: 'core',       targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 3,
        name: 'Día 3',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'cable-fly',         exerciseName: 'Cruces en polea',         muscleGroup: 'chest',      targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'pull-up',           exerciseName: 'Dominadas',           muscleGroup: 'back',       targetSets: 3, targetRepsMin: 6,  targetRepsMax: 10, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'hip-thrust',        exerciseName: 'Empuje de cadera',        muscleGroup: 'glutes',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'hanging-leg-raise', exerciseName: 'Elevación de piernas colgado', muscleGroup: 'core',       targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
        ],
      },
    ],
  },

  // ── 3. UPPER / LOWER — INTERMEDIO (4 days) ────────────────────────────
  {
    id: 'upper-lower-intermediate',
    name: 'Upper/Lower — Intermedio',
    split: 'Upper/Lower',
    level: 'intermediate',
    estimatedMinutesPerDay: 65,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Upper A',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'bench-press',    exerciseName: 'Press de banca',    muscleGroup: 'chest',     targetSets: 4, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-row',    exerciseName: 'Remo con barra',    muscleGroup: 'back',      targetSets: 4, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'overhead-press', exerciseName: 'Press militar', muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'pull-up',        exerciseName: 'Dominadas',        muscleGroup: 'back',      targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-curl',   exerciseName: 'Curl con barra',   muscleGroup: 'biceps',    targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'skull-crusher',  exerciseName: 'Press francés',  muscleGroup: 'triceps',   targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Lower A',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'back-squat',        exerciseName: 'Sentadilla',        muscleGroup: 'quads',      targetSets: 4, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-press',         exerciseName: 'Prensa de piernas',         muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-curl',          exerciseName: 'Curl femoral',          muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'calf-raise',        exerciseName: 'Elevación de pantorrillas',        muscleGroup: 'calves',     targetSets: 4, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null, notes: null },
          { exerciseId: 'plank',             exerciseName: 'Plancha',             muscleGroup: 'core',       targetSets: 3, targetRepsMin: 40, targetRepsMax: 60, restSeconds: 45,  targetWeightKg: null, notes: 'segundos' },
        ],
      },
      {
        dayNumber: 3,
        name: 'Upper B',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'incline-dumbbell-press', exerciseName: 'Press inclinado con mancuernas', muscleGroup: 'chest',     targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',           exerciseName: 'Jalón al pecho',           muscleGroup: 'back',      targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise',          exerciseName: 'Elevaciones laterales',          muscleGroup: 'shoulders', targetSets: 4, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'cable-fly',              exerciseName: 'Cruces en polea',              muscleGroup: 'chest',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'hammer-curl',            exerciseName: 'Curl martillo',            muscleGroup: 'biceps',    targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'tricep-pushdown',        exerciseName: 'Extensión de tríceps en polea',        muscleGroup: 'triceps',   targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 4,
        name: 'Lower B',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'deadlift',          exerciseName: 'Peso muerto',          muscleGroup: 'back',       targetSets: 4, targetRepsMin: 4,  targetRepsMax: 6,  restSeconds: 180, targetWeightKg: null, notes: null },
          { exerciseId: 'leg-extension',     exerciseName: 'Extensión de cuádriceps',     muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'hip-thrust',        exerciseName: 'Empuje de cadera',        muscleGroup: 'glutes',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'cable-crunch',      exerciseName: 'Crunch en polea',      muscleGroup: 'core',       targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null, notes: null },
          { exerciseId: 'calf-raise',        exerciseName: 'Elevación de pantorrillas',        muscleGroup: 'calves',     targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null, notes: null },
        ],
      },
    ],
  },

  // ── 4. BRO SPLIT — INTERMEDIO (5 days) ───────────────────────────────
  {
    id: 'bro-split-intermediate',
    name: 'Bro Split — Intermedio',
    split: 'Bro Split',
    level: 'intermediate',
    estimatedMinutesPerDay: 55,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Pecho',
        estimatedMinutes: 55,
        slots: [
          { exerciseId: 'bench-press',           exerciseName: 'Press de banca',           muscleGroup: 'chest', targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'incline-dumbbell-press', exerciseName: 'Press inclinado con mancuernas', muscleGroup: 'chest', targetSets: 4, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'cable-fly',             exerciseName: 'Cruces en polea',             muscleGroup: 'chest', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'close-grip-bench-press', exerciseName: 'Press cerrado', muscleGroup: 'triceps', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'tricep-pushdown',       exerciseName: 'Extensión de tríceps en polea',       muscleGroup: 'triceps', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Espalda',
        estimatedMinutes: 60,
        slots: [
          { exerciseId: 'deadlift',     exerciseName: 'Peso muerto',     muscleGroup: 'back',   targetSets: 4, targetRepsMin: 5,  targetRepsMax: 6,  restSeconds: 180, targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-row',  exerciseName: 'Remo con barra',  muscleGroup: 'back',   targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'pull-up',      exerciseName: 'Dominadas',      muscleGroup: 'back',   targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown', exerciseName: 'Jalón al pecho', muscleGroup: 'back',   targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75,  targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-curl', exerciseName: 'Curl con barra', muscleGroup: 'biceps', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'hammer-curl',  exerciseName: 'Curl martillo',  muscleGroup: 'biceps', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 3,
        name: 'Hombros',
        estimatedMinutes: 50,
        slots: [
          { exerciseId: 'overhead-press', exerciseName: 'Press militar', muscleGroup: 'shoulders', targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise',  exerciseName: 'Elevaciones laterales',  muscleGroup: 'shoulders', targetSets: 4, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'face-pull',      exerciseName: 'Jalón al rostro',      muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'skull-crusher',  exerciseName: 'Press francés',  muscleGroup: 'triceps',   targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'cable-crunch',   exerciseName: 'Crunch en polea',   muscleGroup: 'core',      targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 4,
        name: 'Piernas',
        estimatedMinutes: 65,
        slots: [
          { exerciseId: 'back-squat',        exerciseName: 'Sentadilla',        muscleGroup: 'quads',      targetSets: 4, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-press',         exerciseName: 'Prensa de piernas',         muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-extension',     exerciseName: 'Extensión de cuádriceps',     muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'leg-curl',          exerciseName: 'Curl femoral',          muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'calf-raise',        exerciseName: 'Elevación de pantorrillas',        muscleGroup: 'calves',     targetSets: 4, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null, notes: null },
          { exerciseId: 'hip-thrust',        exerciseName: 'Empuje de cadera',        muscleGroup: 'glutes',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 5,
        name: 'Full',
        estimatedMinutes: 50,
        slots: [
          { exerciseId: 'bench-press',   exerciseName: 'Press de banca',   muscleGroup: 'chest',    targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',  exerciseName: 'Jalón al pecho',  muscleGroup: 'back',     targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'back-squat',    exerciseName: 'Sentadilla',    muscleGroup: 'quads',    targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'plank',         exerciseName: 'Plancha',         muscleGroup: 'core',     targetSets: 3, targetRepsMin: 40, targetRepsMax: 60, restSeconds: 45, targetWeightKg: null, notes: 'segundos' },
          { exerciseId: 'hanging-leg-raise', exerciseName: 'Elevación de piernas colgado', muscleGroup: 'core', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
        ],
      },
    ],
  },

  // ── 5. POWERLIFTING BASE — AVANZADO (4 days) ──────────────────────────
  {
    id: 'powerlifting-base',
    name: 'Powerlifting Base',
    split: 'Powerlifting',
    level: 'advanced',
    estimatedMinutesPerDay: 75,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Sentadilla',
        estimatedMinutes: 75,
        slots: [
          { exerciseId: 'back-squat',    exerciseName: 'Sentadilla',    muscleGroup: 'quads',      targetSets: 5, targetRepsMin: 3,  targetRepsMax: 5,  restSeconds: 180, targetWeightKg: 100.0, notes: '80% 1RM' },
          { exerciseId: 'leg-press',     exerciseName: 'Prensa de piernas',     muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 120, targetWeightKg: null,  notes: null },
          { exerciseId: 'leg-curl',      exerciseName: 'Curl femoral',      muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null,  notes: null },
          { exerciseId: 'calf-raise',    exerciseName: 'Elevación de pantorrillas',    muscleGroup: 'calves',     targetSets: 4, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 45,  targetWeightKg: null,  notes: null },
          { exerciseId: 'cable-crunch',  exerciseName: 'Crunch en polea',  muscleGroup: 'core',       targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45,  targetWeightKg: null,  notes: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Press',
        estimatedMinutes: 70,
        slots: [
          { exerciseId: 'bench-press',           exerciseName: 'Press de banca',           muscleGroup: 'chest',     targetSets: 5, targetRepsMin: 3,  targetRepsMax: 5,  restSeconds: 180, targetWeightKg: 80.0,  notes: '80% 1RM' },
          { exerciseId: 'close-grip-bench-press', exerciseName: 'Press cerrado', muscleGroup: 'triceps',  targetSets: 3, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 90,  targetWeightKg: null,  notes: null },
          { exerciseId: 'overhead-press',        exerciseName: 'Press militar',        muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 90,  targetWeightKg: null,  notes: null },
          { exerciseId: 'tricep-pushdown',       exerciseName: 'Extensión de tríceps en polea',       muscleGroup: 'triceps',   targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null,  notes: null },
          { exerciseId: 'face-pull',             exerciseName: 'Jalón al rostro',             muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 60,  targetWeightKg: null,  notes: null },
        ],
      },
      {
        dayNumber: 3,
        name: 'Peso Muerto',
        estimatedMinutes: 75,
        slots: [
          { exerciseId: 'deadlift',          exerciseName: 'Peso muerto',          muscleGroup: 'back',       targetSets: 5, targetRepsMin: 2,  targetRepsMax: 4,  restSeconds: 240, targetWeightKg: 120.0, notes: '80% 1RM' },
          { exerciseId: 'romanian-deadlift', exerciseName: 'Peso muerto rumano', muscleGroup: 'hamstrings', targetSets: 3, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 120, targetWeightKg: null,  notes: null },
          { exerciseId: 'barbell-row',       exerciseName: 'Remo con barra',       muscleGroup: 'back',       targetSets: 3, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 90,  targetWeightKg: null,  notes: null },
          { exerciseId: 'pull-up',           exerciseName: 'Dominadas',           muscleGroup: 'back',       targetSets: 3, targetRepsMin: 6,  targetRepsMax: 10, restSeconds: 90,  targetWeightKg: null,  notes: null },
          { exerciseId: 'hanging-leg-raise', exerciseName: 'Elevación de piernas colgado', muscleGroup: 'core',       targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null,  notes: null },
        ],
      },
      {
        dayNumber: 4,
        name: 'Accesorios',
        estimatedMinutes: 60,
        slots: [
          { exerciseId: 'incline-dumbbell-press', exerciseName: 'Press inclinado con mancuernas', muscleGroup: 'chest',     targetSets: 3, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',           exerciseName: 'Jalón al pecho',           muscleGroup: 'back',      targetSets: 3, targetRepsMin: 8,  targetRepsMax: 10, restSeconds: 75, targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise',          exerciseName: 'Elevaciones laterales',          muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-curl',           exerciseName: 'Curl con barra',           muscleGroup: 'biceps',    targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'skull-crusher',          exerciseName: 'Press francés',          muscleGroup: 'triceps',   targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'plank',                  exerciseName: 'Plancha',                  muscleGroup: 'core',      targetSets: 3, targetRepsMin: 45, targetRepsMax: 60, restSeconds: 45, targetWeightKg: null, notes: 'segundos' },
        ],
      },
    ],
  },

  // ── 6. CALISTENIA PRINCIPIANTE (3 days) ───────────────────────────────
  {
    id: 'calistenia-beginner',
    name: 'Calistenia Principiante',
    split: 'Full Body',
    level: 'beginner',
    estimatedMinutesPerDay: 45,
    imageUrl: null,
    days: [
      {
        dayNumber: 1,
        name: 'Empuje + Core',
        estimatedMinutes: 45,
        slots: [
          { exerciseId: 'bench-press',    exerciseName: 'Press de banca',    muscleGroup: 'chest',    targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'overhead-press', exerciseName: 'Press militar', muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 90, targetWeightKg: null, notes: null },
          { exerciseId: 'tricep-pushdown', exerciseName: 'Extensión de tríceps en polea', muscleGroup: 'triceps', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60, targetWeightKg: null, notes: null },
          { exerciseId: 'plank',          exerciseName: 'Plancha',          muscleGroup: 'core',     targetSets: 3, targetRepsMin: 20, targetRepsMax: 40, restSeconds: 45, targetWeightKg: null, notes: 'segundos' },
          { exerciseId: 'cable-crunch',   exerciseName: 'Crunch en polea',   muscleGroup: 'core',     targetSets: 3, targetRepsMin: 15, targetRepsMax: 20, restSeconds: 45, targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 2,
        name: 'Jalón + Piernas',
        estimatedMinutes: 50,
        slots: [
          { exerciseId: 'pull-up',           exerciseName: 'Dominadas',           muscleGroup: 'back',       targetSets: 3, targetRepsMin: 5,  targetRepsMax: 8,  restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'lat-pulldown',      exerciseName: 'Jalón al pecho',      muscleGroup: 'back',       targetSets: 3, targetRepsMin: 10, targetRepsMax: 12, restSeconds: 75,  targetWeightKg: null, notes: null },
          { exerciseId: 'barbell-curl',      exerciseName: 'Curl con barra',      muscleGroup: 'biceps',     targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'back-squat',        exerciseName: 'Sentadilla',        muscleGroup: 'quads',      targetSets: 3, targetRepsMin: 10, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'hip-thrust',        exerciseName: 'Empuje de cadera',        muscleGroup: 'glutes',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 75,  targetWeightKg: null, notes: null },
          { exerciseId: 'hanging-leg-raise', exerciseName: 'Elevación de piernas colgado', muscleGroup: 'core',       targetSets: 3, targetRepsMin: 8,  targetRepsMax: 12, restSeconds: 60,  targetWeightKg: null, notes: null },
        ],
      },
      {
        dayNumber: 3,
        name: 'Full + Isométricos',
        estimatedMinutes: 45,
        slots: [
          { exerciseId: 'deadlift',      exerciseName: 'Peso muerto',      muscleGroup: 'back',      targetSets: 3, targetRepsMin: 6,  targetRepsMax: 8,  restSeconds: 120, targetWeightKg: null, notes: null },
          { exerciseId: 'leg-press',     exerciseName: 'Prensa de piernas',     muscleGroup: 'quads',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 90,  targetWeightKg: null, notes: null },
          { exerciseId: 'lateral-raise', exerciseName: 'Elevaciones laterales', muscleGroup: 'shoulders', targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'cable-fly',     exerciseName: 'Cruces en polea',     muscleGroup: 'chest',     targetSets: 3, targetRepsMin: 12, targetRepsMax: 15, restSeconds: 60,  targetWeightKg: null, notes: null },
          { exerciseId: 'plank',         exerciseName: 'Plancha',         muscleGroup: 'core',      targetSets: 4, targetRepsMin: 30, targetRepsMax: 45, restSeconds: 45,  targetWeightKg: null, notes: 'segundos' },
        ],
      },
    ],
  },
];

// -- SEEDERS ---------------------------------------------------------------

async function seedExercises() {
  console.log(`Seeding ${exercises.length} exercises...`);
  for (const ex of exercises) {
    await db.collection('exercises').doc(ex.id).set(ex);
  }
  console.log('Exercises seeded.');
}

// -- VALIDATION ------------------------------------------------------------

function validateRoutineRefs() {
  const exerciseIds = new Set(exercises.map((e) => e.id));
  const errors = [];
  for (const routine of routines) {
    for (const day of routine.days) {
      for (const slot of day.slots) {
        if (!exerciseIds.has(slot.exerciseId)) {
          errors.push(
            `Routine '${routine.id}' day ${day.dayNumber} references ` +
            `unknown exerciseId '${slot.exerciseId}'.`
          );
        }
      }
    }
  }
  if (errors.length > 0) {
    console.error('Orphan reference validation FAILED:');
    for (const e of errors) console.error('  - ' + e);
    throw new Error(
      `${errors.length} orphan reference(s) found. Aborting before any Firestore writes.`
    );
  }
  console.log('Orphan reference validation passed.');
}

// -- SEEDERS (continued) ---------------------------------------------------

async function seedRoutines() {
  validateRoutineRefs();
  console.log(`Seeding ${routines.length} routines...`);
  for (const r of routines) {
    await db.collection('routines').doc(r.id).set(r);
    console.log(`  Seeded routine: ${r.id}`);
  }
  console.log('Routines seeded.');
}

// -- ENTRYPOINT ------------------------------------------------------------

async function main() {
  const args = process.argv.slice(2);
  const doExercises = args.includes('--exercises') || args.includes('--all');
  const doRoutines = args.includes('--routines') || args.includes('--all');

  if (!doExercises && !doRoutines) {
    console.error('Usage: node seed_workout_catalog.js [--exercises|--routines|--all]');
    process.exit(1);
  }

  if (doExercises) await seedExercises();
  if (doRoutines) await seedRoutines();
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
