import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine_tag.freezed.dart';
part 'routine_tag.g.dart';

@freezed
class RoutineTag with _$RoutineTag {
  const factory RoutineTag({
    required String routineId,
    required String routineName,
  }) = _RoutineTag;

  factory RoutineTag.fromJson(Map<String, Object?> json) =>
      _$RoutineTagFromJson(json);
}
