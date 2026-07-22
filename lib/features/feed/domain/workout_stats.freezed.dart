// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workout_stats.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WorkoutStats _$WorkoutStatsFromJson(Map<String, dynamic> json) {
  return _WorkoutStats.fromJson(json);
}

/// @nodoc
mixin _$WorkoutStats {
  double get volumeKg => throw _privateConstructorUsedError;
  int get durationMin => throw _privateConstructorUsedError;
  int get exerciseCount => throw _privateConstructorUsedError;

  /// Serializes this WorkoutStats to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of WorkoutStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WorkoutStatsCopyWith<WorkoutStats> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WorkoutStatsCopyWith<$Res> {
  factory $WorkoutStatsCopyWith(
          WorkoutStats value, $Res Function(WorkoutStats) then) =
      _$WorkoutStatsCopyWithImpl<$Res, WorkoutStats>;
  @useResult
  $Res call({double volumeKg, int durationMin, int exerciseCount});
}

/// @nodoc
class _$WorkoutStatsCopyWithImpl<$Res, $Val extends WorkoutStats>
    implements $WorkoutStatsCopyWith<$Res> {
  _$WorkoutStatsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WorkoutStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? volumeKg = null,
    Object? durationMin = null,
    Object? exerciseCount = null,
  }) {
    return _then(_value.copyWith(
      volumeKg: null == volumeKg
          ? _value.volumeKg
          : volumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      exerciseCount: null == exerciseCount
          ? _value.exerciseCount
          : exerciseCount // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WorkoutStatsImplCopyWith<$Res>
    implements $WorkoutStatsCopyWith<$Res> {
  factory _$$WorkoutStatsImplCopyWith(
          _$WorkoutStatsImpl value, $Res Function(_$WorkoutStatsImpl) then) =
      __$$WorkoutStatsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double volumeKg, int durationMin, int exerciseCount});
}

/// @nodoc
class __$$WorkoutStatsImplCopyWithImpl<$Res>
    extends _$WorkoutStatsCopyWithImpl<$Res, _$WorkoutStatsImpl>
    implements _$$WorkoutStatsImplCopyWith<$Res> {
  __$$WorkoutStatsImplCopyWithImpl(
      _$WorkoutStatsImpl _value, $Res Function(_$WorkoutStatsImpl) _then)
      : super(_value, _then);

  /// Create a copy of WorkoutStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? volumeKg = null,
    Object? durationMin = null,
    Object? exerciseCount = null,
  }) {
    return _then(_$WorkoutStatsImpl(
      volumeKg: null == volumeKg
          ? _value.volumeKg
          : volumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      exerciseCount: null == exerciseCount
          ? _value.exerciseCount
          : exerciseCount // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WorkoutStatsImpl implements _WorkoutStats {
  const _$WorkoutStatsImpl(
      {required this.volumeKg,
      required this.durationMin,
      required this.exerciseCount});

  factory _$WorkoutStatsImpl.fromJson(Map<String, dynamic> json) =>
      _$$WorkoutStatsImplFromJson(json);

  @override
  final double volumeKg;
  @override
  final int durationMin;
  @override
  final int exerciseCount;

  @override
  String toString() {
    return 'WorkoutStats(volumeKg: $volumeKg, durationMin: $durationMin, exerciseCount: $exerciseCount)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WorkoutStatsImpl &&
            (identical(other.volumeKg, volumeKg) ||
                other.volumeKg == volumeKg) &&
            (identical(other.durationMin, durationMin) ||
                other.durationMin == durationMin) &&
            (identical(other.exerciseCount, exerciseCount) ||
                other.exerciseCount == exerciseCount));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, volumeKg, durationMin, exerciseCount);

  /// Create a copy of WorkoutStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WorkoutStatsImplCopyWith<_$WorkoutStatsImpl> get copyWith =>
      __$$WorkoutStatsImplCopyWithImpl<_$WorkoutStatsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WorkoutStatsImplToJson(
      this,
    );
  }
}

abstract class _WorkoutStats implements WorkoutStats {
  const factory _WorkoutStats(
      {required final double volumeKg,
      required final int durationMin,
      required final int exerciseCount}) = _$WorkoutStatsImpl;

  factory _WorkoutStats.fromJson(Map<String, dynamic> json) =
      _$WorkoutStatsImpl.fromJson;

  @override
  double get volumeKg;
  @override
  int get durationMin;
  @override
  int get exerciseCount;

  /// Create a copy of WorkoutStats
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WorkoutStatsImplCopyWith<_$WorkoutStatsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
