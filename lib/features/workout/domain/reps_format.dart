// Pure helpers for the per-set reps field.
//
// Convention:
//   [] → no value / legacy
//   [10] → uniform reps across all sets
//   [6, 8, 10] → explicit per-set progression

/// Parses a user-entered reps string into a list of non-negative integers.
///
/// Accepts:
///   "10"        → [10]
///   "6-8-10"    → [6, 8, 10]
///   "6 - 8 - 10" → [6, 8, 10]  (spaces around dashes)
///   "10/8/6"    → [10, 8, 6]   (slash separator)
///   "6 8 10"    → [6, 8, 10]   (space separator)
///
/// Invalid or empty input returns [].
List<int> parseReps(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return [];

  // A dash is only a separator when it sits *between* two digits (e.g. "6-8").
  // A dash that acts as a sign (start of input or after another separator,
  // followed by a digit) means negative reps → reject the whole input, since
  // the split below would otherwise swallow it and accept a positive value.
  if (RegExp(r'(^|[\s/-])-\d').hasMatch(trimmed)) return [];

  // Split on dashes, slashes, or whitespace (one or more of each).
  final parts = trimmed.split(RegExp(r'[\s/\-]+'));
  final result = <int>[];
  for (final part in parts) {
    final p = part.trim();
    if (p.isEmpty) continue;
    final n = int.tryParse(p);
    if (n == null || n < 0) {
      return []; // any invalid token → whole thing invalid
    }
    result.add(n);
  }
  return result;
}

/// Formats a list of reps back to a display string.
///
///   [] → ""
///   [10] → "10"
///   [6, 8, 10] → "6-8-10"
String formatReps(List<int> reps) {
  if (reps.isEmpty) return '';
  return reps.join('-');
}
