// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine_slot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RoutineSlot _$RoutineSlotFromJson(Map<String, dynamic> json) {
  return _RoutineSlot.fromJson(json);
}

/// @nodoc
mixin _$RoutineSlot {
  String get exerciseId =>
      throw _privateConstructorUsedError; // FK → exercises/{id} (canonical reference)
  String get exerciseName =>
      throw _privateConstructorUsedError; // denormalized for compact card display (ADR-2)
  String get muscleGroup =>
      throw _privateConstructorUsedError; // denormalized for compact card display
  int get targetSets => throw _privateConstructorUsedError;
  int get targetRepsMin => throw _privateConstructorUsedError;
  int get targetRepsMax => throw _privateConstructorUsedError;
  int get restSeconds => throw _privateConstructorUsedError;
  double? get targetWeightKg =>
      throw _privateConstructorUsedError; // null means "user picks" or "no target" (plate math)
  String? get notes =>
      throw _privateConstructorUsedError; // nullable free-form coaching notes
  int? get supersetGroup => throw _privateConstructorUsedError;

  /// Serializes this RoutineSlot to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoutineSlotCopyWith<RoutineSlot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoutineSlotCopyWith<$Res> {
  factory $RoutineSlotCopyWith(
          RoutineSlot value, $Res Function(RoutineSlot) then) =
      _$RoutineSlotCopyWithImpl<$Res, RoutineSlot>;
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      String muscleGroup,
      int targetSets,
      int targetRepsMin,
      int targetRepsMax,
      int restSeconds,
      double? targetWeightKg,
      String? notes,
      int? supersetGroup});
}

/// @nodoc
class _$RoutineSlotCopyWithImpl<$Res, $Val extends RoutineSlot>
    implements $RoutineSlotCopyWith<$Res> {
  _$RoutineSlotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? muscleGroup = null,
    Object? targetSets = null,
    Object? targetRepsMin = null,
    Object? targetRepsMax = null,
    Object? restSeconds = null,
    Object? targetWeightKg = freezed,
    Object? notes = freezed,
    Object? supersetGroup = freezed,
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
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetSets: null == targetSets
          ? _value.targetSets
          : targetSets // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMin: null == targetRepsMin
          ? _value.targetRepsMin
          : targetRepsMin // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMax: null == targetRepsMax
          ? _value.targetRepsMax
          : targetRepsMax // ignore: cast_nullable_to_non_nullable
              as int,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      targetWeightKg: freezed == targetWeightKg
          ? _value.targetWeightKg
          : targetWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      supersetGroup: freezed == supersetGroup
          ? _value.supersetGroup
          : supersetGroup // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RoutineSlotImplCopyWith<$Res>
    implements $RoutineSlotCopyWith<$Res> {
  factory _$$RoutineSlotImplCopyWith(
          _$RoutineSlotImpl value, $Res Function(_$RoutineSlotImpl) then) =
      __$$RoutineSlotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String exerciseId,
      String exerciseName,
      String muscleGroup,
      int targetSets,
      int targetRepsMin,
      int targetRepsMax,
      int restSeconds,
      double? targetWeightKg,
      String? notes,
      int? supersetGroup});
}

/// @nodoc
class __$$RoutineSlotImplCopyWithImpl<$Res>
    extends _$RoutineSlotCopyWithImpl<$Res, _$RoutineSlotImpl>
    implements _$$RoutineSlotImplCopyWith<$Res> {
  __$$RoutineSlotImplCopyWithImpl(
      _$RoutineSlotImpl _value, $Res Function(_$RoutineSlotImpl) _then)
      : super(_value, _then);

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? muscleGroup = null,
    Object? targetSets = null,
    Object? targetRepsMin = null,
    Object? targetRepsMax = null,
    Object? restSeconds = null,
    Object? targetWeightKg = freezed,
    Object? notes = freezed,
    Object? supersetGroup = freezed,
  }) {
    return _then(_$RoutineSlotImpl(
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      targetSets: null == targetSets
          ? _value.targetSets
          : targetSets // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMin: null == targetRepsMin
          ? _value.targetRepsMin
          : targetRepsMin // ignore: cast_nullable_to_non_nullable
              as int,
      targetRepsMax: null == targetRepsMax
          ? _value.targetRepsMax
          : targetRepsMax // ignore: cast_nullable_to_non_nullable
              as int,
      restSeconds: null == restSeconds
          ? _value.restSeconds
          : restSeconds // ignore: cast_nullable_to_non_nullable
              as int,
      targetWeightKg: freezed == targetWeightKg
          ? _value.targetWeightKg
          : targetWeightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      supersetGroup: freezed == supersetGroup
          ? _value.supersetGroup
          : supersetGroup // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RoutineSlotImpl implements _RoutineSlot {
  const _$RoutineSlotImpl(
      {required this.exerciseId,
      required this.exerciseName,
      required this.muscleGroup,
      required this.targetSets,
      required this.targetRepsMin,
      required this.targetRepsMax,
      required this.restSeconds,
      this.targetWeightKg,
      this.notes,
      this.supersetGroup});

  factory _$RoutineSlotImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoutineSlotImplFromJson(json);

  @override
  final String exerciseId;
// FK → exercises/{id} (canonical reference)
  @override
  final String exerciseName;
// denormalized for compact card display (ADR-2)
  @override
  final String muscleGroup;
// denormalized for compact card display
  @override
  final int targetSets;
  @override
  final int targetRepsMin;
  @override
  final int targetRepsMax;
  @override
  final int restSeconds;
  @override
  final double? targetWeightKg;
// null means "user picks" or "no target" (plate math)
  @override
  final String? notes;
// nullable free-form coaching notes
  @override
  final int? supersetGroup;

  @override
  String toString() {
    return 'RoutineSlot(exerciseId: $exerciseId, exerciseName: $exerciseName, muscleGroup: $muscleGroup, targetSets: $targetSets, targetRepsMin: $targetRepsMin, targetRepsMax: $targetRepsMax, restSeconds: $restSeconds, targetWeightKg: $targetWeightKg, notes: $notes, supersetGroup: $supersetGroup)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoutineSlotImpl &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup) &&
            (identical(other.targetSets, targetSets) ||
                other.targetSets == targetSets) &&
            (identical(other.targetRepsMin, targetRepsMin) ||
                other.targetRepsMin == targetRepsMin) &&
            (identical(other.targetRepsMax, targetRepsMax) ||
                other.targetRepsMax == targetRepsMax) &&
            (identical(other.restSeconds, restSeconds) ||
                other.restSeconds == restSeconds) &&
            (identical(other.targetWeightKg, targetWeightKg) ||
                other.targetWeightKg == targetWeightKg) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.supersetGroup, supersetGroup) ||
                other.supersetGroup == supersetGroup));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      exerciseId,
      exerciseName,
      muscleGroup,
      targetSets,
      targetRepsMin,
      targetRepsMax,
      restSeconds,
      targetWeightKg,
      notes,
      supersetGroup);

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoutineSlotImplCopyWith<_$RoutineSlotImpl> get copyWith =>
      __$$RoutineSlotImplCopyWithImpl<_$RoutineSlotImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoutineSlotImplToJson(
      this,
    );
  }
}

abstract class _RoutineSlot implements RoutineSlot {
  const factory _RoutineSlot(
      {required final String exerciseId,
      required final String exerciseName,
      required final String muscleGroup,
      required final int targetSets,
      required final int targetRepsMin,
      required final int targetRepsMax,
      required final int restSeconds,
      final double? targetWeightKg,
      final String? notes,
      final int? supersetGroup}) = _$RoutineSlotImpl;

  factory _RoutineSlot.fromJson(Map<String, dynamic> json) =
      _$RoutineSlotImpl.fromJson;

  @override
  String get exerciseId; // FK → exercises/{id} (canonical reference)
  @override
  String get exerciseName; // denormalized for compact card display (ADR-2)
  @override
  String get muscleGroup; // denormalized for compact card display
  @override
  int get targetSets;
  @override
  int get targetRepsMin;
  @override
  int get targetRepsMax;
  @override
  int get restSeconds;
  @override
  double?
      get targetWeightKg; // null means "user picks" or "no target" (plate math)
  @override
  String? get notes; // nullable free-form coaching notes
  @override
  int? get supersetGroup;

  /// Create a copy of RoutineSlot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoutineSlotImplCopyWith<_$RoutineSlotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
