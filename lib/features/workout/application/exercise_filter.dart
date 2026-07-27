/// Pure filter utilities for the exercise catalogue.
///
/// Extracted from [_ExercisePickerSheetContentState] so the same predicate
/// can be reused in the Coach Hub web Biblioteca section without pulling
/// in Flutter/Riverpod dependencies.
///
/// ADR-BIBW-01: placed in `application/` (same layer as session_providers.dart,
/// exercise_providers.dart) because `foldSearch` is a UI search concern, not
/// an entity invariant.
///
/// ADR-RER-05: exercises with null equipment are EXCLUDED when any equipment
/// filter is active (see [exerciseMatchesFilters]).
library;

import '../domain/custom_exercise.dart';
import '../domain/equipment_type.dart';
import '../domain/exercise.dart';
import '../domain/muscle_group.dart';

/// Whitespace runs — tokenizes multi-word queries. Hoisted because the
/// predicate runs once per candidate exercise per keystroke.
final _whitespace = RegExp(r'\s+');

/// Lowercases and strips Spanish diacritics so the search field tolerates
/// accent and case typos: "elevacion" matches "Elevación", "BICEPS" matches
/// "Bíceps". Applied to both the query and the candidate text before matching.
///
/// MOVED verbatim from `exercise_picker_sheet.dart` lines 36–47.
String foldSearch(String input) {
  final lower = input.toLowerCase();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buf = StringBuffer();
  for (final code in lower.runes) {
    final ch = String.fromCharCode(code);
    final idx = from.indexOf(ch);
    buf.write(idx >= 0 ? to[idx] : ch);
  }
  return buf.toString();
}

/// Returns `true` when [e] satisfies all active filters simultaneously
/// (AND across filter dimensions, OR within each dimension).
///
/// This is a line-for-line lift of `_matches` from
/// `exercise_picker_sheet.dart` lines 102–126, with the three widget-scoped
/// fields (`_query`, `_muscleFilters`, `_equipmentFilters`) promoted to named
/// parameters so the predicate is pure and testable.
///
/// Rules:
/// - Query: diacritic-tolerant, tokenized on whitespace — an exercise matches
///   when EVERY token appears in the folded name (any order), or when every
///   token appears within a single folded alias. One-word queries behave
///   exactly like the original substring match.
/// - Muscles: primary OR secondary match against filter set; empty set = pass.
/// - Equipment: OR within set; **empty set = pass all (including null)**;
///   **non-empty set = EXCLUDE exercises with null equipment** (ADR-RER-05).
bool exerciseMatchesFilters(
  Exercise e, {
  required String query,
  required Set<MuscleGroup> muscles,
  required Set<EquipmentType> equipment,
}) {
  final q = foldSearch(query).trim();
  if (q.isNotEmpty) {
    // Tokenized AND-match: every word of the query must appear in the name
    // (any order) — "press banca" finds "Press de Banca (Barra)" despite the
    // missing "de". Aliases match when ALL tokens hit the same alias.
    final tokens = q.split(_whitespace);
    final name = foldSearch(e.name);
    final nameMatch = tokens.every(name.contains);
    final aliasMatch = e.aliases.any((a) {
      final alias = foldSearch(a);
      return tokens.every(alias.contains);
    });
    if (!nameMatch && !aliasMatch) return false;
  }
  // OR within muscle filter, AND across filter types. An exercise matches if
  // EITHER its primary or its (optional) secondary muscle is in the filter,
  // so e.g. "estocada a press" surfaces under both Cuádriceps and Hombros.
  if (muscles.isNotEmpty) {
    final primary = MuscleGroup.fromKey(e.muscleGroup);
    final secondary = MuscleGroup.fromKey(e.secondaryMuscleGroup);
    final hit = (primary != null && muscles.contains(primary)) ||
        (secondary != null && muscles.contains(secondary));
    if (!hit) return false;
  }
  // ADR-RER-05: EXCLUDE exercises with null equipment when ANY equipment
  // filter is active. OR within equipment filter.
  if (equipment.isNotEmpty) {
    if (e.equipment == null) return false;
    if (!equipment.contains(e.equipment)) return false;
  }
  return true;
}

/// Lossy adapter — projects the fields the routine slot needs and stamps
/// `category: 'custom'` so downstream code can distinguish custom exercises.
///
/// PROMOTED verbatim from picker's `_toExercise` (lines 883–895). Lossiness
/// is safe for read-only surfaces; the detail dialog re-fetches the full
/// custom doc via `slotExerciseProvider(ownerId:)`.
Exercise customToExercise(CustomExercise c) {
  return Exercise(
    id: c.id,
    name: c.name,
    muscleGroup: c.muscleGroup,
    secondaryMuscleGroup: c.secondaryMuscleGroup,
    category: 'custom',
    techniqueInstructions: null,
    videoUrl: c.videoUrl,
    defaultRestSeconds: c.defaultRestSeconds,
    equipment: c.equipment,
  );
}
