// Date formatting helpers for the workout historial feature.
// Pure functions — no Riverpod, no BuildContext, no intl dependency.

/// Weekday abbreviations in Spanish (Rioplatense).
/// [DateTime.weekday]: 1 = Monday … 7 = Sunday.
const Map<int, String> _kDow = {
  1: 'Lun',
  2: 'Mar',
  3: 'Mié',
  4: 'Jue',
  5: 'Vie',
  6: 'Sáb',
  7: 'Dom',
};

/// Month abbreviations in Spanish (Rioplatense).
/// [DateTime.month]: 1 = January … 12 = December.
const Map<int, String> _kMonth = {
  1: 'ene',
  2: 'feb',
  3: 'mar',
  4: 'abr',
  5: 'may',
  6: 'jun',
  7: 'jul',
  8: 'ago',
  9: 'sep',
  10: 'oct',
  11: 'nov',
  12: 'dic',
};

/// Formats [date] as `"Mié 27 nov"` — weekday abbrev, day (no zero-pad), month abbrev.
///
/// [now] is accepted for API stability (potential future use by Insights/Etapa 5)
/// but does NOT affect the output in this etapa.
///
/// Examples:
/// ```dart
/// formatSessionDate(DateTime(2025, 11, 26)) // → "Mié 26 nov"
/// formatSessionDate(DateTime(2025, 3, 7))   // → "Vie 7 mar"
/// ```
String formatSessionDate(DateTime date, {DateTime? now}) {
  final dow = _kDow[date.weekday]!;
  final month = _kMonth[date.month]!;
  return '$dow ${date.day} $month';
}
