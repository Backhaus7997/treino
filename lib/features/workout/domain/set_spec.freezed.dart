// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'set_spec.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

SetSpec _$SetSpecFromJson(Map<String, dynamic> json) {
  return _SetSpec.fromJson(json);
}

/// @nodoc
mixin _$SetSpec {
  /// The role of this set (warmup, working, drop, failure).
  ///
  /// Serialized as the enum name string; unknown values fall back to [SetType.normal].
  @JsonKey(unknownEnumValue: SetType.normal)
  SetType get type => throw _privateConstructorUsedError;

  /// Target weight in kilograms. Null means "bodyweight" or "user picks".
  double? get weightKg => throw _privateConstructorUsedError;

  /// Target rep count — used when [RepMode.single].
  int? get reps => throw _privateConstructorUsedError;

  /// Minimum reps — used when [RepMode.range].
  int? get repsMin => throw _privateConstructorUsedError;

  /// Maximum reps — used when [RepMode.range].
  int? get repsMax => throw _privateConstructorUsedError;

  /// Target duration in seconds — used when [ExerciseMode.duration].
  int? get durationSeconds => throw _privateConstructorUsedError;

  /// Serializes this SetSpec to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SetSpec
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SetSpecCopyWith<SetSpec> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SetSpecCopyWith<$Res> {
  factory $SetSpecCopyWith(SetSpec value, $Res Function(SetSpec) then) =
      _$SetSpecCopyWithImpl<$Res, SetSpec>;
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: SetType.normal) SetType type,
      double? weightKg,
      int? reps,
      int? repsMin,
      int? repsMax,
      int? durationSeconds});
}

/// @nodoc
class _$SetSpecCopyWithImpl<$Res, $Val extends SetSpec>
    implements $SetSpecCopyWith<$Res> {
  _$SetSpecCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SetSpec
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? weightKg = freezed,
    Object? reps = freezed,
    Object? repsMin = freezed,
    Object? repsMax = freezed,
    Object? durationSeconds = freezed,
  }) {
    return _then(_value.copyWith(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SetType,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      reps: freezed == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int?,
      repsMin: freezed == repsMin
          ? _value.repsMin
          : repsMin // ignore: cast_nullable_to_non_nullable
              as int?,
      repsMax: freezed == repsMax
          ? _value.repsMax
          : repsMax // ignore: cast_nullable_to_non_nullable
              as int?,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SetSpecImplCopyWith<$Res> implements $SetSpecCopyWith<$Res> {
  factory _$$SetSpecImplCopyWith(
          _$SetSpecImpl value, $Res Function(_$SetSpecImpl) then) =
      __$$SetSpecImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(unknownEnumValue: SetType.normal) SetType type,
      double? weightKg,
      int? reps,
      int? repsMin,
      int? repsMax,
      int? durationSeconds});
}

/// @nodoc
class __$$SetSpecImplCopyWithImpl<$Res>
    extends _$SetSpecCopyWithImpl<$Res, _$SetSpecImpl>
    implements _$$SetSpecImplCopyWith<$Res> {
  __$$SetSpecImplCopyWithImpl(
      _$SetSpecImpl _value, $Res Function(_$SetSpecImpl) _then)
      : super(_value, _then);

  /// Create a copy of SetSpec
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? weightKg = freezed,
    Object? reps = freezed,
    Object? repsMin = freezed,
    Object? repsMax = freezed,
    Object? durationSeconds = freezed,
  }) {
    return _then(_$SetSpecImpl(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as SetType,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      reps: freezed == reps
          ? _value.reps
          : reps // ignore: cast_nullable_to_non_nullable
              as int?,
      repsMin: freezed == repsMin
          ? _value.repsMin
          : repsMin // ignore: cast_nullable_to_non_nullable
              as int?,
      repsMax: freezed == repsMax
          ? _value.repsMax
          : repsMax // ignore: cast_nullable_to_non_nullable
              as int?,
      durationSeconds: freezed == durationSeconds
          ? _value.durationSeconds
          : durationSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SetSpecImpl implements _SetSpec {
  const _$SetSpecImpl(
      {@JsonKey(unknownEnumValue: SetType.normal) this.type = SetType.normal,
      this.weightKg,
      this.reps,
      this.repsMin,
      this.repsMax,
      this.durationSeconds});

  factory _$SetSpecImpl.fromJson(Map<String, dynamic> json) =>
      _$$SetSpecImplFromJson(json);

  /// The role of this set (warmup, working, drop, failure).
  ///
  /// Serialized as the enum name string; unknown values fall back to [SetType.normal].
  @override
  @JsonKey(unknownEnumValue: SetType.normal)
  final SetType type;

  /// Target weight in kilograms. Null means "bodyweight" or "user picks".
  @override
  final double? weightKg;

  /// Target rep count — used when [RepMode.single].
  @override
  final int? reps;

  /// Minimum reps — used when [RepMode.range].
  @override
  final int? repsMin;

  /// Maximum reps — used when [RepMode.range].
  @override
  final int? repsMax;

  /// Target duration in seconds — used when [ExerciseMode.duration].
  @override
  final int? durationSeconds;

  @override
  String toString() {
    return 'SetSpec(type: $type, weightKg: $weightKg, reps: $reps, repsMin: $repsMin, repsMax: $repsMax, durationSeconds: $durationSeconds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SetSpecImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.weightKg, weightKg) ||
                other.weightKg == weightKg) &&
            (identical(other.reps, reps) || other.reps == reps) &&
            (identical(other.repsMin, repsMin) || other.repsMin == repsMin) &&
            (identical(other.repsMax, repsMax) || other.repsMax == repsMax) &&
            (identical(other.durationSeconds, durationSeconds) ||
                other.durationSeconds == durationSeconds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, weightKg, reps, repsMin, repsMax, durationSeconds);

  /// Create a copy of SetSpec
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SetSpecImplCopyWith<_$SetSpecImpl> get copyWith =>
      __$$SetSpecImplCopyWithImpl<_$SetSpecImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SetSpecImplToJson(
      this,
    );
  }
}

abstract class _SetSpec implements SetSpec {
  const factory _SetSpec(
      {@JsonKey(unknownEnumValue: SetType.normal) final SetType type,
      final double? weightKg,
      final int? reps,
      final int? repsMin,
      final int? repsMax,
      final int? durationSeconds}) = _$SetSpecImpl;

  factory _SetSpec.fromJson(Map<String, dynamic> json) = _$SetSpecImpl.fromJson;

  /// The role of this set (warmup, working, drop, failure).
  ///
  /// Serialized as the enum name string; unknown values fall back to [SetType.normal].
  @override
  @JsonKey(unknownEnumValue: SetType.normal)
  SetType get type;

  /// Target weight in kilograms. Null means "bodyweight" or "user picks".
  @override
  double? get weightKg;

  /// Target rep count — used when [RepMode.single].
  @override
  int? get reps;

  /// Minimum reps — used when [RepMode.range].
  @override
  int? get repsMin;

  /// Maximum reps — used when [RepMode.range].
  @override
  int? get repsMax;

  /// Target duration in seconds — used when [ExerciseMode.duration].
  @override
  int? get durationSeconds;

  /// Create a copy of SetSpec
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SetSpecImplCopyWith<_$SetSpecImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
