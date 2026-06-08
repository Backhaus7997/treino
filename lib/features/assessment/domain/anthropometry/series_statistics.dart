import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

/// Summary statistics for a series of repeated measurements.
///
/// The proforma allows up to 5 series per measurement to assess intra-rater
/// reliability. This object captures the central tendency and dispersion.
@immutable
class SeriesSummary {
  const SeriesSummary({
    required this.median,
    required this.sd,
    required this.errorPct,
  });

  /// Median of the series.
  /// Even-count series: mean of the two middle values.
  final double median;

  /// Population standard deviation.
  final double sd;

  /// Coefficient of variation as a percentage: (sd / median) × 100.
  /// Falls back to [defaultErrorPct] when median is 0 or fewer than 2 values.
  // PENDING_VERIFICATION: confirm whether proforma's "% error" is
  // sd/median*100 (CV) or something else (e.g. SEM, TEM).
  final double errorPct;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SeriesSummary &&
        other.median == median &&
        other.sd == sd &&
        other.errorPct == errorPct;
  }

  @override
  int get hashCode => Object.hash(median, sd, errorPct);

  @override
  String toString() =>
      'SeriesSummary(median: $median, sd: $sd, errorPct: $errorPct)';
}

/// Computes summary statistics for a series of repeated measurement [values].
///
/// [defaultErrorPct] is used when:
///   - [values] has fewer than 2 entries (can't compute meaningful dispersion), OR
///   - computed median is 0 (division by zero guard).
///
/// Median: proper statistical median.
///   - Odd count  → middle value.
///   - Even count → mean of the two middle values.
///
/// SD: population standard deviation (not sample/Bessel-corrected).
SeriesSummary summarizeSeries(
  List<double> values, {
  double defaultErrorPct = 2.0,
}) {
  if (values.isEmpty) {
    return SeriesSummary(
      median: 0,
      sd: 0,
      errorPct: defaultErrorPct,
    );
  }

  // ── Median ──
  final sorted = List<double>.from(values)..sort();
  final n = sorted.length;
  final double med;
  if (n.isOdd) {
    med = sorted[n ~/ 2];
  } else {
    med = (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
  }

  // ── Population SD ──
  double sd = 0;
  if (n >= 2) {
    final mean = values.fold(0.0, (a, b) => a + b) / n;
    final variance =
        values.fold(0.0, (a, b) => a + (b - mean) * (b - mean)) / n;
    sd = sqrt(variance);
  }

  // ── Error % ──
  final double errPct;
  if (n < 2 || med == 0) {
    errPct = defaultErrorPct;
  } else {
    errPct = (sd / med) * 100;
  }

  return SeriesSummary(median: med, sd: sd, errorPct: errPct);
}
