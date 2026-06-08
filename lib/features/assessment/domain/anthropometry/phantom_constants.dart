/// Phantom stratagem constants for the Kerr 1988 five-mass fractionation model.
///
/// Every constant is grouped by mass component and annotated with its
/// verification status. This is the SINGLE file to update after validating
/// against the real Holway proforma / Excel formulas.
///
/// VERIFICATION TIERS (read before trusting any value):
///   • CANONICAL  — settled, universally-agreed published equation/constant
///     (Phantom stature/mass, Du Bois, Harris-Benedict, Heath-Carter). Trust.
///   • LITERATURE — from a SINGLE secondary source (PMC11164060) that
///     reproduces Kerr 1988; NOT yet cross-checked against the primary thesis
///     OR the trainer's real proforma. Structurally right, numerically must be
///     re-confirmed against a filled proforma before clinical trust.
///   • PENDING_VERIFICATION — unknown; left null. Fill from real proforma /
///     extracted Excel formulas.
///
/// Sources:
///   Ross & Wilson 1974 — original Phantom publication
///   PMC11164060 — Kerr (1988) five-mass model values (Muscle + Bone)
///   Holway proforma — visible constants in the Excel sheet
library phantom_constants;

// ─── PHANTOM STATURE ─────────────────────────────────────────────────────────

/// Phantom stature mean (cm). // VERIFIED Ross & Wilson 1974
const double phantomStatureP = 170.18;

/// Phantom stature standard deviation (cm). // VERIFIED Ross & Wilson 1974
const double phantomStatureS = 6.29;

// ─── PHANTOM BODY MASS ───────────────────────────────────────────────────────

/// Phantom body mass mean (kg). // VERIFIED Ross & Wilson 1974
const double phantomBodyMassP = 64.58;

/// Phantom body mass standard deviation (kg). // VERIFIED Ross & Wilson 1974
const double phantomBodyMassS = 8.60;

// ─── MUSCLE MASS (Kerr 1988) ─────────────────────────────────────────────────
// Input: sum of 5 π-corrected girths (relaxed arm, chest, mid-thigh, calf, forearm).

/// Sum-5-corrected-girths Phantom mean (cm). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomMuscleGirthSumP = 207.21;

/// Sum-5-corrected-girths Phantom standard deviation (cm). // VERIFIED PMC11164060
const double phantomMuscleGirthSumS = 13.74;

/// Muscle mass Phantom mean (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomMuscleMassP = 24.5;

/// Muscle mass Phantom standard deviation (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomMuscleMassS = 4.4;

// ─── BONE MASS — BODY (Kerr 1988) ────────────────────────────────────────────
// Input: sum of 5 breadths (biacromial + biiliocristal + 2×humerus + 2×femur).

/// Sum-5-breadths Phantom mean (cm). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomBoneBreadthSumP = 98.88;

/// Sum-5-breadths Phantom standard deviation (cm). // VERIFIED PMC11164060
const double phantomBoneBreadthSumS = 5.33;

/// Body bone mass Phantom mean (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomBodyBoneMassP = 6.7;

/// Body bone mass Phantom standard deviation (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomBodyBoneMassS = 1.34;

// ─── BONE MASS — HEAD (Kerr 1988) ────────────────────────────────────────────
// Head bone is NOT scaled by height^3 (head size is independent of stature).

/// Head girth Phantom mean (cm). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomHeadGirthP = 56.0;

/// Head girth Phantom standard deviation (cm). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomHeadGirthS = 1.44;

/// Head bone mass Phantom mean (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomHeadBoneMassP = 1.2;

/// Head bone mass Phantom standard deviation (kg). // VERIFIED PMC11164060 (Kerr 1988)
const double phantomHeadBoneMassS = 0.18;

// ─── ADIPOSE MASS (Kerr 1988) ────────────────────────────────────────────────
// Input: sum of 6 skinfolds (triceps, subscapular, supraspinale, abdominal,
//        medial thigh, medial calf). Constants NOT confirmed from open-access source.

/// Sum-6-skinfolds Phantom mean (mm). // PENDING_VERIFICATION (Kerr thesis not in open access)
const double? phantomAdiposeSumP = null;

/// Sum-6-skinfolds Phantom standard deviation (mm). // PENDING_VERIFICATION
const double? phantomAdiposeSumS = null;

/// Adipose mass Phantom mean (kg). // PENDING_VERIFICATION
const double? phantomAdiposeMassP = null;

/// Adipose mass Phantom standard deviation (kg). // PENDING_VERIFICATION
const double? phantomAdiposeMassS = null;

// ─── RESIDUAL MASS (Kerr 1988) ───────────────────────────────────────────────

/// Residual mass Phantom input sum mean. // PENDING_VERIFICATION
const double? phantomResidualInputP = null;

/// Residual mass Phantom input sum standard deviation. // PENDING_VERIFICATION
const double? phantomResidualInputS = null;

/// Residual mass Phantom mean (kg). // PENDING_VERIFICATION
const double? phantomResidualMassP = null;

/// Residual mass Phantom standard deviation (kg). // PENDING_VERIFICATION
const double? phantomResidualMassS = null;

// ─── SKIN MASS (Kerr 1988) ───────────────────────────────────────────────────

/// Skin thickness for males (mm). // PENDING_VERIFICATION
/// Visible in Holway proforma; derivation/source unconfirmed.
const double skinThicknessMaleMm = 2.07;

/// Skin thickness for females (mm). // PENDING_VERIFICATION
/// Visible in Holway proforma; derivation/source unconfirmed.
const double skinThicknessFemaleMm = 1.96;

/// Surface-area constant for males aged >12. // PENDING_VERIFICATION
/// Visible in Holway proforma; meaning/derivation unconfirmed.
const double bsaSurfaceConstantMaleAdult = 68.308;

/// Surface-area constant for females aged >12. // PENDING_VERIFICATION
/// Visible in Holway proforma; meaning/derivation unconfirmed.
const double bsaSurfaceConstantFemaleAdult = 73.074;

/// Surface-area constant for children aged ≤12 (sex-neutral). // PENDING_VERIFICATION
/// Visible in Holway proforma; meaning/derivation unconfirmed.
const double bsaSurfaceConstantChild = 70.691;

/// Skin mass Phantom mean (kg). // PENDING_VERIFICATION
const double? phantomSkinMassP = null;

/// Skin mass Phantom standard deviation (kg). // PENDING_VERIFICATION
const double? phantomSkinMassS = null;
