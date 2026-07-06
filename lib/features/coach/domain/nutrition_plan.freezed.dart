// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'nutrition_plan.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

FoodOption _$FoodOptionFromJson(Map<String, dynamic> json) {
  return _FoodOption.fromJson(json);
}

/// @nodoc
mixin _$FoodOption {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get quantity => throw _privateConstructorUsedError;
  String? get unit => throw _privateConstructorUsedError;
  String? get notes => throw _privateConstructorUsedError;

  /// Serializes this FoodOption to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FoodOption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FoodOptionCopyWith<FoodOption> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FoodOptionCopyWith<$Res> {
  factory $FoodOptionCopyWith(
          FoodOption value, $Res Function(FoodOption) then) =
      _$FoodOptionCopyWithImpl<$Res, FoodOption>;
  @useResult
  $Res call(
      {String id, String name, String? quantity, String? unit, String? notes});
}

/// @nodoc
class _$FoodOptionCopyWithImpl<$Res, $Val extends FoodOption>
    implements $FoodOptionCopyWith<$Res> {
  _$FoodOptionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FoodOption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? quantity = freezed,
    Object? unit = freezed,
    Object? notes = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      quantity: freezed == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as String?,
      unit: freezed == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FoodOptionImplCopyWith<$Res>
    implements $FoodOptionCopyWith<$Res> {
  factory _$$FoodOptionImplCopyWith(
          _$FoodOptionImpl value, $Res Function(_$FoodOptionImpl) then) =
      __$$FoodOptionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id, String name, String? quantity, String? unit, String? notes});
}

/// @nodoc
class __$$FoodOptionImplCopyWithImpl<$Res>
    extends _$FoodOptionCopyWithImpl<$Res, _$FoodOptionImpl>
    implements _$$FoodOptionImplCopyWith<$Res> {
  __$$FoodOptionImplCopyWithImpl(
      _$FoodOptionImpl _value, $Res Function(_$FoodOptionImpl) _then)
      : super(_value, _then);

  /// Create a copy of FoodOption
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? quantity = freezed,
    Object? unit = freezed,
    Object? notes = freezed,
  }) {
    return _then(_$FoodOptionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      quantity: freezed == quantity
          ? _value.quantity
          : quantity // ignore: cast_nullable_to_non_nullable
              as String?,
      unit: freezed == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String?,
      notes: freezed == notes
          ? _value.notes
          : notes // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FoodOptionImpl implements _FoodOption {
  const _$FoodOptionImpl(
      {required this.id,
      required this.name,
      this.quantity,
      this.unit,
      this.notes});

  factory _$FoodOptionImpl.fromJson(Map<String, dynamic> json) =>
      _$$FoodOptionImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? quantity;
  @override
  final String? unit;
  @override
  final String? notes;

  @override
  String toString() {
    return 'FoodOption(id: $id, name: $name, quantity: $quantity, unit: $unit, notes: $notes)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FoodOptionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.quantity, quantity) ||
                other.quantity == quantity) &&
            (identical(other.unit, unit) || other.unit == unit) &&
            (identical(other.notes, notes) || other.notes == notes));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, quantity, unit, notes);

  /// Create a copy of FoodOption
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FoodOptionImplCopyWith<_$FoodOptionImpl> get copyWith =>
      __$$FoodOptionImplCopyWithImpl<_$FoodOptionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FoodOptionImplToJson(
      this,
    );
  }
}

abstract class _FoodOption implements FoodOption {
  const factory _FoodOption(
      {required final String id,
      required final String name,
      final String? quantity,
      final String? unit,
      final String? notes}) = _$FoodOptionImpl;

  factory _FoodOption.fromJson(Map<String, dynamic> json) =
      _$FoodOptionImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get quantity;
  @override
  String? get unit;
  @override
  String? get notes;

  /// Create a copy of FoodOption
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FoodOptionImplCopyWith<_$FoodOptionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

FoodGroup _$FoodGroupFromJson(Map<String, dynamic> json) {
  return _FoodGroup.fromJson(json);
}

/// @nodoc
mixin _$FoodGroup {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  SelectionMode get selectionMode => throw _privateConstructorUsedError;
  List<FoodOption> get options => throw _privateConstructorUsedError;

  /// Serializes this FoodGroup to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FoodGroup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FoodGroupCopyWith<FoodGroup> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FoodGroupCopyWith<$Res> {
  factory $FoodGroupCopyWith(FoodGroup value, $Res Function(FoodGroup) then) =
      _$FoodGroupCopyWithImpl<$Res, FoodGroup>;
  @useResult
  $Res call(
      {String id,
      String name,
      SelectionMode selectionMode,
      List<FoodOption> options});
}

/// @nodoc
class _$FoodGroupCopyWithImpl<$Res, $Val extends FoodGroup>
    implements $FoodGroupCopyWith<$Res> {
  _$FoodGroupCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FoodGroup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? selectionMode = null,
    Object? options = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      selectionMode: null == selectionMode
          ? _value.selectionMode
          : selectionMode // ignore: cast_nullable_to_non_nullable
              as SelectionMode,
      options: null == options
          ? _value.options
          : options // ignore: cast_nullable_to_non_nullable
              as List<FoodOption>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FoodGroupImplCopyWith<$Res>
    implements $FoodGroupCopyWith<$Res> {
  factory _$$FoodGroupImplCopyWith(
          _$FoodGroupImpl value, $Res Function(_$FoodGroupImpl) then) =
      __$$FoodGroupImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      SelectionMode selectionMode,
      List<FoodOption> options});
}

/// @nodoc
class __$$FoodGroupImplCopyWithImpl<$Res>
    extends _$FoodGroupCopyWithImpl<$Res, _$FoodGroupImpl>
    implements _$$FoodGroupImplCopyWith<$Res> {
  __$$FoodGroupImplCopyWithImpl(
      _$FoodGroupImpl _value, $Res Function(_$FoodGroupImpl) _then)
      : super(_value, _then);

  /// Create a copy of FoodGroup
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? selectionMode = null,
    Object? options = null,
  }) {
    return _then(_$FoodGroupImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      selectionMode: null == selectionMode
          ? _value.selectionMode
          : selectionMode // ignore: cast_nullable_to_non_nullable
              as SelectionMode,
      options: null == options
          ? _value._options
          : options // ignore: cast_nullable_to_non_nullable
              as List<FoodOption>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FoodGroupImpl implements _FoodGroup {
  const _$FoodGroupImpl(
      {required this.id,
      required this.name,
      required this.selectionMode,
      required final List<FoodOption> options})
      : _options = options;

  factory _$FoodGroupImpl.fromJson(Map<String, dynamic> json) =>
      _$$FoodGroupImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final SelectionMode selectionMode;
  final List<FoodOption> _options;
  @override
  List<FoodOption> get options {
    if (_options is EqualUnmodifiableListView) return _options;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_options);
  }

  @override
  String toString() {
    return 'FoodGroup(id: $id, name: $name, selectionMode: $selectionMode, options: $options)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FoodGroupImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.selectionMode, selectionMode) ||
                other.selectionMode == selectionMode) &&
            const DeepCollectionEquality().equals(other._options, _options));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, selectionMode,
      const DeepCollectionEquality().hash(_options));

  /// Create a copy of FoodGroup
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FoodGroupImplCopyWith<_$FoodGroupImpl> get copyWith =>
      __$$FoodGroupImplCopyWithImpl<_$FoodGroupImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FoodGroupImplToJson(
      this,
    );
  }
}

abstract class _FoodGroup implements FoodGroup {
  const factory _FoodGroup(
      {required final String id,
      required final String name,
      required final SelectionMode selectionMode,
      required final List<FoodOption> options}) = _$FoodGroupImpl;

  factory _FoodGroup.fromJson(Map<String, dynamic> json) =
      _$FoodGroupImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  SelectionMode get selectionMode;
  @override
  List<FoodOption> get options;

  /// Create a copy of FoodGroup
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FoodGroupImplCopyWith<_$FoodGroupImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Meal _$MealFromJson(Map<String, dynamic> json) {
  return _Meal.fromJson(json);
}

/// @nodoc
mixin _$Meal {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get time => throw _privateConstructorUsedError;
  List<FoodGroup> get groups => throw _privateConstructorUsedError;

  /// Serializes this Meal to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Meal
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MealCopyWith<Meal> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MealCopyWith<$Res> {
  factory $MealCopyWith(Meal value, $Res Function(Meal) then) =
      _$MealCopyWithImpl<$Res, Meal>;
  @useResult
  $Res call({String id, String name, String? time, List<FoodGroup> groups});
}

/// @nodoc
class _$MealCopyWithImpl<$Res, $Val extends Meal>
    implements $MealCopyWith<$Res> {
  _$MealCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Meal
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? time = freezed,
    Object? groups = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      time: freezed == time
          ? _value.time
          : time // ignore: cast_nullable_to_non_nullable
              as String?,
      groups: null == groups
          ? _value.groups
          : groups // ignore: cast_nullable_to_non_nullable
              as List<FoodGroup>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MealImplCopyWith<$Res> implements $MealCopyWith<$Res> {
  factory _$$MealImplCopyWith(
          _$MealImpl value, $Res Function(_$MealImpl) then) =
      __$$MealImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String name, String? time, List<FoodGroup> groups});
}

/// @nodoc
class __$$MealImplCopyWithImpl<$Res>
    extends _$MealCopyWithImpl<$Res, _$MealImpl>
    implements _$$MealImplCopyWith<$Res> {
  __$$MealImplCopyWithImpl(_$MealImpl _value, $Res Function(_$MealImpl) _then)
      : super(_value, _then);

  /// Create a copy of Meal
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? time = freezed,
    Object? groups = null,
  }) {
    return _then(_$MealImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      time: freezed == time
          ? _value.time
          : time // ignore: cast_nullable_to_non_nullable
              as String?,
      groups: null == groups
          ? _value._groups
          : groups // ignore: cast_nullable_to_non_nullable
              as List<FoodGroup>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MealImpl implements _Meal {
  const _$MealImpl(
      {required this.id,
      required this.name,
      this.time,
      required final List<FoodGroup> groups})
      : _groups = groups;

  factory _$MealImpl.fromJson(Map<String, dynamic> json) =>
      _$$MealImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? time;
  final List<FoodGroup> _groups;
  @override
  List<FoodGroup> get groups {
    if (_groups is EqualUnmodifiableListView) return _groups;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_groups);
  }

  @override
  String toString() {
    return 'Meal(id: $id, name: $name, time: $time, groups: $groups)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MealImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.time, time) || other.time == time) &&
            const DeepCollectionEquality().equals(other._groups, _groups));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, name, time,
      const DeepCollectionEquality().hash(_groups));

  /// Create a copy of Meal
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MealImplCopyWith<_$MealImpl> get copyWith =>
      __$$MealImplCopyWithImpl<_$MealImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MealImplToJson(
      this,
    );
  }
}

abstract class _Meal implements Meal {
  const factory _Meal(
      {required final String id,
      required final String name,
      final String? time,
      required final List<FoodGroup> groups}) = _$MealImpl;

  factory _Meal.fromJson(Map<String, dynamic> json) = _$MealImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get time;
  @override
  List<FoodGroup> get groups;

  /// Create a copy of Meal
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MealImplCopyWith<_$MealImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

NutritionPlan _$NutritionPlanFromJson(Map<String, dynamic> json) {
  return _NutritionPlan.fromJson(json);
}

/// @nodoc
mixin _$NutritionPlan {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  List<Meal> get meals => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this NutritionPlan to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NutritionPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NutritionPlanCopyWith<NutritionPlan> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NutritionPlanCopyWith<$Res> {
  factory $NutritionPlanCopyWith(
          NutritionPlan value, $Res Function(NutritionPlan) then) =
      _$NutritionPlanCopyWithImpl<$Res, NutritionPlan>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String title,
      List<Meal> meals,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$NutritionPlanCopyWithImpl<$Res, $Val extends NutritionPlan>
    implements $NutritionPlanCopyWith<$Res> {
  _$NutritionPlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NutritionPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? title = null,
    Object? meals = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      meals: null == meals
          ? _value.meals
          : meals // ignore: cast_nullable_to_non_nullable
              as List<Meal>,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NutritionPlanImplCopyWith<$Res>
    implements $NutritionPlanCopyWith<$Res> {
  factory _$$NutritionPlanImplCopyWith(
          _$NutritionPlanImpl value, $Res Function(_$NutritionPlanImpl) then) =
      __$$NutritionPlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String title,
      List<Meal> meals,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$NutritionPlanImplCopyWithImpl<$Res>
    extends _$NutritionPlanCopyWithImpl<$Res, _$NutritionPlanImpl>
    implements _$$NutritionPlanImplCopyWith<$Res> {
  __$$NutritionPlanImplCopyWithImpl(
      _$NutritionPlanImpl _value, $Res Function(_$NutritionPlanImpl) _then)
      : super(_value, _then);

  /// Create a copy of NutritionPlan
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? title = null,
    Object? meals = null,
    Object? updatedAt = null,
  }) {
    return _then(_$NutritionPlanImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      meals: null == meals
          ? _value._meals
          : meals // ignore: cast_nullable_to_non_nullable
              as List<Meal>,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NutritionPlanImpl implements _NutritionPlan {
  const _$NutritionPlanImpl(
      {required this.id,
      required this.trainerId,
      required this.athleteId,
      required this.title,
      required final List<Meal> meals,
      @TimestampConverter() required this.updatedAt})
      : _meals = meals;

  factory _$NutritionPlanImpl.fromJson(Map<String, dynamic> json) =>
      _$$NutritionPlanImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final String title;
  final List<Meal> _meals;
  @override
  List<Meal> get meals {
    if (_meals is EqualUnmodifiableListView) return _meals;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_meals);
  }

  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'NutritionPlan(id: $id, trainerId: $trainerId, athleteId: $athleteId, title: $title, meals: $meals, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NutritionPlanImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other._meals, _meals) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, trainerId, athleteId, title,
      const DeepCollectionEquality().hash(_meals), updatedAt);

  /// Create a copy of NutritionPlan
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NutritionPlanImplCopyWith<_$NutritionPlanImpl> get copyWith =>
      __$$NutritionPlanImplCopyWithImpl<_$NutritionPlanImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NutritionPlanImplToJson(
      this,
    );
  }
}

abstract class _NutritionPlan implements NutritionPlan {
  const factory _NutritionPlan(
          {required final String id,
          required final String trainerId,
          required final String athleteId,
          required final String title,
          required final List<Meal> meals,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$NutritionPlanImpl;

  factory _NutritionPlan.fromJson(Map<String, dynamic> json) =
      _$NutritionPlanImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  String get title;
  @override
  List<Meal> get meals;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of NutritionPlan
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NutritionPlanImplCopyWith<_$NutritionPlanImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
