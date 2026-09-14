'use strict';

/**
 * seed_workout_catalog.js
 *
 * Siembra el stock de EJERCICIOS. Las plantillas del catálogo NO se siembran
 * desde acá — ver `seed_templates.js` y el mensaje de `--routines`.
 *
 * 🚨 ESCRIBE EN PRODUCCIÓN por Admin SDK —salteándose las rules— salvo que
 * apuntes al emulador. Es el entrypoint de `npm run seed:exercises`, que no
 * nombra el proyecto: lo resuelve la credencial que apunta `$TREINO_SA_KEY`
 * (#834). El que SÍ trae las env vars del emulador es `seed:emulator`, que es
 * la EXCEPCIÓN, no el default. Imprime un cartel antes del primer write cuando
 * el destino es producción.
 *
 *   # Emulador (recomendado):
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 node scripts/seed_workout_catalog.js --exercises
 *
 * ─── Por qué se le sacó la mitad de rutinas (2026-09-14) ───
 *
 * Este archivo tenía un array `routines` con seis plantillas y su propio
 * validador de referencias. El validador pasaba siempre, y ahí estaba la
 * trampa: validaba las rutinas contra los 25 ejercicios de ESTE archivo, o
 * sea contra sí mismo. Una burbuja auto-consistente no prueba nada del
 * catálogo real.
 *
 * Medido contra producción: de las 116 referencias a `exerciseId` que tenían
 * esas seis rutinas, CERO existen entre los 793 ejercicios de la colección.
 * Los dos vocabularios son disjuntos. Y como el `.set()` es reemplazo total,
 * `npm run seed:all` dejaba el catálogo con seis plantillas donde cada
 * ejercicio apunta a un documento que no está — además de borrarles
 * `isPremium`, `summary` y `goals`, que este archivo nunca supo que existían.
 *
 * Producción coincide hoy con `improved-templates.json` en las 7 plantillas,
 * no con lo que había acá. El array era un fósil.
 *
 * Contexto: #826 · #834 · scripts/README.md · AGENTS.md → Entornos.
 */

const { inicializarAdmin } = require('./lib/admin');
const { getFirestore } = require('firebase-admin/firestore');
const { equipmentMap } = require('./_equipment_map.js');
const { videoMap } = require('./_video_map.js');

// El cartel va ANTES de inicializar: cuando `seed_emulator_full.js` requiere
// este módulo ya inicializó su propia app contra el emulador, y ahí no hay nada
// que advertir — `inicializarAdmin` es idempotente y devuelve la que ya existe,
// y con Firestore desviado `bannerDeProduccion` calla solo. Fuera de ese caso,
// `npm run seed:all` escribe el catálogo entero en producción sin que
// `treino-dev` aparezca una sola vez en pantalla. (#826)
const { bannerDeProduccion } = require('./lib/firebase_projects');
const { contraEmuladorDe, projectIdObjetivo } = require('./lib/target_project');
// #846 — por servicio, no por OR. Este script escribe SÓLO en Firestore (un
// único `admin.firestore()`, ni Auth ni Storage), y el viejo `usandoEmulador()`
// también miraba `FIREBASE_AUTH_EMULATOR_HOST`: esa variable suelta —la que
// queda exportada de una sesión de `emulator.sh`— apagaba el cartel de
// `npm run seed:all` sin desviar un solo write.
const bannerProd = bannerDeProduccion(projectIdObjetivo(), {
  contraEmulador: contraEmuladorDe(['firestore']),
});
if (bannerProd) console.warn(bannerProd);

// Credenciales: la única puerta (#834).
const { app } = inicializarAdmin();
const db = getFirestore(app);

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

// -- SEEDERS ---------------------------------------------------------------

// Builds the Firestore doc for one catalogue exercise.
// - `equipment` from the shared map (REQ-RER-015, ADR-RER-03). Unmapped
//   exercises stay without the field — filter treats null as "match all".
//   The map is the single source of truth, shared with
//   scripts/backfill_exercise_equipment.js.
// - `videoUrl` from the shared video map (musclewiki.com URLs).
//   ExerciseVideoPlayer opens these in an in-app browser. Shared with
//   scripts/backfill_exercise_videos.js.
function buildExerciseDoc(ex) {
  const equipment = equipmentMap[ex.id];
  const videoUrl = videoMap[ex.id];
  return {
    ...ex,
    ...(equipment ? { equipment } : {}),
    ...(videoUrl ? { videoUrl } : {}),
  };
}

async function seedExercises() {
  console.log(`Seeding ${exercises.length} exercises...`);
  for (const ex of exercises) {
    await db.collection('exercises').doc(ex.id).set(buildExerciseDoc(ex));
  }
  console.log('Exercises seeded.');
}

// -- ENTRYPOINT ------------------------------------------------------------

// `--routines` y `--all` NO se ignoran ni se reinterpretan: cortan con un
// mensaje. Aceptarlos en silencio haciendo sólo los ejercicios sería cambiarle
// el significado a un comando que alguien tiene en la memoria muscular, y eso
// es lo que dejó pasar el problema durante tres meses. Si tu dedo escribe
// `--all`, la terminal te dice adónde se mudaron las rutinas.
const RUTINAS_SE_MUDARON = [
  '',
  'Este script YA NO siembra /routines. Sembraba seis plantillas con un',
  'vocabulario de 25 ejercicios que el catálogo vivo dejó atrás: sus 116',
  'referencias a exerciseId no existen entre los 793 de producción, así que',
  'correrlo dejaba el catálogo apuntando a documentos que no están.',
  '',
  'Las plantillas del catálogo se siembran con:',
  '',
  '    node scripts/seed_templates.js            # dry-run, no escribe',
  '    node scripts/seed_templates.js --write    # escribe',
  '',
  'Lee docs/video-catalog-audit/improved-templates.json, que es la fuente, y',
  'valida cada exerciseId contra enriched-catalog.json antes de escribir.',
  '',
].join('\n');

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('--routines') || args.includes('--all')) {
    console.error(RUTINAS_SE_MUDARON);
    process.exit(1);
  }

  if (!args.includes('--exercises')) {
    console.error('Usage: node seed_workout_catalog.js --exercises');
    process.exit(1);
  }

  await seedExercises();
}

if (require.main === module) {
  main().catch((err) => {
    console.error('Seed failed:', err);
    process.exit(1);
  });
}

// Reusado por seed_emulator_full.js para poblar el picker de ejercicios del
// emulador.
//
// ⚠️ NO es "el mismo catálogo que prod", que es lo que decía este comentario.
// Producción tiene 793 ejercicios con otro esquema de ids (`bench-press-barra`,
// `push-up-pesocorporal`); estos 25 usan el viejo (`bench-press`) y NINGUNO
// existe allá. Medido contra producción el 2026-09-14.
//
// Para el emulador da igual —lo único que se pide de estos 25 es que el picker
// tenga con qué llenarse— y `seed_emulator_full.js:1291` ya documenta que sus
// rutinas usan un tercer juego de ids a propósito. Pero el cartel viejo hacía
// creer que este archivo era una réplica de producción, y sobre esa creencia
// es que `--all` parecía inofensivo.
module.exports = { exercises, buildExerciseDoc };
