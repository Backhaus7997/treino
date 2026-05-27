import 'package:freezed_annotation/freezed_annotation.dart';

part 'exercise.freezed.dart';
part 'exercise.g.dart';

@freezed
class Exercise with _$Exercise {
  const factory Exercise({
    required String id,
    required String name,
    required String muscleGroup,
    required String
        category, // 'compound' | 'isolation' (free-form String, validated in seed)
    List<String>?
        techniqueInstructions, // null means "not yet authored" (ADR-1)
    String? videoUrl,
    int? defaultRestSeconds,
    @Default(<String>[]) List<String>
        aliases, // Spanish/jargon synonyms for the Excel importer match
  }) = _Exercise;

  factory Exercise.fromJson(Map<String, Object?> json) =>
      _$ExerciseFromJson(json);
}
