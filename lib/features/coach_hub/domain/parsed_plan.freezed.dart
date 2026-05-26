// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'parsed_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ParsedPlan _$ParsedPlanFromJson(Map<String, dynamic> json) {
  return _ParsedPlan.fromJson(json);
}

/// @nodoc
mixin _$ParsedPlan {
  String get name => throw _privateConstructorUsedError;
  int get daysPerWeek => throw _privateConstructorUsedError;
  int get durationWeeks => throw _privateConstructorUsedError;
  ExperienceLevel get level => throw _privateConstructorUsedError;
  List<ParsedPlanDay> get days => throw _privateConstructorUsedError;
  List<ParsedPlanUnmatched> get unmatched => throw _privateConstructorUsedError;

  /// Serializes this ParsedPlan to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ParsedPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ParsedPlanCopyWith<ParsedPlan> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ParsedPlanCopyWith<$Res> {
  factory $ParsedPlanCopyWith(
          ParsedPlan value, $Res Function(ParsedPlan) then) =
      _$ParsedPlanCopyWithImpl<$Res, ParsedPlan>;
  @useResult
  $Res call(
      {String name,
      int daysPerWeek,
      int durationWeeks,
      ExperienceLevel level,
      List<ParsedPlanDay> days,
      List<ParsedPlanUnmatched> unmatched});
}

/// @nodoc
class _$ParsedPlanCopyWithImpl<$Res, $Val extends ParsedPlan>
    implements $ParsedPlanCopyWith<$Res> {
  _$ParsedPlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ParsedPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? daysPerWeek = null,
    Object? durationWeeks = null,
    Object? level = null,
    Object? days = null,
    Object? unmatched = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      daysPerWeek: null == daysPerWeek
          ? _value.daysPerWeek
          : daysPerWeek // ignore: cast_nullable_to_non_nullable
              as int,
      durationWeeks: null == durationWeeks
          ? _value.durationWeeks
          : durationWeeks // ignore: cast_nullable_to_non_nullable
              as int,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel,
      days: null == days
          ? _value.days
          : days // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanDay>,
      unmatched: null == unmatched
          ? _value.unmatched
          : unmatched // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanUnmatched>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ParsedPlanImplCopyWith<$Res>
    implements $ParsedPlanCopyWith<$Res> {
  factory _$$ParsedPlanImplCopyWith(
          _$ParsedPlanImpl value, $Res Function(_$ParsedPlanImpl) then) =
      __$$ParsedPlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String name,
      int daysPerWeek,
      int durationWeeks,
      ExperienceLevel level,
      List<ParsedPlanDay> days,
      List<ParsedPlanUnmatched> unmatched});
}

/// @nodoc
class __$$ParsedPlanImplCopyWithImpl<$Res>
    extends _$ParsedPlanCopyWithImpl<$Res, _$ParsedPlanImpl>
    implements _$$ParsedPlanImplCopyWith<$Res> {
  __$$ParsedPlanImplCopyWithImpl(
      _$ParsedPlanImpl _value, $Res Function(_$ParsedPlanImpl) _then)
      : super(_value, _then);

  /// Create a copy of ParsedPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? daysPerWeek = null,
    Object? durationWeeks = null,
    Object? level = null,
    Object? days = null,
    Object? unmatched = null,
  }) {
    return _then(_$ParsedPlanImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      daysPerWeek: null == daysPerWeek
          ? _value.daysPerWeek
          : daysPerWeek // ignore: cast_nullable_to_non_nullable
              as int,
      durationWeeks: null == durationWeeks
          ? _value.durationWeeks
          : durationWeeks // ignore: cast_nullable_to_non_nullable
              as int,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel,
      days: null == days
          ? _value._days
          : days // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanDay>,
      unmatched: null == unmatched
          ? _value._unmatched
          : unmatched // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanUnmatched>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ParsedPlanImpl implements _ParsedPlan {
  const _$ParsedPlanImpl(
      {required this.name,
      required this.daysPerWeek,
      required this.durationWeeks,
      required this.level,
      required final List<ParsedPlanDay> days,
      final List<ParsedPlanUnmatched> unmatched =
          const <ParsedPlanUnmatched>[]})
      : _days = days,
        _unmatched = unmatched;

  factory _$ParsedPlanImpl.fromJson(Map<String, dynamic> json) =>
      _$$ParsedPlanImplFromJson(json);

  @override
  final String name;
  @override
  final int daysPerWeek;
  @override
  final int durationWeeks;
  @override
  final ExperienceLevel level;
  final List<ParsedPlanDay> _days;
  @override
  List<ParsedPlanDay> get days {
    if (_days is EqualUnmodifiableListView) return _days;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_days);
  }

  final List<ParsedPlanUnmatched> _unmatched;
  @override
  @JsonKey()
  List<ParsedPlanUnmatched> get unmatched {
    if (_unmatched is EqualUnmodifiableListView) return _unmatched;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_unmatched);
  }

  @override
  String toString() {
    return 'ParsedPlan(name: $name, daysPerWeek: $daysPerWeek, durationWeeks: $durationWeeks, level: $level, days: $days, unmatched: $unmatched)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ParsedPlanImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.daysPerWeek, daysPerWeek) ||
                other.daysPerWeek == daysPerWeek) &&
            (identical(other.durationWeeks, durationWeeks) ||
                other.durationWeeks == durationWeeks) &&
            (identical(other.level, level) || other.level == level) &&
            const DeepCollectionEquality().equals(other._days, _days) &&
            const DeepCollectionEquality()
                .equals(other._unmatched, _unmatched));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      name,
      daysPerWeek,
      durationWeeks,
      level,
      const DeepCollectionEquality().hash(_days),
      const DeepCollectionEquality().hash(_unmatched));

  /// Create a copy of ParsedPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ParsedPlanImplCopyWith<_$ParsedPlanImpl> get copyWith =>
      __$$ParsedPlanImplCopyWithImpl<_$ParsedPlanImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ParsedPlanImplToJson(
      this,
    );
  }
}

abstract class _ParsedPlan implements ParsedPlan {
  const factory _ParsedPlan(
      {required final String name,
      required final int daysPerWeek,
      required final int durationWeeks,
      required final ExperienceLevel level,
      required final List<ParsedPlanDay> days,
      final List<ParsedPlanUnmatched> unmatched}) = _$ParsedPlanImpl;

  factory _ParsedPlan.fromJson(Map<String, dynamic> json) =
      _$ParsedPlanImpl.fromJson;

  @override
  String get name;
  @override
  int get daysPerWeek;
  @override
  int get durationWeeks;
  @override
  ExperienceLevel get level;
  @override
  List<ParsedPlanDay> get days;
  @override
  List<ParsedPlanUnmatched> get unmatched;

  /// Create a copy of ParsedPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ParsedPlanImplCopyWith<_$ParsedPlanImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ParsedPlanDay _$ParsedPlanDayFromJson(Map<String, dynamic> json) {
  return _ParsedPlanDay.fromJson(json);
}

/// @nodoc
mixin _$ParsedPlanDay {
  int get dayNumber => throw _privateConstructorUsedError;
  List<ParsedPlanItem> get items => throw _privateConstructorUsedError;

  /// Serializes this ParsedPlanDay to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ParsedPlanDay
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ParsedPlanDayCopyWith<ParsedPlanDay> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ParsedPlanDayCopyWith<$Res> {
  factory $ParsedPlanDayCopyWith(
          ParsedPlanDay value, $Res Function(ParsedPlanDay) then) =
      _$ParsedPlanDayCopyWithImpl<$Res, ParsedPlanDay>;
  @useResult
  $Res call({int dayNumber, List<ParsedPlanItem> items});
}

/// @nodoc
class _$ParsedPlanDayCopyWithImpl<$Res, $Val extends ParsedPlanDay>
    implements $ParsedPlanDayCopyWith<$Res> {
  _$ParsedPlanDayCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ParsedPlanDay
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? items = null,
  }) {
    return _then(_value.copyWith(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      items: null == items
          ? _value.items
          : items // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanItem>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ParsedPlanDayImplCopyWith<$Res>
    implements $ParsedPlanDayCopyWith<$Res> {
  factory _$$ParsedPlanDayImplCopyWith(
          _$ParsedPlanDayImpl value, $Res Function(_$ParsedPlanDayImpl) then) =
      __$$ParsedPlanDayImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int dayNumber, List<ParsedPlanItem> items});
}

/// @nodoc
class __$$ParsedPlanDayImplCopyWithImpl<$Res>
    extends _$ParsedPlanDayCopyWithImpl<$Res, _$ParsedPlanDayImpl>
    implements _$$ParsedPlanDayImplCopyWith<$Res> {
  __$$ParsedPlanDayImplCopyWithImpl(
      _$ParsedPlanDayImpl _value, $Res Function(_$ParsedPlanDayImpl) _then)
      : super(_value, _then);

  /// Create a copy of ParsedPlanDay
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? items = null,
  }) {
    return _then(_$ParsedPlanDayImpl(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      items: null == items
          ? _value._items
          : items // ignore: cast_nullable_to_non_nullable
              as List<ParsedPlanItem>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ParsedPlanDayImpl implements _ParsedPlanDay {
  const _$ParsedPlanDayImpl(
      {required this.dayNumber, required final List<ParsedPlanItem> items})
      : _items = items;

  factory _$ParsedPlanDayImpl.fromJson(Map<String, dynamic> json) =>
      _$$ParsedPlanDayImplFromJson(json);

  @override
  final int dayNumber;
  final List<ParsedPlanItem> _items;
  @override
  List<ParsedPlanItem> get items {
    if (_items is EqualUnmodifiableListView) return _items;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_items);
  }

  @override
  String toString() {
    return 'ParsedPlanDay(dayNumber: $dayNumber, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ParsedPlanDayImpl &&
            (identical(other.dayNumber, dayNumber) ||
                other.dayNumber == dayNumber) &&
            const DeepCollectionEquality().equals(other._items, _items));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, dayNumber, const DeepCollectionEquality().hash(_items));

  /// Create a copy of ParsedPlanDay
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ParsedPlanDayImplCopyWith<_$ParsedPlanDayImpl> get copyWith =>
      __$$ParsedPlanDayImplCopyWithImpl<_$ParsedPlanDayImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ParsedPlanDayImplToJson(
      this,
    );
  }
}

abstract class _ParsedPlanDay implements ParsedPlanDay {
  const factory _ParsedPlanDay(
      {required final int dayNumber,
      required final List<ParsedPlanItem> items}) = _$ParsedPlanDayImpl;

  factory _ParsedPlanDay.fromJson(Map<String, dynamic> json) =
      _$ParsedPlanDayImpl.fromJson;

  @override
  int get dayNumber;
  @override
  List<ParsedPlanItem> get items;

  /// Create a copy of ParsedPlanDay
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ParsedPlanDayImplCopyWith<_$ParsedPlanDayImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ParsedPlanItem _$ParsedPlanItemFromJson(Map<String, dynamic> json) {
  return _ParsedPlanItem.fromJson(json);
}

/// @nodoc
mixin _$ParsedPlanItem {
  String get rowName => throw _privateConstructorUsedError;
  int get sets => throw _privateConstructorUsedError;
  int get repsMin => throw _privateConstructorUsedError;
  int get repsMax => throw _privateConstructorUsedError;
  double? get weightKg => throw _privateConstructorUsedError;
  int? get restSec => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;
  String? get exerciseId => throw _privateConstructorUsedError;
  String get exerciseName => throw _privateConstructorUsedError;
  String? get muscleGroup => throw _privateConstructorUsedError;

  /// Serializes this ParsedPlanItem to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ParsedPlanItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ParsedPlanItemCopyWith<ParsedPlanItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ParsedPlanItemCopyWith<$Res> {
  factory $ParsedPlanItemCopyWith(
          ParsedPlanItem value, $Res Function(ParsedPlanItem) then) =
      _$ParsedPlanItemCopyWithImpl<$Res, ParsedPlanItem>;
  @useResult
  $Res call(
      {String rowName,
      int sets,
      int repsMin,
      int repsMax,
      double? weightKg,
      int? restSec,
      String? notes,
      String? exerciseId,
      String exerciseName,
      String? muscleGroup});
}

/// @nodoc
class _$ParsedPlanItemCopyWithImpl<$Res, $Val extends ParsedPlanItem>
    implements $ParsedPlanItemCopyWith<$Res> {
  _$ParsedPlanItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ParsedPlanItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? rowName = null,
    Object? sets = null,
    Object? repsMin = null,
    Object? repsMax = null,
    Object? weightKg = freezed,
    Object? restSec = freezed,
    Object? notes = freezed,
    Object? exerciseId = freezed,
    Object? exerciseName = null,
    Object? muscleGroup = freezed,
  }) {
    return _then(_value.copyWith(
      rowName: null == rowName
          ? _value.rowName
          : rowName // ignore: cast_nullable_to_non_nullable
              as String,
      sets: null == sets
          ? _value.sets
          : sets // ignore: cast_nullable_to_non_nullable
              as int,
      repsMin: null == repsMin
          ? _value.repsMin
          : repsMin // ignore: cast_nullable_to_non_nullable
              as int,
      repsMax: null == repsMax
          ? _value.repsMax
          : repsMax // ignore: cast_nullable_to_non_nullable
              as int,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      restSec: freezed == restSec
          ? _value.restSec
          : restSec // ignore: cast_nullable_to_non_nullable
              as int?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      exerciseId: freezed == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String?,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: freezed == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ParsedPlanItemImplCopyWith<$Res>
    implements $ParsedPlanItemCopyWith<$Res> {
  factory _$$ParsedPlanItemImplCopyWith(_$ParsedPlanItemImpl value,
          $Res Function(_$ParsedPlanItemImpl) then) =
      __$$ParsedPlanItemImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String rowName,
      int sets,
      int repsMin,
      int repsMax,
      double? weightKg,
      int? restSec,
      String? notes,
      String? exerciseId,
      String exerciseName,
      String? muscleGroup});
}

/// @nodoc
class __$$ParsedPlanItemImplCopyWithImpl<$Res>
    extends _$ParsedPlanItemCopyWithImpl<$Res, _$ParsedPlanItemImpl>
    implements _$$ParsedPlanItemImplCopyWith<$Res> {
  __$$ParsedPlanItemImplCopyWithImpl(
      _$ParsedPlanItemImpl _value, $Res Function(_$ParsedPlanItemImpl) _then)
      : super(_value, _then);

  /// Create a copy of ParsedPlanItem
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? rowName = null,
    Object? sets = null,
    Object? repsMin = null,
    Object? repsMax = null,
    Object? weightKg = freezed,
    Object? restSec = freezed,
    Object? notes = freezed,
    Object? exerciseId = freezed,
    Object? exerciseName = null,
    Object? muscleGroup = freezed,
  }) {
    return _then(_$ParsedPlanItemImpl(
      rowName: null == rowName
          ? _value.rowName
          : rowName // ignore: cast_nullable_to_non_nullable
              as String,
      sets: null == sets
          ? _value.sets
          : sets // ignore: cast_nullable_to_non_nullable
              as int,
      repsMin: null == repsMin
          ? _value.repsMin
          : repsMin // ignore: cast_nullable_to_non_nullable
              as int,
      repsMax: null == repsMax
          ? _value.repsMax
          : repsMax // ignore: cast_nullable_to_non_nullable
              as int,
      weightKg: freezed == weightKg
          ? _value.weightKg
          : weightKg // ignore: cast_nullable_to_non_nullable
              as double?,
      restSec: freezed == restSec
          ? _value.restSec
          : restSec // ignore: cast_nullable_to_non_nullable
              as int?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
      exerciseId: freezed == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String?,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: freezed == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ParsedPlanItemImpl implements _ParsedPlanItem {
  const _$ParsedPlanItemImpl(
      {required this.rowName,
      required this.sets,
      required this.repsMin,
      required this.repsMax,
      this.weightKg,
      this.restSec,
      this.notes,
      this.exerciseId,
      required this.exerciseName,
      this.muscleGroup});

  factory _$ParsedPlanItemImpl.fromJson(Map<String, dynamic> json) =>
      _$$ParsedPlanItemImplFromJson(json);

  @override
  final String rowName;
  @override
  final int sets;
  @override
  final int repsMin;
  @override
  final int repsMax;
  @override
  final double? weightKg;
  @override
  final int? restSec;
  @override
  final String? notes;
  @override
  final String? exerciseId;
  @override
  final String exerciseName;
  @override
  final String? muscleGroup;

  @override
  String toString() {
    return 'ParsedPlanItem(rowName: $rowName, sets: $sets, repsMin: $repsMin, repsMax: $repsMax, weightKg: $weightKg, restSec: $restSec, notes: $notes, exerciseId: $exerciseId, exerciseName: $exerciseName, muscleGroup: $muscleGroup)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ParsedPlanItemImpl &&
            (identical(other.rowName, rowName) || other.rowName == rowName) &&
            (identical(other.sets, sets) || other.sets == sets) &&
            (identical(other.repsMin, repsMin) || other.repsMin == repsMin) &&
            (identical(other.repsMax, repsMax) || other.repsMax == repsMax) &&
            (identical(other.weightKg, weightKg) ||
                other.weightKg == weightKg) &&
            (identical(other.restSec, restSec) || other.restSec == restSec) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, rowName, sets, repsMin, repsMax,
      weightKg, restSec, notes, exerciseId, exerciseName, muscleGroup);

  /// Create a copy of ParsedPlanItem
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ParsedPlanItemImplCopyWith<_$ParsedPlanItemImpl> get copyWith =>
      __$$ParsedPlanItemImplCopyWithImpl<_$ParsedPlanItemImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ParsedPlanItemImplToJson(
      this,
    );
  }
}

abstract class _ParsedPlanItem implements ParsedPlanItem {
  const factory _ParsedPlanItem(
      {required final String rowName,
      required final int sets,
      required final int repsMin,
      required final int repsMax,
      final double? weightKg,
      final int? restSec,
      final String? notes,
      final String? exerciseId,
      required final String exerciseName,
      final String? muscleGroup}) = _$ParsedPlanItemImpl;

  factory _ParsedPlanItem.fromJson(Map<String, dynamic> json) =
      _$ParsedPlanItemImpl.fromJson;

  @override
  String get rowName;
  @override
  int get sets;
  @override
  int get repsMin;
  @override
  int get repsMax;
  @override
  double? get weightKg;
  @override
  int? get restSec;
  @override
  String? get notes;
  @override
  String? get exerciseId;
  @override
  String get exerciseName;
  @override
  String? get muscleGroup;

  /// Create a copy of ParsedPlanItem
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ParsedPlanItemImplCopyWith<_$ParsedPlanItemImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ParsedPlanUnmatched _$ParsedPlanUnmatchedFromJson(Map<String, dynamic> json) {
  return _ParsedPlanUnmatched.fromJson(json);
}

/// @nodoc
mixin _$ParsedPlanUnmatched {
  int get dayNumber => throw _privateConstructorUsedError;
  String get rowName => throw _privateConstructorUsedError;

  /// Serializes this ParsedPlanUnmatched to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ParsedPlanUnmatched
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ParsedPlanUnmatchedCopyWith<ParsedPlanUnmatched> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ParsedPlanUnmatchedCopyWith<$Res> {
  factory $ParsedPlanUnmatchedCopyWith(
          ParsedPlanUnmatched value, $Res Function(ParsedPlanUnmatched) then) =
      _$ParsedPlanUnmatchedCopyWithImpl<$Res, ParsedPlanUnmatched>;
  @useResult
  $Res call({int dayNumber, String rowName});
}

/// @nodoc
class _$ParsedPlanUnmatchedCopyWithImpl<$Res, $Val extends ParsedPlanUnmatched>
    implements $ParsedPlanUnmatchedCopyWith<$Res> {
  _$ParsedPlanUnmatchedCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ParsedPlanUnmatched
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? rowName = null,
  }) {
    return _then(_value.copyWith(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      rowName: null == rowName
          ? _value.rowName
          : rowName // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ParsedPlanUnmatchedImplCopyWith<$Res>
    implements $ParsedPlanUnmatchedCopyWith<$Res> {
  factory _$$ParsedPlanUnmatchedImplCopyWith(_$ParsedPlanUnmatchedImpl value,
          $Res Function(_$ParsedPlanUnmatchedImpl) then) =
      __$$ParsedPlanUnmatchedImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int dayNumber, String rowName});
}

/// @nodoc
class __$$ParsedPlanUnmatchedImplCopyWithImpl<$Res>
    extends _$ParsedPlanUnmatchedCopyWithImpl<$Res, _$ParsedPlanUnmatchedImpl>
    implements _$$ParsedPlanUnmatchedImplCopyWith<$Res> {
  __$$ParsedPlanUnmatchedImplCopyWithImpl(_$ParsedPlanUnmatchedImpl _value,
      $Res Function(_$ParsedPlanUnmatchedImpl) _then)
      : super(_value, _then);

  /// Create a copy of ParsedPlanUnmatched
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dayNumber = null,
    Object? rowName = null,
  }) {
    return _then(_$ParsedPlanUnmatchedImpl(
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      rowName: null == rowName
          ? _value.rowName
          : rowName // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ParsedPlanUnmatchedImpl implements _ParsedPlanUnmatched {
  const _$ParsedPlanUnmatchedImpl(
      {required this.dayNumber, required this.rowName});

  factory _$ParsedPlanUnmatchedImpl.fromJson(Map<String, dynamic> json) =>
      _$$ParsedPlanUnmatchedImplFromJson(json);

  @override
  final int dayNumber;
  @override
  final String rowName;

  @override
  String toString() {
    return 'ParsedPlanUnmatched(dayNumber: $dayNumber, rowName: $rowName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ParsedPlanUnmatchedImpl &&
            (identical(other.dayNumber, dayNumber) ||
                other.dayNumber == dayNumber) &&
            (identical(other.rowName, rowName) || other.rowName == rowName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, dayNumber, rowName);

  /// Create a copy of ParsedPlanUnmatched
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ParsedPlanUnmatchedImplCopyWith<_$ParsedPlanUnmatchedImpl> get copyWith =>
      __$$ParsedPlanUnmatchedImplCopyWithImpl<_$ParsedPlanUnmatchedImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ParsedPlanUnmatchedImplToJson(
      this,
    );
  }
}

abstract class _ParsedPlanUnmatched implements ParsedPlanUnmatched {
  const factory _ParsedPlanUnmatched(
      {required final int dayNumber,
      required final String rowName}) = _$ParsedPlanUnmatchedImpl;

  factory _ParsedPlanUnmatched.fromJson(Map<String, dynamic> json) =
      _$ParsedPlanUnmatchedImpl.fromJson;

  @override
  int get dayNumber;
  @override
  String get rowName;

  /// Create a copy of ParsedPlanUnmatched
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ParsedPlanUnmatchedImplCopyWith<_$ParsedPlanUnmatchedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
