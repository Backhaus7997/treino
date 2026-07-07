// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise_frequency.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$ExerciseFrequencyEntry {
  String get exerciseId => throw _privateConstructorUsedError;
  String get exerciseName => throw _privateConstructorUsedError;
  int get sessionCount => throw _privateConstructorUsedError;

  /// Create a copy of ExerciseFrequencyEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ExerciseFrequencyEntryCopyWith<ExerciseFrequencyEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseFrequencyEntryCopyWith<$Res> {
  factory $ExerciseFrequencyEntryCopyWith(ExerciseFrequencyEntry value,
          $Res Function(ExerciseFrequencyEntry) then) =
      _$ExerciseFrequencyEntryCopyWithImpl<$Res, ExerciseFrequencyEntry>;
  @useResult
  $Res call({String exerciseId, String exerciseName, int sessionCount});
}

/// @nodoc
class _$ExerciseFrequencyEntryCopyWithImpl<$Res,
        $Val extends ExerciseFrequencyEntry>
    implements $ExerciseFrequencyEntryCopyWith<$Res> {
  _$ExerciseFrequencyEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ExerciseFrequencyEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? sessionCount = null,
  }) {
    return _then(_value.copyWith(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      sessionCount: null == sessionCount
          ? _value.sessionCount
          : sessionCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseFrequencyEntryImplCopyWith<$Res>
    implements $ExerciseFrequencyEntryCopyWith<$Res> {
  factory _$$ExerciseFrequencyEntryImplCopyWith(
          _$ExerciseFrequencyEntryImpl value,
          $Res Function(_$ExerciseFrequencyEntryImpl) then) =
      __$$ExerciseFrequencyEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String exerciseId, String exerciseName, int sessionCount});
}

/// @nodoc
class __$$ExerciseFrequencyEntryImplCopyWithImpl<$Res>
    extends _$ExerciseFrequencyEntryCopyWithImpl<$Res,
        _$ExerciseFrequencyEntryImpl>
    implements _$$ExerciseFrequencyEntryImplCopyWith<$Res> {
  __$$ExerciseFrequencyEntryImplCopyWithImpl(
      _$ExerciseFrequencyEntryImpl _value,
      $Res Function(_$ExerciseFrequencyEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of ExerciseFrequencyEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? sessionCount = null,
  }) {
    return _then(_$ExerciseFrequencyEntryImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      sessionCount: null == sessionCount
          ? _value.sessionCount
          : sessionCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

class _$ExerciseFrequencyEntryImpl implements _ExerciseFrequencyEntry {
  const _$ExerciseFrequencyEntryImpl(
      {required this.exerciseId,
      required this.exerciseName,
      required this.sessionCount});

  @override
  final String exerciseId;
  @override
  final String exerciseName;
  @override
  final int sessionCount;

  @override
  String toString() {
    return 'ExerciseFrequencyEntry(exerciseId: $exerciseId, exerciseName: $exerciseName, sessionCount: $sessionCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseFrequencyEntryImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            (identical(other.sessionCount, sessionCount) ||
                other.sessionCount == sessionCount));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, exerciseId, exerciseName, sessionCount);

  /// Create a copy of ExerciseFrequencyEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseFrequencyEntryImplCopyWith<_$ExerciseFrequencyEntryImpl>
      get copyWith => __$$ExerciseFrequencyEntryImplCopyWithImpl<
          _$ExerciseFrequencyEntryImpl>(this, _$identity);
}

abstract class _ExerciseFrequencyEntry implements ExerciseFrequencyEntry {
  const factory _ExerciseFrequencyEntry(
      {required final String exerciseId,
      required final String exerciseName,
      required final int sessionCount}) = _$ExerciseFrequencyEntryImpl;

  @override
  String get exerciseId;
  @override
  String get exerciseName;
  @override
  int get sessionCount;

  /// Create a copy of ExerciseFrequencyEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ExerciseFrequencyEntryImplCopyWith<_$ExerciseFrequencyEntryImpl>
      get copyWith => throw _privateConstructorUsedError;
}
