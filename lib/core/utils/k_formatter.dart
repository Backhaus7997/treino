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

/// Formats a magnitude value (e.g. lifted volume in kg) for compact display
/// WITHOUT overstating it.
///
/// Unlike [kFormat], this never rounds up: values >= 1000 are floored to one
/// decimal `'X.Yk'` so a headline number is never inflated. Below 1000 the
/// integer string is returned. Negative values are formatted as plain integers.
///
/// Examples:
/// ```dart
/// kFormatMagnitude(999)    → '999'
/// kFormatMagnitude(1000)   → '1.0k'
/// kFormatMagnitude(1499)   → '1.4k'
/// kFormatMagnitude(1500)   → '1.5k'
/// kFormatMagnitude(92000)  → '92.0k'
/// ```
String kFormatMagnitude(num value) {
  if (value >= 1000) {
    // Floor to one decimal so the displayed value is never higher than the
    // real one (a fitness headline must not inflate total volume).
    final tenths = (value / 100).floor() / 10;
    return '${tenths.toStringAsFixed(1)}k';
  }
  return value.toInt().toString();
}
