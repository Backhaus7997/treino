import 'dart:math' show pow;

import 'anthropometric_profile.dart';

/// Waist-hip risk classification (Holway proforma table).
/// Spanish labels match the proforma conventions.
enum WaistHipRisk {
  bajo,
  moderado,
  alto,
  muyAlto,
}

// ─── BODY SURFACE AREA ───────────────────────────────────────────────────────

/// Du Bois & Du Bois body surface area (m²).
///
/// BSA = 0.007184 × H^0.725 × W^0.425
///
/// [heightCm] in centimetres, [weightKg] in kilograms.
/// // VERIFIED Du Bois & Du Bois 1916
double bsaDuBois(double weightKg, double heightCm) {
  return 0.007184 * pow(heightCm, 0.725) * pow(weightKg, 0.425);
}

// ─── BMI ─────────────────────────────────────────────────────────────────────

/// Body Mass Index (kg/m²).
double bmi(double weightKg, double heightCm) {
  final heightM = heightCm / 100.0;
  return weightKg / (heightM * heightM);
}

// ─── HWR / PONDERAL INDEX ────────────────────────────────────────────────────

/// Height-weight ratio (ponderal index): height (cm) / ∛weight (kg).
///
/// This is the same value fed into the ectomorphy branch of Heath-Carter.
double hwr(double weightKg, double heightCm) {
  return heightCm / pow(weightKg, 1 / 3).toDouble();
}

// ─── WAIST-HIP RATIO ─────────────────────────────────────────────────────────

/// Raw waist-to-hip ratio.
double waistHipRatio(double waistMin, double hipMax) => waistMin / hipMax;

/// Waist-hip risk category from the Holway proforma table.
///
/// Age bands: 20-29, 30-39, 40-49, 50-59, 60-69.
/// Ages <20 are clamped to the 20-29 band; ages >69 to the 60-69 band.
///
/// Table source: Holway proforma (values transcribed exactly as specified).
WaistHipRisk waistHipRisk(Sex sex, int ageYears, double ratio) {
  // Age-band index 0..4 → 20-29, 30-39, 40-49, 50-59, 60-69.
  final band = ((ageYears - 20) ~/ 10).clamp(0, 4);

  // Thresholds: [bajo_max, moderado_max, alto_max] per age band.
  // Values above alto_max → muyAlto.
  //
  // MEN table (Holway proforma):
  //   20-29: <0.83 / .83-.88 / .89-.94 / >.94
  //   30-39: <0.84 / .84-.91 / .92-.96 / >.96
  //   40-49: <0.88 / .88-.95 / .96-1.00 / >1.00
  //   50-59: <0.90 / .90-.96 / .97-1.02 / >1.02
  //   60-69: <0.91 / .91-.98 / .99-1.03 / >1.03
  //
  // WOMEN table (Holway proforma):
  //   20-29: <0.71 / .71-.77 / .78-.82 / >.82
  //   30-39: <0.72 / .72-.78 / .79-.84 / >.84
  //   40-49: <0.73 / .73-.79 / .80-.87 / >.87
  //   50-59: <0.74 / .74-.81 / .82-.88 / >.88
  //   60-69: <0.76 / .76-.83 / .84-.90 / >.90

  final List<List<double>> thresholds;

  if (sex == Sex.male) {
    thresholds = [
      // band 0: 20-29
      [0.83, 0.88, 0.94],
      // band 1: 30-39
      [0.84, 0.91, 0.96],
      // band 2: 40-49
      [0.88, 0.95, 1.00],
      // band 3: 50-59
      [0.90, 0.96, 1.02],
      // band 4: 60-69
      [0.91, 0.98, 1.03],
    ];
  } else {
    thresholds = [
      // band 0: 20-29
      [0.71, 0.77, 0.82],
      // band 1: 30-39
      [0.72, 0.78, 0.84],
      // band 2: 40-49
      [0.73, 0.79, 0.87],
      // band 3: 50-59
      [0.74, 0.81, 0.88],
      // band 4: 60-69
      [0.76, 0.83, 0.90],
    ];
  }

  final t = thresholds[band];
  if (ratio < t[0]) return WaistHipRisk.bajo;
  if (ratio <= t[1]) return WaistHipRisk.moderado;
  if (ratio <= t[2]) return WaistHipRisk.alto;
  return WaistHipRisk.muyAlto;
}

// ─── BASAL METABOLIC RATE ────────────────────────────────────────────────────

/// Harris-Benedict BMR (kcal/day).
///
/// Male:   66.4730 + 13.7516×W + 5.0033×H − 6.7550×age
/// Female: 655.0955 + 9.5634×W + 1.8496×H − 4.6756×age
///
/// [weightKg] kg, [heightCm] cm, [ageYears] integer years.
/// // VERIFIED Harris & Benedict 1919 original
double bmrHarrisBenedict(
    Sex sex, double weightKg, double heightCm, int ageYears) {
  if (sex == Sex.male) {
    return 66.4730 + 13.7516 * weightKg + 5.0033 * heightCm - 6.7550 * ageYears;
  } else {
    return 655.0955 + 9.5634 * weightKg + 1.8496 * heightCm - 4.6756 * ageYears;
  }
}

/// Cunningham BMR (kcal/day) from fat-free mass.
///
/// BMR = 370 + 21.6 × FFM (kg)
///
/// // VERIFIED Cunningham 1991
double bmrCunningham(double fatFreeMassKg) => 370 + 21.6 * fatFreeMassKg;
