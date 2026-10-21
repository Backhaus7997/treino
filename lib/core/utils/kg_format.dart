import 'package:intl/intl.dart';

/// Single source of truth for rendering masses (kg) across the app.
///
/// Three helpers, two audiences:
///
/// * **Editable field** (editor prefill, measurement/evaluation forms):
///   [formatWeightKg]. Locale-free on purpose: no grouping and a `.`
///   decimal, because the field's parser accepts both separators and a
///   grouped `5.000` would parse back as 5.
/// * **Display weight** — the exact load of a set as READ (player, targets,
///   plan preview, historial): [formatWeightDisplay]. Locale-aware: `12,5`
///   and `1.234,5` in es (#1481, #1512). Never compacted.
/// * **Display volume** — an aggregate (session summary, historial, session
///   detail, insights cards, profile): [formatVolumeKg]. Locale-aware, full
///   number below 10 000 (`9.600`, #1465), floored one-decimal `k` from
///   10 000 up (`20,7k`; `66k`, never `66.0k` — #1516).
///
/// Before #1465 none of them knew the locale: every screen in Spanish showed
/// `12.5 kg` and `9600 kg`.
///
/// Neither helper appends the unit: the surface owns it (l10n label, suffix
/// or its own `Text`) and must keep it visible — compact values exist
/// precisely so the unit never gets ellipsized away.

/// Formats a weight for an EDITABLE field: whole numbers drop the decimal
/// (`20.0` → `'20'`), fractional values keep theirs (`17.5` → `'17.5'`).
/// Never grouped, never compacted, never localized — see the header.
/// `null` → `''` (empty editor field). For text the user READS, use
/// [formatWeightDisplay].
String formatWeightKg(double? kg) {
  if (kg == null) return '';
  return kg == kg.truncateToDouble() ? kg.toInt().toString() : kg.toString();
}

/// Formats an exact weight for DISPLAY in [localeName]: up to two decimals
/// with the locale's separator, grouped thousands, no redundant `,0`
/// (`12.5` → `'12,5'`, `1234.5` → `'1.234,5'` in es). Never compacted — a
/// load must read exactly as lifted.
String formatWeightDisplay(double kg, String localeName) =>
    NumberFormat('#,##0.##', localeName).format(kg);

/// Volumes below this render in full; from here up they compact to `k` so
/// they fit next to their unit in quarter-width stat cards.
const double _compactVolumeFromKg = 10000;

/// Formats an aggregated volume for DISPLAY in [localeName].
///
/// Below 10 000 the full number is kept, grouped, one decimal at most
/// (`9600` → `'9.600'`, `1234.5` → `'1.234,5'` in es). From 10 000 up it
/// compacts to thousands with a `k`, FLOORED to one decimal because a
/// headline must never inflate (`34 580` → `'34,5k'`), dropping a redundant
/// `,0` (`66 057,5` → `'66k'`, not `'66.0k'`).
///
/// `k` and not «mil»: the compact form exists so the value fits next to its
/// unit in quarter-width cards; « mil» is four characters wider.
String formatVolumeKg(double kg, String localeName) {
  final format = NumberFormat('#,##0.#', localeName);
  if (kg >= _compactVolumeFromKg) {
    final thousands = (kg / 100).floor() / 10;
    return '${format.format(thousands)}k';
  }
  return format.format(kg);
}

/// Formats any other number READ on screen (cm, seconds, hours, levels,
/// deltas) in [localeName]: grouped thousands, at most [maxDecimals]
/// decimals, no redundant `,0` (`78.5` → `'78,5'`, `3100` → `'3.100'` in es).
///
/// Replaces the per-screen `v % 1 == 0 ? toStringAsFixed(0) :
/// toStringAsFixed(1)` helpers, which ignored the locale. Like the other
/// display helpers, NEVER for an editable field.
String formatNumberDisplay(
  num value,
  String localeName, {
  int maxDecimals = 1,
}) {
  final pattern = maxDecimals <= 0 ? '#,##0' : '#,##0.${'#' * maxDecimals}';
  return NumberFormat(pattern, localeName).format(value);
}
