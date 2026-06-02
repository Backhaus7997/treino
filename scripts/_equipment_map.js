/**
 * Single source of truth for exercise → equipment mapping.
 *
 * Used by both `seed_workout_catalog.js` (catalog seed) and
 * `backfill_exercise_equipment.js` (one-shot prod backfill).
 *
 * Format: { exerciseId: equipmentJsonValue }
 *
 * Equipment values must match EquipmentType.jsonValue in
 * lib/features/workout/domain/equipment_type.dart:
 *   mancuerna · barra · maquina · cable · banda ·
 *   peso_corporal · cardio · otro · ninguno
 *
 * Heuristic: based on the exercise name's implied equipment (e.g.
 * "Press de banca" with default form → barra; "Cruces en polea" → cable).
 * Unmapped exercises stay null (filter treats null as "match all").
 *
 * See ADR-RER-03 of sdd/routine-editor-redesign.
 */

'use strict';

const equipmentMap = Object.freeze({
  // Pecho
  'bench-press': 'barra',
  'incline-dumbbell-press': 'mancuerna',
  'cable-fly': 'cable',

  // Espalda
  'deadlift': 'barra',
  'barbell-row': 'barra',
  'pull-up': 'peso_corporal',
  'lat-pulldown': 'cable',
  'face-pull': 'cable',

  // Hombros
  'overhead-press': 'barra',
  'lateral-raise': 'mancuerna',

  // Piernas
  'back-squat': 'barra',
  'leg-press': 'maquina',
  'leg-extension': 'maquina',
  'romanian-deadlift': 'barra',
  'leg-curl': 'maquina',
  'hip-thrust': 'barra',
  'calf-raise': 'maquina',

  // Bíceps
  'barbell-curl': 'barra',
  'hammer-curl': 'mancuerna',

  // Tríceps
  'tricep-pushdown': 'cable',
  'skull-crusher': 'barra',

  // Core
  'plank': 'peso_corporal',
  'cable-crunch': 'cable',
  'hanging-leg-raise': 'peso_corporal',
});

module.exports = { equipmentMap };
