import 'dart:math' show pow;

import 'package:flutter/foundation.dart';

import 'anthropometric_profile.dart';

/// Heath-Carter somatotype result. Carter & Heath 1990.
///
/// Components are stored at full floating-point precision.
/// Use [x] and [y] for somatochart plotting.
@immutable
class Somatotype {
  const Somatotype({
    required this.endomorphy,
    required this.mesomorphy,
    required this.ectomorphy,
  });

  final double endomorphy;
  final double mesomorphy;
  final double ectomorphy;

  /// Somatochart X-axis: ectomorphy − endomorphy.
  double get x => ectomorphy - endomorphy;

  /// Somatochart Y-axis: 2×mesomorphy − (endomorphy + ectomorphy).
  double get y => 2 * mesomorphy - (endomorphy + ectomorphy);

  Somatotype copyWith({
    double? endomorphy,
    double? mesomorphy,
    double? ectomorphy,
  }) {
    return Somatotype(
      endomorphy: endomorphy ?? this.endomorphy,
      mesomorphy: mesomorphy ?? this.mesomorphy,
      ectomorphy: ectomorphy ?? this.ectomorphy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Somatotype &&
        other.endomorphy == endomorphy &&
        other.mesomorphy == mesomorphy &&
        other.ectomorphy == ectomorphy;
  }

  @override
  int get hashCode => Object.hash(endomorphy, mesomorphy, ectomorphy);

  @override
  String toString() =>
      'Somatotype(endo: $endomorphy, meso: $mesomorphy, ecto: $ectomorphy)';
}

/// Calculates the Heath-Carter somatotype from raw anthropometric data.
///
/// Requires (throws [ArgumentError] if any mandatory input is null):
///   Endomorphy  → triceps, subscapular, supraspinale skinfolds + heightCm
///   Mesomorphy  → humerusBiepicondylar, femurBiepicondylar, flexedArm,
///                 triceps, calfMax, calfMedial, heightCm
///   Ectomorphy  → heightCm, weightKg
///
/// NOTE: mesomorphy uses FLEXED arm girth (not relaxed).
///       Kerr muscle mass uses RELAXED arm — these are intentionally different.
///
/// Source: Carter & Heath 1990.
Somatotype calculateSomatotype(AnthropometricProfile p) {
  // ─── ENDOMORPHY ───────────────────────────────────────────────────────────
  // Requires: triceps, subscapular, supraspinale (mm), heightCm
  final tri = p.triceps;
  final sub = p.subscapular;
  final sup = p.supraspinale;

  if (tri == null || sub == null || sup == null) {
    throw ArgumentError(
      'calculateSomatotype: triceps, subscapular, and supraspinale '
      'skinfolds are required for endomorphy.',
    );
  }

  // Height-corrected sum of 3 skinfolds (mm).
  final x = (tri + sub + sup) * (170.18 / p.heightCm);
  var endo = -0.7182 + 0.1451 * x - 0.00068 * x * x + 0.0000014 * x * x * x;
  if (endo < 0.1) endo = 0.1; // floor per Carter & Heath

  // ─── MESOMORPHY ───────────────────────────────────────────────────────────
  // Requires: humerusBiepicondylar, femurBiepicondylar (cm), flexedArm (cm),
  //           triceps (mm), calfMax (cm), calfMedial (mm), heightCm
  final humBiep = p.humerusBiepicondylar;
  final femBiep = p.femurBiepicondylar;
  final flexArm = p.flexedArm;
  final calfG = p.calfMax;
  final calfSk = p.calfMedial;

  if (humBiep == null ||
      femBiep == null ||
      flexArm == null ||
      calfG == null ||
      calfSk == null) {
    throw ArgumentError(
      'calculateSomatotype: humerusBiepicondylar, femurBiepicondylar, '
      'flexedArm, calfMax, and calfMedial are required for mesomorphy.',
    );
  }

  // Skinfold corrections: mm ÷ 10 → cm, subtracted from girth.
  final correctedArm = flexArm - tri / 10;
  final correctedCalf = calfG - calfSk / 10;

  final meso = 0.858 * humBiep +
      0.601 * femBiep +
      0.188 * correctedArm +
      0.161 * correctedCalf -
      0.131 * p.heightCm +
      4.5;

  // ─── ECTOMORPHY ───────────────────────────────────────────────────────────
  // Ponderal index (HWR): height (cm) / cube-root of weight (kg).
  final hwrValue = p.heightCm / pow(p.weightKg, 1 / 3).toDouble();

  double ecto;
  if (hwrValue >= 40.75) {
    ecto = 0.732 * hwrValue - 28.58;
  } else if (hwrValue > 38.25) {
    ecto = 0.463 * hwrValue - 17.63;
  } else {
    ecto = 0.1;
  }

  return Somatotype(endomorphy: endo, mesomorphy: meso, ectomorphy: ecto);
}
