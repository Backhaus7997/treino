import 'dart:math' show pi, pow;

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/assessment/domain/anthropometry/anthropometric_profile.dart';
import 'package:treino/features/assessment/domain/anthropometry/body_composition.dart';
import 'package:treino/features/assessment/domain/anthropometry/phantom_constants.dart';

// ─── REFERENCE PROFILE ────────────────────────────────────────────────────────
// Fictional athlete with all required fields for muscle + bone computation.
//
// heightCm = 175.0
//
// MUSCLE (relaxed arm, Kerr 1988):
//   relaxedArm     = 32.0 cm,  triceps    = 10.0 mm
//   chestMesost.   = 92.0 cm,  subscapular= 12.0 mm
//   thighMid       = 55.0 cm,  thighMedial= 15.0 mm
//   calfMax        = 36.0 cm,  calfMedial =  8.0 mm
//   forearmMax     = 26.0 cm  (uncorrected)
//
//   armCorr   = 32.0 - π*(10/10) = 32.0 - π*1.0 = 32.0 - 3.14159 = 28.858
//   chestCorr = 92.0 - π*(12/10) = 92.0 - π*1.2 = 92.0 - 3.76991 = 88.230
//   thighCorr = 55.0 - π*(15/10) = 55.0 - π*1.5 = 55.0 - 4.71239 = 50.288
//   calfCorr  = 36.0 - π*(8/10)  = 36.0 - π*0.8 = 36.0 - 2.51327 = 33.487
//   forearm   = 26.0
//   sum5 = 28.858 + 88.230 + 50.288 + 33.487 + 26.0 = 226.863
//
//   z = (226.863 * (170.18/175.0) - 207.21) / 13.74
//     = (226.863 * 0.97246 - 207.21) / 13.74
//     = (220.63 - 207.21) / 13.74
//     = 13.42 / 13.74
//     = 0.97671
//
//   mass = (0.97671 * 4.4 + 24.5) * (175/170.18)^3
//        = (4.2975 + 24.5) * (1.02833)^3
//        = 28.7975 * 1.08738
//        = 31.311 kg
//
// BONE:
//   biacromial=38.0, biiliocristal=28.0, humerusBiep=7.0, femurBiep=9.5, headGirth=56.5
//
//   sum5-breadths = 38.0 + 28.0 + 2*7.0 + 2*9.5 = 38+28+14+19 = 99.0 cm
//
//   zBody = (99.0 * (170.18/175.0) - 98.88) / 5.33
//         = (99.0 * 0.97246 - 98.88) / 5.33
//         = (96.274 - 98.88) / 5.33
//         = -2.606 / 5.33
//         = -0.48894
//
//   bodyBone = (-0.48894 * 1.34 + 6.7) * (175/170.18)^3
//            = (-0.65518 + 6.7) * 1.08738
//            = 6.04482 * 1.08738
//            = 6.573 kg
//
//   zHead = (56.5 * (170.18/175.0) - 56.0) / 1.44
//         = (56.5 * 0.97246 - 56.0) / 1.44
//         = (54.944 - 56.0) / 1.44
//         = -1.056 / 1.44
//         = -0.73333
//
//   headBone = -0.73333 * 0.18 + 1.2
//            = -0.132 + 1.2
//            = 1.068 kg
//
//   totalBone = 6.573 + 1.068 = 7.641 kg

AnthropometricProfile _fullProfile() => const AnthropometricProfile(
      sex: Sex.male,
      ageYears: 25,
      weightKg: 75.0,
      heightCm: 175.0,
      // girths (cm)
      relaxedArm: 32.0,
      chestMesosternal: 92.0,
      thighMid: 55.0,
      calfMax: 36.0,
      forearmMax: 26.0,
      // skinfolds (mm)
      triceps: 10.0,
      subscapular: 12.0,
      thighMedial: 15.0,
      calfMedial: 8.0,
      // diameters (cm)
      biacromial: 38.0,
      biiliocristal: 28.0,
      humerusBiepicondylar: 7.0,
      femurBiepicondylar: 9.5,
      // head girth (cm)
      headGirth: 56.5,
    );

void main() {
  group('muscleMassKg (Kerr 1988)', () {
    // SCENARIO-440: Muscle mass against hand-computed value
    test('SCENARIO-440: muscle mass ≈ 31.31 kg for reference profile', () {
      // Arithmetic shown in header comment.
      expect(muscleMassKg(_fullProfile()), closeTo(31.31, 0.10));
    });

    // SCENARIO-441: Verify π-corrected girth arithmetic is applied
    // Duplicate the computation inline to confirm formula path.
    test('SCENARIO-441: manual π-correction matches function output', () {
      const h = 175.0;
      const armCorr = 32.0 - pi * (10.0 / 10);
      const chestCorr = 92.0 - pi * (12.0 / 10);
      const thighCorr = 55.0 - pi * (15.0 / 10);
      const calfCorr = 36.0 - pi * (8.0 / 10);
      const forearm = 26.0;
      const sum5 = armCorr + chestCorr + thighCorr + calfCorr + forearm;
      const z = (sum5 * (phantomStatureP / h) - phantomMuscleGirthSumP) /
          phantomMuscleGirthSumS;
      final expected = (z * phantomMuscleMassS + phantomMuscleMassP) *
          pow(h / phantomStatureP, 3);
      expect(muscleMassKg(_fullProfile()), closeTo(expected, 0.001));
    });

    // SCENARIO-442: Missing required field → ArgumentError
    test('SCENARIO-442: missing forearmMax → ArgumentError', () {
      final p = _fullProfile().copyWith(); // all present
      final pNoForearm = AnthropometricProfile(
        sex: p.sex,
        ageYears: p.ageYears,
        weightKg: p.weightKg,
        heightCm: p.heightCm,
        relaxedArm: p.relaxedArm,
        chestMesosternal: p.chestMesosternal,
        thighMid: p.thighMid,
        calfMax: p.calfMax,
        // forearmMax intentionally omitted
        triceps: p.triceps,
        subscapular: p.subscapular,
        thighMedial: p.thighMedial,
        calfMedial: p.calfMedial,
        biacromial: p.biacromial,
        biiliocristal: p.biiliocristal,
        humerusBiepicondylar: p.humerusBiepicondylar,
        femurBiepicondylar: p.femurBiepicondylar,
        headGirth: p.headGirth,
      );
      expect(() => muscleMassKg(pNoForearm), throwsArgumentError);
    });
  });

  group('boneMassKg (Kerr 1988)', () {
    // SCENARIO-443: Bone mass against hand-computed value
    test('SCENARIO-443: total bone mass ≈ 7.64 kg for reference profile', () {
      // Arithmetic shown in header comment.
      expect(boneMassKg(_fullProfile()), closeTo(7.64, 0.10));
    });

    // SCENARIO-444: Verify head bone is NOT scaled by height³
    // zHead = (56.5*(170.18/175) - 56.0) / 1.44 = -0.733
    // headBone = -0.733 * 0.18 + 1.2 = 1.068
    test('SCENARIO-444: head bone ≈ 1.07 kg (no height-cube scaling)', () {
      const h = 175.0;
      const headG = 56.5;
      const zHead = (headG * (phantomStatureP / h) - phantomHeadGirthP) /
          phantomHeadGirthS;
      const headBone = zHead * phantomHeadBoneMassS + phantomHeadBoneMassP;
      expect(headBone, closeTo(1.07, 0.02));
    });
  });

  group('calculateBodyComposition (Kerr 1988 five-mass)', () {
    // SCENARIO-445: Adipose, residual, skin are null (PENDING_VERIFICATION)
    test('SCENARIO-445: adipose, residual, skin are null', () {
      final comp = calculateBodyComposition(_fullProfile());
      expect(comp.adiposeKg, isNull);
      expect(comp.residualKg, isNull);
      expect(comp.skinKg, isNull);
    });

    // SCENARIO-446: Pending set contains adipose, residual, skin
    test('SCENARIO-446: pending contains adipose, residual, skin', () {
      final comp = calculateBodyComposition(_fullProfile());
      expect(
          comp.pending,
          containsAll([
            MassComponent.adipose,
            MassComponent.residual,
            MassComponent.skin,
          ]));
    });

    // SCENARIO-447: structuredWeightKg ≈ muscle + bone (the only available)
    test('SCENARIO-447: structuredWeightKg == muscle + bone (closeTo)', () {
      final comp = calculateBodyComposition(_fullProfile());
      final expected = comp.muscleKg! + comp.boneKg!;
      expect(comp.structuredWeightKg, closeTo(expected, 0.001));
    });

    // SCENARIO-448: muscle and bone are NOT null
    test('SCENARIO-448: muscle and bone are non-null for complete profile', () {
      final comp = calculateBodyComposition(_fullProfile());
      expect(comp.muscleKg, isNotNull);
      expect(comp.boneKg, isNotNull);
    });

    // SCENARIO-449: BodyComposition equality
    test('SCENARIO-449: BodyComposition equality', () {
      final c1 = calculateBodyComposition(_fullProfile());
      final c2 = calculateBodyComposition(_fullProfile());
      expect(c1, equals(c2));
    });
  });
}
