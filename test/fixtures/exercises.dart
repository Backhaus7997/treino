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
