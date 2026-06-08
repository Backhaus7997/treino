import 'package:flutter/foundation.dart';

import 'anthropometric_indices.dart';
import 'body_composition.dart';
import 'somatotype.dart';

/// Aggregated output of a full anthropometric assessment.
///
/// Bundles the Heath-Carter somatotype, Kerr five-mass body composition,
/// and derived indices computed from [AnthropometricProfile].
@immutable
class AnthropometryResult {
  const AnthropometryResult({
    required this.somatotype,
    required this.composition,
    required this.bsaM2,
    required this.bmiValue,
    required this.hwrValue,
    required this.bmrHarrisBenedictKcal,
    this.waistHipRatioValue,
    this.waistHipRiskLevel,
    this.bmrCunninghamKcal,
  });

  final Somatotype somatotype;
  final BodyComposition composition;

  /// Body surface area (m²), Du Bois formula.
  final double bsaM2;

  /// Body Mass Index (kg/m²).
  final double bmiValue;

  /// Height-weight ratio / ponderal index.
  final double hwrValue;

  /// Harris-Benedict BMR (kcal/day).
  final double bmrHarrisBenedictKcal;

  /// Waist-to-hip ratio. Null if waistMin or hipMax were missing.
  final double? waistHipRatioValue;

  /// Waist-hip risk category. Null if [waistHipRatioValue] is null.
  final WaistHipRisk? waistHipRiskLevel;

  /// Cunningham BMR (kcal/day). Null if fat-free mass could not be derived
  /// (requires adipose mass, which is PENDING_VERIFICATION).
  final double? bmrCunninghamKcal;

  AnthropometryResult copyWith({
    Somatotype? somatotype,
    BodyComposition? composition,
    double? bsaM2,
    double? bmiValue,
    double? hwrValue,
    double? bmrHarrisBenedictKcal,
    double? waistHipRatioValue,
    WaistHipRisk? waistHipRiskLevel,
    double? bmrCunninghamKcal,
  }) {
    return AnthropometryResult(
      somatotype: somatotype ?? this.somatotype,
      composition: composition ?? this.composition,
      bsaM2: bsaM2 ?? this.bsaM2,
      bmiValue: bmiValue ?? this.bmiValue,
      hwrValue: hwrValue ?? this.hwrValue,
      bmrHarrisBenedictKcal:
          bmrHarrisBenedictKcal ?? this.bmrHarrisBenedictKcal,
      waistHipRatioValue: waistHipRatioValue ?? this.waistHipRatioValue,
      waistHipRiskLevel: waistHipRiskLevel ?? this.waistHipRiskLevel,
      bmrCunninghamKcal: bmrCunninghamKcal ?? this.bmrCunninghamKcal,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnthropometryResult &&
        other.somatotype == somatotype &&
        other.composition == composition &&
        other.bsaM2 == bsaM2 &&
        other.bmiValue == bmiValue &&
        other.hwrValue == hwrValue &&
        other.bmrHarrisBenedictKcal == bmrHarrisBenedictKcal &&
        other.waistHipRatioValue == waistHipRatioValue &&
        other.waistHipRiskLevel == waistHipRiskLevel &&
        other.bmrCunninghamKcal == bmrCunninghamKcal;
  }

  @override
  int get hashCode => Object.hash(
        somatotype,
        composition,
        bsaM2,
        bmiValue,
        hwrValue,
        bmrHarrisBenedictKcal,
        waistHipRatioValue,
        waistHipRiskLevel,
        bmrCunninghamKcal,
      );
}
