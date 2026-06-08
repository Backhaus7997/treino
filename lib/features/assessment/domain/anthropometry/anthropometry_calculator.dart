import 'anthropometric_indices.dart';
import 'anthropometric_profile.dart';
import 'anthropometry_result.dart';
import 'body_composition.dart';
import 'somatotype.dart';

/// Orchestrates all anthropometric calculations and returns a single
/// [AnthropometryResult] from a raw [AnthropometricProfile].
///
/// Cunningham BMR is omitted when adipose mass is PENDING_VERIFICATION,
/// because fat-free mass (FFM = structured weight − adipose) cannot be derived.
AnthropometryResult evaluate(AnthropometricProfile profile) {
  // ── Somatotype ──
  final soma = calculateSomatotype(profile);

  // ── Body composition ──
  final comp = calculateBodyComposition(profile);

  // ── Indices ──
  final bsa = bsaDuBois(profile.weightKg, profile.heightCm);
  final bmiVal = bmi(profile.weightKg, profile.heightCm);
  final hwrVal = hwr(profile.weightKg, profile.heightCm);
  final bmrHB = bmrHarrisBenedict(
    profile.sex,
    profile.weightKg,
    profile.heightCm,
    profile.ageYears,
  );

  // ── Waist-hip ratio (optional) ──
  double? whrValue;
  WaistHipRisk? whrRisk;
  if (profile.waistMin != null && profile.hipMax != null) {
    whrValue = waistHipRatio(profile.waistMin!, profile.hipMax!);
    whrRisk = waistHipRisk(profile.sex, profile.ageYears, whrValue);
  }

  // ── Cunningham BMR ──
  // FFM = structuredWeight − adipose.
  // Adipose is PENDING_VERIFICATION → bmrCunningham stays null for now.
  double? bmrCunn;
  if (comp.adiposeKg != null && comp.structuredWeightKg != null) {
    final ffm = comp.structuredWeightKg! - comp.adiposeKg!;
    bmrCunn = bmrCunningham(ffm);
  }

  return AnthropometryResult(
    somatotype: soma,
    composition: comp,
    bsaM2: bsa,
    bmiValue: bmiVal,
    hwrValue: hwrVal,
    bmrHarrisBenedictKcal: bmrHB,
    waistHipRatioValue: whrValue,
    waistHipRiskLevel: whrRisk,
    bmrCunninghamKcal: bmrCunn,
  );
}
