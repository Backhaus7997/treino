import 'k_formatter.dart';

/// Single source of truth for rendering masses (kg) across the app.
///
/// Two families, two rules:
///
/// * **Weight** — the exact load of a set (player, editor prefill, targets,
///   plan preview): [formatWeightKg]. Never compacted, no redundant `.0`.
/// * **Volume** — an aggregate (session summary, historial, session detail,
///   insights cards): [formatVolumeKg]. Full number below 10 000, floored
///   one-decimal `k` from 10 000 up.
///
/// Neither helper appends the unit: the surface owns it (l10n label, suffix
/// or its own `Text`) and must keep it visible — compact values exist
/// precisely so the unit never gets ellipsized away.

/// Formats an exact weight: whole numbers drop the decimal (`20.0` → `'20'`),
/// fractional values keep theirs (`17.5` → `'17.5'`). Never compacted — a
/// load must read exactly as lifted. `null` → `''` (empty editor field).
String formatWeightKg(double? kg) {
  if (kg == null) return '';
  return kg == kg.truncateToDouble() ? kg.toInt().toString() : kg.toString();
}

/// Volumes below this render in full; from here up they compact to `k` so
/// they fit next to their unit in quarter-width stat cards.
const double _compactVolumeFromKg = 10000;

/// Formats an aggregated volume.
///
/// Below 10 000 the full number is kept — whole values drop the decimal
/// (`600.0` → `'600'`), fractional values round to one (`1234.5` →
/// `'1234.5'`). From 10 000 up it compacts via [kFormatMagnitude] — floored
/// one decimal, because a headline must never inflate (`34 580` → `'34.5k'`)
/// — dropping a redundant `.0` (`12 000` → `'12k'`).
String formatVolumeKg(double kg) {
  if (kg >= _compactVolumeFromKg) {
    final compact = kFormatMagnitude(kg);
    return compact.endsWith('.0k')
        ? '${compact.substring(0, compact.length - 3)}k'
        : compact;
  }
  return kg % 1 == 0 ? kg.toStringAsFixed(0) : kg.toStringAsFixed(1);
}
