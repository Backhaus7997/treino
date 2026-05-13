import 'package:freezed_annotation/freezed_annotation.dart';

import 'routine_slot.dart';

part 'routine_day.freezed.dart';
part 'routine_day.g.dart';

@freezed
class RoutineDay with _$RoutineDay {
  const factory RoutineDay({
    required int dayNumber,
    required String name,
    required List<RoutineSlot> slots, // empty list is valid (spec SCENARIO-046)
    int? estimatedMinutes,
  }) = _RoutineDay;

  factory RoutineDay.fromJson(Map<String, Object?> json) =>
      _$RoutineDayFromJson(json);
}
