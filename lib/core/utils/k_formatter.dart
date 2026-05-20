/// Formats a numeric value for compact display.
///
/// Returns `'Xk'` when [value] >= 1000, otherwise returns the integer string.
/// Negative values are formatted as plain integers (no k suffix).
///
/// Examples:
/// ```dart
/// kFormat(0)     → '0'
/// kFormat(999)   → '999'
/// kFormat(1000)  → '1k'
/// kFormat(1500)  → '2k'
/// kFormat(92000) → '92k'
/// ```
String kFormat(num value) {
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)}k';
  }
  return value.toInt().toString();
}
