/// Whether an exercise is completed by reps+weight or by duration.
///
/// Serialized by enum name (json_serializable default). Unknown names on read
/// are handled via [JsonKey(unknownEnumValue: ...)] at the field level.
enum ExerciseMode {
  /// Reps-based: each set has a weight + rep count (or range).
  reps,

  /// Duration-based: each set has a time target (seconds). No reps tracked.
  duration,
}

/// Whether a reps-based set targets a single rep count or a min–max range.
///
/// Mirrors Hevy's "REPS" vs "REP RANGE" selector.
enum RepMode {
  /// Single rep target (e.g. "10").
  single,

  /// Min–max rep range (e.g. "8–12").
  range,
}

/// The type/role of an individual set row, mirroring Hevy's W / normal / D / F.
enum SetType {
  /// Warm-up set — lower load, not counted toward working volume.
  warmup,

  /// Standard working set.
  normal,

  /// Drop set — immediately follows a working set at reduced weight.
  drop,

  /// Failure set — taken to muscular failure.
  failure,
}

/// Short display label for a [SetType], used in set-row widgets.
///
/// `normal` intentionally has no letter — the UI renders the set number instead.
const Map<SetType, String> kSetTypeLabel = {
  SetType.warmup: 'W',
  SetType.normal: '',
  SetType.drop: 'D',
  SetType.failure: 'F',
};
