import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';

/// Factory for creating test [Exercise] instances with controlled field values.
///
/// Defaults: muscleGroup = 'chest', category = 'compound', equipment = null.
/// T-RER-028.
Exercise testExercise({
  String id = 'test-ex',
  String name = 'Test Exercise',
  String muscleGroup = 'chest',
  String category = 'compound',
  EquipmentType? equipment,
  List<String>? aliases,
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      category: category,
      equipment: equipment,
      aliases: aliases ?? const [],
    );

/// Seed list covering all 6 muscle groups with known equipment values.
/// Used by picker filter combo tests (T-RER-025).
const kExerciseSeed = [
  // ── Pecho (chest) ──────────────────────────────────────────────────────────
  Exercise(
    id: 'bench-press',
    name: 'Press de Banca',
    muscleGroup: 'chest',
    category: 'compound',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'incline-dumbbell-press',
    name: 'Press Inclinado con Mancuerna',
    muscleGroup: 'chest',
    category: 'compound',
    equipment: EquipmentType.mancuerna,
  ),
  // Un ejercicio con un NÚMERO en el nombre. El catálogo real los tiene
  // ("Landmine 180"), y son el caso donde el nombre y la prescripción pueden
  // compartir token: `landmine 180 3x10 180`. Sin uno acá, ese camino de la
  // entrada rápida no se puede probar.
  Exercise(
    id: 'landmine-180',
    name: 'Landmine 180',
    muscleGroup: 'chest',
    category: 'compound',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'cable-fly',
    name: 'Aperturas con Cable',
    muscleGroup: 'chest',
    category: 'isolation',
    equipment: EquipmentType.cable,
  ),

  // ── Espalda (back) ─────────────────────────────────────────────────────────
  Exercise(
    id: 'deadlift',
    name: 'Peso Muerto',
    muscleGroup: 'back',
    category: 'compound',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'pull-up',
    name: 'Dominadas',
    muscleGroup: 'back',
    category: 'compound',
    equipment: EquipmentType.pesoCorporal,
  ),
  Exercise(
    id: 'lat-pulldown',
    name: 'Jalón al Pecho',
    muscleGroup: 'back',
    category: 'isolation',
    equipment: EquipmentType.cable,
  ),

  // ── Piernas (quads/hamstrings) ─────────────────────────────────────────────
  Exercise(
    id: 'back-squat',
    name: 'Sentadilla con Barra',
    muscleGroup: 'quads',
    category: 'compound',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'leg-press',
    name: 'Prensa de Piernas',
    muscleGroup: 'quads',
    category: 'compound',
    equipment: EquipmentType.maquina,
  ),
  Exercise(
    id: 'leg-curl',
    name: 'Curl de Piernas',
    muscleGroup: 'hamstrings',
    category: 'isolation',
    equipment: EquipmentType.maquina,
  ),

  // ── Hombros (shoulders) ────────────────────────────────────────────────────
  Exercise(
    id: 'overhead-press',
    name: 'Press Militar',
    muscleGroup: 'shoulders',
    category: 'compound',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'lateral-raise',
    name: 'Elevaciones Laterales',
    muscleGroup: 'shoulders',
    category: 'isolation',
    equipment: EquipmentType.mancuerna,
  ),

  // ── Brazos (biceps/triceps) ────────────────────────────────────────────────
  Exercise(
    id: 'barbell-curl',
    name: 'Curl con Barra',
    muscleGroup: 'biceps',
    category: 'isolation',
    equipment: EquipmentType.barra,
  ),
  Exercise(
    id: 'hammer-curl',
    name: 'Curl Martillo',
    muscleGroup: 'biceps',
    category: 'isolation',
    equipment: EquipmentType.mancuerna,
  ),
  Exercise(
    id: 'tricep-pushdown',
    name: 'Extensión de Tríceps en Cable',
    muscleGroup: 'triceps',
    category: 'isolation',
    equipment: EquipmentType.cable,
  ),

  // ── Core (abs) ─────────────────────────────────────────────────────────────
  Exercise(
    id: 'plank',
    name: 'Plancha',
    muscleGroup: 'core',
    category: 'isolation',
    equipment: EquipmentType.pesoCorporal,
  ),
  Exercise(
    id: 'cable-crunch',
    name: 'Crunch en Cable',
    muscleGroup: 'core',
    category: 'isolation',
    equipment: EquipmentType.cable,
  ),
];

/// Busca un ejercicio del seed por su `id`.
///
/// Los tests que arman su propia lista tienen que usar ESTO, nunca
/// `kExerciseSeed[n]`. El índice posicional se rompe en silencio: cuando #918
/// insertó `lat-pulldown` en el medio del seed, `[6]` dejó de ser `back-squat`
/// y los dos pickers se cayeron con ocho "Found 0 widgets with text ..." que
/// no decían una palabra de la causa real.
///
/// Tira si el id no existe, que es exactamente lo que querés: un id mal escrito
/// falla con el nombre adentro del mensaje, no con una lista vacía.
Exercise seedExercise(String id) => kExerciseSeed.firstWhere((e) => e.id == id);
