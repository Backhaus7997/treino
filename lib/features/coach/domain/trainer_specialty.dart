import 'package:json_annotation/json_annotation.dart';

/// 10 predefined trainer specialties per REQ-COACH-DISC-DATA-003.
///
/// Mirrors the `SessionStatus` enum pattern (json_annotation + extension
/// with `_wireMap`). `fromString` returns null for unknown/legacy strings
/// per design D13. Case-insensitive matching per SCENARIO-410.
enum TrainerSpecialty {
  @JsonValue('powerlifting')
  powerlifting,
  @JsonValue('crossfit')
  crossfit,
  @JsonValue('bodybuilding')
  bodybuilding,
  @JsonValue('hipertrofia')
  hipertrofia,
  @JsonValue('wellness')
  wellness,
  @JsonValue('kinesiologia')
  kinesiologia,
  @JsonValue('funcional')
  funcional,
  @JsonValue('running')
  running,
  @JsonValue('yoga')
  yoga,
  @JsonValue('calistenia')
  calistenia,
}

extension TrainerSpecialtyX on TrainerSpecialty {
  static const _wireMap = {
    'powerlifting': TrainerSpecialty.powerlifting,
    'crossfit': TrainerSpecialty.crossfit,
    'bodybuilding': TrainerSpecialty.bodybuilding,
    'hipertrofia': TrainerSpecialty.hipertrofia,
    'wellness': TrainerSpecialty.wellness,
    'kinesiologia': TrainerSpecialty.kinesiologia,
    'funcional': TrainerSpecialty.funcional,
    'running': TrainerSpecialty.running,
    'yoga': TrainerSpecialty.yoga,
    'calistenia': TrainerSpecialty.calistenia,
  };

  /// Returns the wire (Firestore) string for this specialty.
  static String toWire(TrainerSpecialty s) => switch (s) {
        TrainerSpecialty.powerlifting => 'powerlifting',
        TrainerSpecialty.crossfit => 'crossfit',
        TrainerSpecialty.bodybuilding => 'bodybuilding',
        TrainerSpecialty.hipertrofia => 'hipertrofia',
        TrainerSpecialty.wellness => 'wellness',
        TrainerSpecialty.kinesiologia => 'kinesiologia',
        TrainerSpecialty.funcional => 'funcional',
        TrainerSpecialty.running => 'running',
        TrainerSpecialty.yoga => 'yoga',
        TrainerSpecialty.calistenia => 'calistenia',
      };

  String toWireValue() => toWire(this);
}

/// Parses a wire string (case-insensitive) into a [TrainerSpecialty].
///
/// Returns `null` for unknown/legacy strings — per D13, no sentinel value.
/// Per SCENARIO-410: "Hipertrofia" → `TrainerSpecialty.hipertrofia`.
TrainerSpecialty? trainerSpecialtyFromString(String? value) {
  if (value == null || value.isEmpty) return null;
  return TrainerSpecialtyX._wireMap[value.trim().toLowerCase()];
}
