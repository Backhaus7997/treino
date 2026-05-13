// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine_day.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RoutineDay _$RoutineDayFromJson(Map<String, dynamic> json) {
  return _RoutineDay.fromJson(json);
}

/// @nodoc
mixin _$RoutineDay {
  int get dayNumber => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  List<RoutineSlot> get slots =>
      throw _privateConstructorUsedError; // empty list is valid (spec SCENARIO-046)
  int? get estimatedMinutes => throw _privateConstructorUsedError;

  /// Serializes this RoutineDay to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RoutineDay
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoutineDayCopyWith<RoutineDay> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoutineDayCopyWith<$Res> {
  factory $RoutineDayCopyWith(
          RoutineDay value, $Res Function(RoutineDay) then) =
      _$RoutineDayCopyWithImpl<$Res, RoutineDay>;
  @useResult
  $Res call(
      {int dayNumber,
      String name,
      List<RoutineSlot> slots,
      int? estimatedMinutes});
}

/// @nodoc
class _$RoutineDayCopyWithImpl<$Res, $Val extends RoutineDay>
    implements $RoutineDayCopyWith<$Res> {
  _$RoutineDayCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RoutineDay
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? name = null,
    Object? slots = null,
    Object? estimatedMinutes = freezed,
  }) {
    return _then(_value.copyWith(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      slots: null == slots
          ? _value.slots
          : slots // ignore: cast_nullable_to_non_nullable
              as List<RoutineSlot>,
      estimatedMinutes: freezed == estimatedMinutes
          ? _value.estimatedMinutes
          : estimatedMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RoutineDayImplCopyWith<$Res>
    implements $RoutineDayCopyWith<$Res> {
  factory _$$RoutineDayImplCopyWith(
          _$RoutineDayImpl value, $Res Function(_$RoutineDayImpl) then) =
      __$$RoutineDayImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {int dayNumber,
      String name,
      List<RoutineSlot> slots,
      int? estimatedMinutes});
}

/// @nodoc
class __$$RoutineDayImplCopyWithImpl<$Res>
    extends _$RoutineDayCopyWithImpl<$Res, _$RoutineDayImpl>
    implements _$$RoutineDayImplCopyWith<$Res> {
  __$$RoutineDayImplCopyWithImpl(
      _$RoutineDayImpl _value, $Res Function(_$RoutineDayImpl) _then)
      : super(_value, _then);

  /// Create a copy of RoutineDay
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? name = null,
    Object? slots = null,
    Object? estimatedMinutes = freezed,
  }) {
    return _then(_$RoutineDayImpl(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      slots: null == slots
          ? _value._slots
          : slots // ignore: cast_nullable_to_non_nullable
              as List<RoutineSlot>,
      estimatedMinutes: freezed == estimatedMinutes
          ? _value.estimatedMinutes
          : estimatedMinutes // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RoutineDayImpl implements _RoutineDay {
  const _$RoutineDayImpl(
      {required this.dayNumber,
      required this.name,
      required final List<RoutineSlot> slots,
      this.estimatedMinutes})
      : _slots = slots;

  factory _$RoutineDayImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoutineDayImplFromJson(json);

  @override
  final int dayNumber;
  @override
  final String name;
  final List<RoutineSlot> _slots;
  @override
  List<RoutineSlot> get slots {
    if (_slots is EqualUnmodifiableListView) return _slots;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_slots);
  }

// empty list is valid (spec SCENARIO-046)
  @override
  final int? estimatedMinutes;

  @override
  String toString() {
    return 'RoutineDay(dayNumber: $dayNumber, name: $name, slots: $slots, estimatedMinutes: $estimatedMinutes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoutineDayImpl &&
            (identical(other.dayNumber, dayNumber) ||
                other.dayNumber == dayNumber) &&
            (identical(other.name, name) || other.name == name) &&
            const DeepCollectionEquality().equals(other._slots, _slots) &&
            (identical(other.estimatedMinutes, estimatedMinutes) ||
                other.estimatedMinutes == estimatedMinutes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, dayNumber, name,
      const DeepCollectionEquality().hash(_slots), estimatedMinutes);

  /// Create a copy of RoutineDay
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoutineDayImplCopyWith<_$RoutineDayImpl> get copyWith =>
      __$$RoutineDayImplCopyWithImpl<_$RoutineDayImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoutineDayImplToJson(
      this,
    );
  }
}

abstract class _RoutineDay implements RoutineDay {
  const factory _RoutineDay(
      {required final int dayNumber,
      required final String name,
      required final List<RoutineSlot> slots,
      final int? estimatedMinutes}) = _$RoutineDayImpl;

  factory _RoutineDay.fromJson(Map<String, dynamic> json) =
      _$RoutineDayImpl.fromJson;

  @override
  int get dayNumber;
  @override
  String get name;
  @override
  List<RoutineSlot> get slots; // empty list is valid (spec SCENARIO-046)
  @override
  int? get estimatedMinutes;

  /// Create a copy of RoutineDay
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoutineDayImplCopyWith<_$RoutineDayImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
