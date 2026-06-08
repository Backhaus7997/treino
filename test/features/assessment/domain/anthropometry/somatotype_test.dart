import 'dart:math' show pow;

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/assessment/domain/anthropometry/anthropometric_profile.dart';
import 'package:treino/features/assessment/domain/anthropometry/somatotype.dart';

// ─── SHARED FULL PROFILE ──────────────────────────────────────────────────────
// Fictional athlete used across most somatotype tests.
// Inputs chosen so manual arithmetic is clean.
//
// heightCm = 175.0, weightKg = 75.0
// Skinfolds: triceps=10, subscapular=12, supraspinale=8  (mm)
// Diameters: humerusBiepicondylar=7.0, femurBiepicondylar=9.5  (cm)
// Girths:    flexedArm=34.0, calfMax=36.0  (cm)
// Skinfolds: calfMedial=8  (mm)
//
// ENDOMORPHY arithmetic:
//   X = (10+12+8) * (170.18/175.0) = 30 * 0.97246 = 29.1737
//   endo = -0.7182 + 0.1451*29.1737 - 0.00068*29.1737^2 + 0.0000014*29.1737^3
//        = -0.7182 + 4.2311 - 0.5784 + 0.0348
//        = 2.9693  → ~2.97
//
// MESOMORPHY arithmetic:
//   correctedArm  = 34.0 - 10/10 = 33.0 cm
//   correctedCalf = 36.0 - 8/10  = 35.2 cm
//   meso = 0.858*7.0 + 0.601*9.5 + 0.188*33.0 + 0.161*35.2 - 0.131*175.0 + 4.5
//        = 6.006 + 5.7095 + 6.204 + 5.6672 - 22.925 + 4.5
//        = 5.1617  → ~5.16
//
// ECTOMORPHY arithmetic:
//   hwr = 175.0 / 75^(1/3) = 175.0 / 4.2172 = 41.498
//   hwr >= 40.75 → ecto = 0.732*41.498 - 28.58 = 30.377 - 28.58 = 1.797 → ~1.80
AnthropometricProfile _baseProfile() => const AnthropometricProfile(
      sex: Sex.male,
      ageYears: 25,
      weightKg: 75.0,
      heightCm: 175.0,
      // skinfolds
      triceps: 10.0,
      subscapular: 12.0,
      supraspinale: 8.0,
      calfMedial: 8.0,
      // diameters
      humerusBiepicondylar: 7.0,
      femurBiepicondylar: 9.5,
      // girths
      flexedArm: 34.0,
      calfMax: 36.0,
    );

void main() {
  group('calculateSomatotype', () {
    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-400: Full somatotype on base profile
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-400: base profile → expected endomorphy ≈ 2.97', () {
      final result = calculateSomatotype(_baseProfile());
      // Arithmetic shown in header comment above.
      expect(result.endomorphy, closeTo(2.97, 0.05));
    });

    test('SCENARIO-401: base profile → expected mesomorphy ≈ 5.16', () {
      final result = calculateSomatotype(_baseProfile());
      expect(result.mesomorphy, closeTo(5.16, 0.05));
    });

    // SCENARIO-402: Ectomorphy branch HWR >= 40.75
    // hwr = 175.0 / ∛75 = 41.498 → 0.732*41.498 - 28.58 = 1.797
    test('SCENARIO-402: ectomorphy branch HWR >= 40.75 (≈ 1.80)', () {
      final result = calculateSomatotype(_baseProfile());
      expect(result.ectomorphy, closeTo(1.80, 0.05));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-403: Ectomorphy branch 38.25 < HWR < 40.75
    // weightKg=85, heightCm=175
    // hwr = 175 / ∛85 = 175 / 4.3969 = 39.80
    // ecto = 0.463*39.80 - 17.63 = 18.427 - 17.63 = 0.797 → ~0.80
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-403: ectomorphy branch 38.25 < HWR < 40.75 (≈ 0.80)', () {
      final p = _baseProfile().copyWith(weightKg: 85.0);
      // hwr = 175 / pow(85, 1/3) = 175 / 4.3969 ≈ 39.80
      final hwrVal = 175.0 / pow(85.0, 1 / 3);
      expect(hwrVal, inInclusiveRange(38.25, 40.75));
      final result = calculateSomatotype(p);
      expect(result.ectomorphy, closeTo(0.80, 0.05));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-404: Ectomorphy branch HWR <= 38.25 → floor 0.1
    // weightKg=120, heightCm=175
    // hwr = 175 / ∛120 = 175 / 4.9324 = 35.48 → <= 38.25 → ecto = 0.1
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-404: ectomorphy branch HWR <= 38.25 → floor 0.1', () {
      final p = _baseProfile().copyWith(weightKg: 120.0);
      final hwrVal = 175.0 / pow(120.0, 1 / 3);
      expect(hwrVal, lessThanOrEqualTo(38.25));
      final result = calculateSomatotype(p);
      expect(result.ectomorphy, closeTo(0.1, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-405: Endomorphy floor at 0.1
    // Very lean athlete: tiny skinfolds → X small → polynomial yields < 0.1
    // triceps=1, subscapular=1, supraspinale=1 mm
    // X = 3 * (170.18/175) = 2.918
    // endo = -0.7182 + 0.1451*2.918 - 0.00068*2.918^2 + 0.0000014*2.918^3
    //      = -0.7182 + 0.4233 - 0.00579 + 0.0000347 ≈ -0.300 → floored to 0.1
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-405: endomorphy floored to 0.1 when polynomial < 0.1', () {
      final p = _baseProfile().copyWith(
        triceps: 1.0,
        subscapular: 1.0,
        supraspinale: 1.0,
      );
      final result = calculateSomatotype(p);
      expect(result.endomorphy, closeTo(0.1, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-406: Somatochart coordinates
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-406: somatochart x = ecto - endo, y = 2*meso - (endo+ecto)',
        () {
      final result = calculateSomatotype(_baseProfile());
      expect(result.x, closeTo(result.ectomorphy - result.endomorphy, 0.001));
      expect(
          result.y,
          closeTo(
              2 * result.mesomorphy - (result.endomorphy + result.ectomorphy),
              0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-407: Missing skinfold throws ArgumentError (endomorphy)
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-407: missing triceps skinfold → ArgumentError', () {
      const p = AnthropometricProfile(
        sex: Sex.male,
        ageYears: 25,
        weightKg: 75.0,
        heightCm: 175.0,
        subscapular: 12.0,
        supraspinale: 8.0,
        humerusBiepicondylar: 7.0,
        femurBiepicondylar: 9.5,
        flexedArm: 34.0,
        calfMax: 36.0,
        calfMedial: 8.0,
      );
      expect(() => calculateSomatotype(p), throwsArgumentError);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-408: Somatotype equality / copyWith
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-408: Somatotype equality and copyWith', () {
      const s1 = Somatotype(endomorphy: 3.0, mesomorphy: 5.0, ectomorphy: 2.0);
      const s2 = Somatotype(endomorphy: 3.0, mesomorphy: 5.0, ectomorphy: 2.0);
      expect(s1, equals(s2));
      final s3 = s1.copyWith(endomorphy: 4.0);
      expect(s3.endomorphy, 4.0);
      expect(s3.mesomorphy, 5.0);
    });
  });
}
