import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine_slot.freezed.dart';
part 'routine_slot.g.dart';

@freezed
class RoutineSlot with _$RoutineSlot {
  const factory RoutineSlot({
    required String exerciseId, // FK → exercises/{id} (canonical reference)
    required String exerciseName, // denormalized for compact card display (ADR-2)
    required String muscleGroup, // denormalized for compact card display
    required int targetSets,
    required int targetRepsMin,
    required int targetRepsMax,
    required int restSeconds,
    double? targetWeightKg, // null means "user picks" or "no target" (plate math)
    String? notes, // nullable free-form coaching notes
  }) = _RoutineSlot;

  factory RoutineSlot.fromJson(Map<String, Object?> json) =>
      _$RoutineSlotFromJson(json);
}
