import 'dart:math' show pi, pow;

import 'package:flutter/foundation.dart';

import 'anthropometric_profile.dart';
import 'phantom_constants.dart';

/// The five mass components of the Kerr 1988 fractionation model.
enum MassComponent { adipose, muscle, residual, bone, skin }

/// Result of the five-mass body composition fractionation (Kerr 1988).
///
/// Components that could not be computed (due to missing input data or
/// PENDING_VERIFICATION constants) are null and listed in [pending].
/// [structuredWeightKg] is the sum of all non-null components.
@immutable
class BodyComposition {
  const BodyComposition({
    this.adiposeKg,
    this.muscleKg,
    this.residualKg,
    this.boneKg,
    this.skinKg,
    this.structuredWeightKg,
    required this.pending,
  });

  final double? adiposeKg;
  final double? muscleKg;
  final double? residualKg;
  final double? boneKg;
  final double? skinKg;

  /// Sum of all non-null mass components (kg).
  final double? structuredWeightKg;

  /// Components that could not be computed.
  final Set<MassComponent> pending;

  BodyComposition copyWith({
    double? adiposeKg,
    double? muscleKg,
    double? residualKg,
    double? boneKg,
    double? skinKg,
    double? structuredWeightKg,
    Set<MassComponent>? pending,
  }) {
    return BodyComposition(
      adiposeKg: adiposeKg ?? this.adiposeKg,
      muscleKg: muscleKg ?? this.muscleKg,
      residualKg: residualKg ?? this.residualKg,
      boneKg: boneKg ?? this.boneKg,
      skinKg: skinKg ?? this.skinKg,
      structuredWeightKg: structuredWeightKg ?? this.structuredWeightKg,
      pending: pending ?? this.pending,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BodyComposition &&
        other.adiposeKg == adiposeKg &&
        other.muscleKg == muscleKg &&
        other.residualKg == residualKg &&
        other.boneKg == boneKg &&
        other.skinKg == skinKg &&
        other.structuredWeightKg == structuredWeightKg &&
        other.pending.length == pending.length &&
        other.pending.containsAll(pending);
  }

  @override
  int get hashCode => Object.hash(
        adiposeKg,
        muscleKg,
        residualKg,
        boneKg,
        skinKg,
        structuredWeightKg,
        Object.hashAll(pending),
      );
}

// ─── PHANTOM Z-SCORE HELPERS ─────────────────────────────────────────────────

/// Phantom z-score for a sum [S] of linear variables, height-corrected.
///
/// z = (S × (170.18 / H) − P) / s
double _phantomZ(
    double sum, double heightCm, double phantomP, double phantomS) {
  return (sum * (phantomStatureP / heightCm) - phantomP) / phantomS;
}

/// Back-calculates mass from z-score, scaled by height³ (isometric assumption).
///
/// mass = (z × s_mass + P_mass) × (H / 170.18)³
double _massFromZ(
    double z, double heightCm, double phantomMassP, double phantomMassS) {
  return (z * phantomMassS + phantomMassP) *
      pow(heightCm / phantomStatureP, 3).toDouble();
}

// ─── MUSCLE MASS ─────────────────────────────────────────────────────────────

/// Kerr 1988 muscle mass fractionation.
///
/// Uses RELAXED arm girth (not flexed — somatotype uses flexed arm; keep separate).
///
/// Corrected girths (π × skinfold(mm)/10 cm subtracted from each girth):
///   arm   = relaxedArm − π × (triceps/10)
///   chest = chestMesosternal − π × (subscapular/10)
///   thigh = thighMid − π × (thighMedial/10)
///   calf  = calfMax − π × (calfMedial/10)
///   forearm = forearmMax (uncorrected)
///
/// Sum of these 5 → Phantom z-score → muscle mass scaled by height³.
/// // VERIFIED PMC11164060 (Kerr 1988)
double muscleMassKg(AnthropometricProfile p) {
  final relArm = p.relaxedArm;
  final tri = p.triceps;
  final chest = p.chestMesosternal;
  final sub = p.subscapular;
  final thigh = p.thighMid;
  final thighSk = p.thighMedial;
  final calf = p.calfMax;
  final calfSk = p.calfMedial;
  final forearm = p.forearmMax;

  if (relArm == null ||
      tri == null ||
      chest == null ||
      sub == null ||
      thigh == null ||
      thighSk == null ||
      calf == null ||
      calfSk == null ||
      forearm == null) {
    throw ArgumentError(
      'muscleMassKg: relaxedArm, triceps, chestMesosternal, subscapular, '
      'thighMid, thighMedial, calfMax, calfMedial, and forearmMax are required.',
    );
  }

  final armCorr = relArm - pi * (tri / 10);
  final chestCorr = chest - pi * (sub / 10);
  final thighCorr = thigh - pi * (thighSk / 10);
  final calfCorr = calf - pi * (calfSk / 10);

  final sum5 = armCorr + chestCorr + thighCorr + calfCorr + forearm;

  final z = _phantomZ(
      sum5, p.heightCm, phantomMuscleGirthSumP, phantomMuscleGirthSumS);
  return _massFromZ(z, p.heightCm, phantomMuscleMassP, phantomMuscleMassS);
}

// ─── BONE MASS ───────────────────────────────────────────────────────────────

/// Kerr 1988 bone mass fractionation.
///
/// Body bone: sum-5-breadths = biacromial + biiliocristal + 2×humerus + 2×femur
///   → Phantom z-score → body bone mass scaled by height³.
/// Head bone: z = (headGirth × (170.18/H) − 56.0) / 1.44
///   → mass = z × 0.18 + 1.2  (NOT scaled by height³)
/// Total = body bone + head bone.
/// // VERIFIED PMC11164060 (Kerr 1988)
double boneMassKg(AnthropometricProfile p) {
  final biacr = p.biacromial;
  final biili = p.biiliocristal;
  final humBiep = p.humerusBiepicondylar;
  final femBiep = p.femurBiepicondylar;
  final headG = p.headGirth;

  if (biacr == null ||
      biili == null ||
      humBiep == null ||
      femBiep == null ||
      headG == null) {
    throw ArgumentError(
      'boneMassKg: biacromial, biiliocristal, humerusBiepicondylar, '
      'femurBiepicondylar, and headGirth are required.',
    );
  }

  // Body bone: sum of 5 skeletal breadths.
  final sum5 = biacr + biili + 2 * humBiep + 2 * femBiep;
  final zBody = _phantomZ(
      sum5, p.heightCm, phantomBoneBreadthSumP, phantomBoneBreadthSumS);
  final bodyBone =
      _massFromZ(zBody, p.heightCm, phantomBodyBoneMassP, phantomBodyBoneMassS);

  // Head bone: NOT scaled by height³ (head size is independent of stature).
  final zHead = (headG * (phantomStatureP / p.heightCm) - phantomHeadGirthP) /
      phantomHeadGirthS;
  final headBone = zHead * phantomHeadBoneMassS + phantomHeadBoneMassP;

  return bodyBone + headBone;
}

// ─── ADIPOSE MASS ────────────────────────────────────────────────────────────

/// Kerr 1988 adipose mass fractionation.
///
/// Formula structure (constants PENDING_VERIFICATION):
///   sum6 = triceps + subscapular + supraspinale + abdominal
///          + thighMedial + calfMedial  (all in mm)
///   z = (sum6 × (170.18/H) − phantomAdiposeSumP) / phantomAdiposeSumS
///   mass = (z × phantomAdiposeMassS + phantomAdiposeMassP) × (H/170.18)³
///
/// Returns null because [phantomAdiposeSumP], [phantomAdiposeSumS],
/// [phantomAdiposeMassP], [phantomAdiposeMassS] are all PENDING_VERIFICATION.
// ignore: unused_element
double? adiposeMassKg(AnthropometricProfile p) {
  // TODO: fill in once phantom constants are confirmed from real proforma.
  // if (phantomAdiposeSumP == null || ...) return null;
  //
  // final sum6 = (p.triceps ?? 0) + (p.subscapular ?? 0)
  //            + (p.supraspinale ?? 0) + (p.abdominal ?? 0)
  //            + (p.thighMedial ?? 0) + (p.calfMedial ?? 0);
  // final z = _phantomZ(sum6, p.heightCm, phantomAdiposeSumP!, phantomAdiposeSumS!);
  // return _massFromZ(z, p.heightCm, phantomAdiposeMassP!, phantomAdiposeMassS!);
  return null;
}

// ─── RESIDUAL MASS ───────────────────────────────────────────────────────────

/// Kerr 1988 residual mass fractionation.
///
/// Returns null because Phantom constants for residual are PENDING_VERIFICATION.
/// Formula structure mirrors the general Phantom back-calculation pattern.
// ignore: unused_element
double? residualMassKg(AnthropometricProfile p) {
  // TODO: fill in once phantom constants are confirmed from real proforma.
  return null;
}

// ─── SKIN MASS ───────────────────────────────────────────────────────────────

/// Kerr 1988 skin mass fractionation.
///
/// Returns null because Phantom constants for skin mass are PENDING_VERIFICATION.
/// Formula structure (when constants become available):
///   surface_area = bsaDuBois(weightKg, heightCm)  [m²]
///   skin_thickness = sex-specific constant (mm → m)
///   skin_density   ≈ 1.1 g/cm³  [PENDING: confirm from Kerr]
///   skinKg         = surface_area × thickness × density × 1000
// ignore: unused_element
double? skinMassKg(AnthropometricProfile p) {
  // TODO: fill in once phantom constants and density confirmed from real proforma.
  return null;
}

// ─── MAIN FRACTIONATION ──────────────────────────────────────────────────────

/// Assembles the five-mass body composition from an [AnthropometricProfile].
///
/// Components that cannot be computed (null constants or missing inputs)
/// are listed in [BodyComposition.pending].
BodyComposition calculateBodyComposition(AnthropometricProfile p) {
  double? muscleKg;
  double? boneKg;

  final pendingSet = <MassComponent>{};

  // ── Muscle ──
  try {
    muscleKg = muscleMassKg(p);
  } on ArgumentError {
    pendingSet.add(MassComponent.muscle);
  }

  // ── Bone ──
  try {
    boneKg = boneMassKg(p);
  } on ArgumentError {
    pendingSet.add(MassComponent.bone);
  }

  // ── Adipose (constants PENDING) ──
  const double? adiposeKg = null;
  pendingSet.add(MassComponent.adipose);

  // ── Residual (constants PENDING) ──
  const double? residualKg = null;
  pendingSet.add(MassComponent.residual);

  // ── Skin (constants PENDING) ──
  const double? skinKg = null;
  pendingSet.add(MassComponent.skin);

  // ── Structured weight: sum of available components ──
  double? structuredWeightKg;
  final available = [muscleKg, boneKg, adiposeKg, residualKg, skinKg]
      .whereType<double>()
      .toList();

  if (available.isNotEmpty) {
    structuredWeightKg =
        available.fold<double>(0.0, (double a, double b) => a + b);
  }

  return BodyComposition(
    adiposeKg: adiposeKg,
    muscleKg: muscleKg,
    residualKg: residualKg,
    boneKg: boneKg,
    skinKg: skinKg,
    structuredWeightKg: structuredWeightKg,
    pending: pendingSet,
  );
}
