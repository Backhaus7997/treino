import 'package:flutter/foundation.dart';

/// Biological sex, used for sex-specific formulas throughout the proforma.
enum Sex { male, female }

/// Raw ISAK input data collected from a single anthropometric assessment session.
///
/// All weight/height/sex/age fields are required.
/// All remaining measurements are optional so partial profiles don't crash
/// mid-computation — callers guard against null before using derived functions.
///
/// Units:
///   Girths and diameters → centimetres (cm)
///   Skinfolds            → millimetres (mm)
///   Mass                 → kilograms   (kg)
@immutable
class AnthropometricProfile {
  const AnthropometricProfile({
    required this.sex,
    required this.ageYears,
    required this.weightKg,
    required this.heightCm,
    this.measuredAt,
    // Basics
    this.sittingHeightCm,
    // Diameters (cm)
    this.biacromial,
    this.transverseChest,
    this.apChest,
    this.biiliocristal,
    this.humerusBiepicondylar,
    this.femurBiepicondylar,
    // Girths (cm)
    this.headGirth,
    this.relaxedArm,
    this.flexedArm,
    this.forearmMax,
    this.chestMesosternal,
    this.waistMin,
    this.hipMax,
    this.thighMax,
    this.thighMid,
    this.calfMax,
    this.neck,
    // Skinfolds (mm)
    this.triceps,
    this.subscapular,
    this.supraspinale,
    this.abdominal,
    this.thighMedial,
    this.calfMedial,
  });

  final Sex sex;
  final int ageYears;
  final double weightKg;
  final double heightCm;
  final DateTime? measuredAt;

  // ─── Basics ──────────────────────────────────────────────────────────────
  final double? sittingHeightCm;

  // ─── Diameters (cm) ──────────────────────────────────────────────────────
  final double? biacromial;
  final double? transverseChest;
  final double? apChest; // antero-posterior chest depth
  final double? biiliocristal;
  final double? humerusBiepicondylar;
  final double? femurBiepicondylar;

  // ─── Girths (cm) ─────────────────────────────────────────────────────────
  final double? headGirth;
  final double? relaxedArm;
  final double? flexedArm;
  final double? forearmMax;
  final double? chestMesosternal;
  final double? waistMin;
  final double? hipMax;
  final double? thighMax;
  final double? thighMid; // medial thigh girth
  final double? calfMax;
  final double? neck;

  // ─── Skinfolds (mm) ──────────────────────────────────────────────────────
  final double? triceps;
  final double? subscapular;
  final double? supraspinale;
  final double? abdominal;
  final double? thighMedial;
  final double? calfMedial;

  AnthropometricProfile copyWith({
    Sex? sex,
    int? ageYears,
    double? weightKg,
    double? heightCm,
    DateTime? measuredAt,
    double? sittingHeightCm,
    double? biacromial,
    double? transverseChest,
    double? apChest,
    double? biiliocristal,
    double? humerusBiepicondylar,
    double? femurBiepicondylar,
    double? headGirth,
    double? relaxedArm,
    double? flexedArm,
    double? forearmMax,
    double? chestMesosternal,
    double? waistMin,
    double? hipMax,
    double? thighMax,
    double? thighMid,
    double? calfMax,
    double? neck,
    double? triceps,
    double? subscapular,
    double? supraspinale,
    double? abdominal,
    double? thighMedial,
    double? calfMedial,
  }) {
    return AnthropometricProfile(
      sex: sex ?? this.sex,
      ageYears: ageYears ?? this.ageYears,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      measuredAt: measuredAt ?? this.measuredAt,
      sittingHeightCm: sittingHeightCm ?? this.sittingHeightCm,
      biacromial: biacromial ?? this.biacromial,
      transverseChest: transverseChest ?? this.transverseChest,
      apChest: apChest ?? this.apChest,
      biiliocristal: biiliocristal ?? this.biiliocristal,
      humerusBiepicondylar: humerusBiepicondylar ?? this.humerusBiepicondylar,
      femurBiepicondylar: femurBiepicondylar ?? this.femurBiepicondylar,
      headGirth: headGirth ?? this.headGirth,
      relaxedArm: relaxedArm ?? this.relaxedArm,
      flexedArm: flexedArm ?? this.flexedArm,
      forearmMax: forearmMax ?? this.forearmMax,
      chestMesosternal: chestMesosternal ?? this.chestMesosternal,
      waistMin: waistMin ?? this.waistMin,
      hipMax: hipMax ?? this.hipMax,
      thighMax: thighMax ?? this.thighMax,
      thighMid: thighMid ?? this.thighMid,
      calfMax: calfMax ?? this.calfMax,
      neck: neck ?? this.neck,
      triceps: triceps ?? this.triceps,
      subscapular: subscapular ?? this.subscapular,
      supraspinale: supraspinale ?? this.supraspinale,
      abdominal: abdominal ?? this.abdominal,
      thighMedial: thighMedial ?? this.thighMedial,
      calfMedial: calfMedial ?? this.calfMedial,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnthropometricProfile &&
        other.sex == sex &&
        other.ageYears == ageYears &&
        other.weightKg == weightKg &&
        other.heightCm == heightCm &&
        other.measuredAt == measuredAt &&
        other.sittingHeightCm == sittingHeightCm &&
        other.biacromial == biacromial &&
        other.transverseChest == transverseChest &&
        other.apChest == apChest &&
        other.biiliocristal == biiliocristal &&
        other.humerusBiepicondylar == humerusBiepicondylar &&
        other.femurBiepicondylar == femurBiepicondylar &&
        other.headGirth == headGirth &&
        other.relaxedArm == relaxedArm &&
        other.flexedArm == flexedArm &&
        other.forearmMax == forearmMax &&
        other.chestMesosternal == chestMesosternal &&
        other.waistMin == waistMin &&
        other.hipMax == hipMax &&
        other.thighMax == thighMax &&
        other.thighMid == thighMid &&
        other.calfMax == calfMax &&
        other.neck == neck &&
        other.triceps == triceps &&
        other.subscapular == subscapular &&
        other.supraspinale == supraspinale &&
        other.abdominal == abdominal &&
        other.thighMedial == thighMedial &&
        other.calfMedial == calfMedial;
  }

  @override
  int get hashCode => Object.hashAll([
        sex,
        ageYears,
        weightKg,
        heightCm,
        measuredAt,
        sittingHeightCm,
        biacromial,
        transverseChest,
        apChest,
        biiliocristal,
        humerusBiepicondylar,
        femurBiepicondylar,
        headGirth,
        relaxedArm,
        flexedArm,
        forearmMax,
        chestMesosternal,
        waistMin,
        hipMax,
        thighMax,
        thighMid,
        calfMax,
        neck,
        triceps,
        subscapular,
        supraspinale,
        abdominal,
        thighMedial,
        calfMedial,
      ]);
}
