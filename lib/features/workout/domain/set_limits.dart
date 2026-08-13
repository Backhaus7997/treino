/// Domain limits for a single logged/planned set.
///
/// Shared by the routine editor (input caps + `isSetValid`) and the session
/// player (prefill clamp + input caps) so a set can never carry a physically
/// impossible rep count or load. Without a shared ceiling a value like
/// 999999 reps × 99999 kg flows from the editor into a `SetLog` and corrupts
/// `totalVolumeKg`, the public counters and the server-side ranking recompute
/// (`lifetimeVolumeKg`). QA-WKT-003 / QA-WKT-002.
library;

/// Max reps for a single set. 999 matches the player's 3-digit reps field.
const int kMaxReps = 999;

/// Max load in kg for a single set.
const double kMaxWeightKg = 500.0;

/// Clamps a rep count into `[0, kMaxReps]`. Used on prefill to neutralize
/// already-corrupt Firestore docs written before the caps existed.
int clampReps(int reps) => reps.clamp(0, kMaxReps);

/// Clamps a load into `[0, kMaxWeightKg]`.
double clampWeightKg(double kg) => kg.clamp(0.0, kMaxWeightKg).toDouble();
