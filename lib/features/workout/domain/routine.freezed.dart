// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Routine _$RoutineFromJson(Map<String, dynamic> json) {
  return _Routine.fromJson(json);
}

/// @nodoc
mixin _$Routine {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get split =>
      throw _privateConstructorUsedError; // 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form)
  ExperienceLevel get level => throw _privateConstructorUsedError;
  List<RoutineDay> get days =>
      throw _privateConstructorUsedError; // empty list valid (spec SCENARIO-052)
  int? get estimatedMinutesPerDay => throw _privateConstructorUsedError;
  String? get imageUrl =>
      throw _privateConstructorUsedError; // null for seed PR 2 (ADR-3); future Storage URL
  RoutineSource get source => throw _privateConstructorUsedError;
  String? get assignedBy =>
      throw _privateConstructorUsedError; // trainerId — solo cuando source == trainerAssigned
  String? get assignedTo =>
      throw _privateConstructorUsedError; // athleteId — solo en planes privados asignados
  RoutineVisibility get visibility => throw _privateConstructorUsedError;

  /// Serializes this Routine to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Routine
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoutineCopyWith<Routine> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoutineCopyWith<$Res> {
  factory $RoutineCopyWith(Routine value, $Res Function(Routine) then) =
      _$RoutineCopyWithImpl<$Res, Routine>;
  @useResult
  $Res call(
      {String id,
      String name,
      String split,
      ExperienceLevel level,
      List<RoutineDay> days,
      int? estimatedMinutesPerDay,
      String? imageUrl,
      RoutineSource source,
      String? assignedBy,
      String? assignedTo,
      RoutineVisibility visibility});
}

/// @nodoc
class _$RoutineCopyWithImpl<$Res, $Val extends Routine>
    implements $RoutineCopyWith<$Res> {
  _$RoutineCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Routine
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? split = null,
    Object? level = null,
    Object? days = null,
    Object? estimatedMinutesPerDay = freezed,
    Object? imageUrl = freezed,
    Object? source = null,
    Object? assignedBy = freezed,
    Object? assignedTo = freezed,
    Object? visibility = null,
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
      split: null == split
          ? _value.split
          : split // ignore: cast_nullable_to_non_nullable
              as String,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel,
      days: null == days
          ? _value.days
          : days // ignore: cast_nullable_to_non_nullable
              as List<RoutineDay>,
      estimatedMinutesPerDay: freezed == estimatedMinutesPerDay
          ? _value.estimatedMinutesPerDay
          : estimatedMinutesPerDay // ignore: cast_nullable_to_non_nullable
              as int?,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as RoutineSource,
      assignedBy: freezed == assignedBy
          ? _value.assignedBy
          : assignedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedTo: freezed == assignedTo
          ? _value.assignedTo
          : assignedTo // ignore: cast_nullable_to_non_nullable
              as String?,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as RoutineVisibility,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RoutineImplCopyWith<$Res> implements $RoutineCopyWith<$Res> {
  factory _$$RoutineImplCopyWith(
          _$RoutineImpl value, $Res Function(_$RoutineImpl) then) =
      __$$RoutineImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String split,
      ExperienceLevel level,
      List<RoutineDay> days,
      int? estimatedMinutesPerDay,
      String? imageUrl,
      RoutineSource source,
      String? assignedBy,
      String? assignedTo,
      RoutineVisibility visibility});
}

/// @nodoc
class __$$RoutineImplCopyWithImpl<$Res>
    extends _$RoutineCopyWithImpl<$Res, _$RoutineImpl>
    implements _$$RoutineImplCopyWith<$Res> {
  __$$RoutineImplCopyWithImpl(
      _$RoutineImpl _value, $Res Function(_$RoutineImpl) _then)
      : super(_value, _then);

  /// Create a copy of Routine
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? split = null,
    Object? level = null,
    Object? days = null,
    Object? estimatedMinutesPerDay = freezed,
    Object? imageUrl = freezed,
    Object? source = null,
    Object? assignedBy = freezed,
    Object? assignedTo = freezed,
    Object? visibility = null,
  }) {
    return _then(_$RoutineImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      split: null == split
          ? _value.split
          : split // ignore: cast_nullable_to_non_nullable
              as String,
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as ExperienceLevel,
      days: null == days
          ? _value._days
          : days // ignore: cast_nullable_to_non_nullable
              as List<RoutineDay>,
      estimatedMinutesPerDay: freezed == estimatedMinutesPerDay
          ? _value.estimatedMinutesPerDay
          : estimatedMinutesPerDay // ignore: cast_nullable_to_non_nullable
              as int?,
      imageUrl: freezed == imageUrl
          ? _value.imageUrl
          : imageUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as RoutineSource,
      assignedBy: freezed == assignedBy
          ? _value.assignedBy
          : assignedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedTo: freezed == assignedTo
          ? _value.assignedTo
          : assignedTo // ignore: cast_nullable_to_non_nullable
              as String?,
      visibility: null == visibility
          ? _value.visibility
          : visibility // ignore: cast_nullable_to_non_nullable
              as RoutineVisibility,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RoutineImpl implements _Routine {
  const _$RoutineImpl(
      {required this.id,
      required this.name,
      required this.split,
      required this.level,
      required final List<RoutineDay> days,
      this.estimatedMinutesPerDay,
      this.imageUrl,
      this.source = RoutineSource.system,
      this.assignedBy,
      this.assignedTo,
      this.visibility = RoutineVisibility.public})
      : _days = days;

  factory _$RoutineImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoutineImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String split;
// 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form)
  @override
  final ExperienceLevel level;
  final List<RoutineDay> _days;
  @override
  List<RoutineDay> get days {
    if (_days is EqualUnmodifiableListView) return _days;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_days);
  }

// empty list valid (spec SCENARIO-052)
  @override
  final int? estimatedMinutesPerDay;
  @override
  final String? imageUrl;
// null for seed PR 2 (ADR-3); future Storage URL
  @override
  @JsonKey()
  final RoutineSource source;
  @override
  final String? assignedBy;
// trainerId — solo cuando source == trainerAssigned
  @override
  final String? assignedTo;
// athleteId — solo en planes privados asignados
  @override
  @JsonKey()
  final RoutineVisibility visibility;

  @override
  String toString() {
    return 'Routine(id: $id, name: $name, split: $split, level: $level, days: $days, estimatedMinutesPerDay: $estimatedMinutesPerDay, imageUrl: $imageUrl, source: $source, assignedBy: $assignedBy, assignedTo: $assignedTo, visibility: $visibility)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoutineImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.split, split) || other.split == split) &&
            (identical(other.level, level) || other.level == level) &&
            const DeepCollectionEquality().equals(other._days, _days) &&
            (identical(other.estimatedMinutesPerDay, estimatedMinutesPerDay) ||
                other.estimatedMinutesPerDay == estimatedMinutesPerDay) &&
            (identical(other.imageUrl, imageUrl) ||
                other.imageUrl == imageUrl) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.assignedBy, assignedBy) ||
                other.assignedBy == assignedBy) &&
            (identical(other.assignedTo, assignedTo) ||
                other.assignedTo == assignedTo) &&
            (identical(other.visibility, visibility) ||
                other.visibility == visibility));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      split,
      level,
      const DeepCollectionEquality().hash(_days),
      estimatedMinutesPerDay,
      imageUrl,
      source,
      assignedBy,
      assignedTo,
      visibility);

  /// Create a copy of Routine
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoutineImplCopyWith<_$RoutineImpl> get copyWith =>
      __$$RoutineImplCopyWithImpl<_$RoutineImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoutineImplToJson(
      this,
    );
  }
}

abstract class _Routine implements Routine {
  const factory _Routine(
      {required final String id,
      required final String name,
      required final String split,
      required final ExperienceLevel level,
      required final List<RoutineDay> days,
      final int? estimatedMinutesPerDay,
      final String? imageUrl,
      final RoutineSource source,
      final String? assignedBy,
      final String? assignedTo,
      final RoutineVisibility visibility}) = _$RoutineImpl;

  factory _Routine.fromJson(Map<String, dynamic> json) = _$RoutineImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get split; // 'PPL' | 'Full Body' | 'Upper/Lower' | ... (free-form)
  @override
  ExperienceLevel get level;
  @override
  List<RoutineDay> get days; // empty list valid (spec SCENARIO-052)
  @override
  int? get estimatedMinutesPerDay;
  @override
  String? get imageUrl; // null for seed PR 2 (ADR-3); future Storage URL
  @override
  RoutineSource get source;
  @override
  String? get assignedBy; // trainerId — solo cuando source == trainerAssigned
  @override
  String? get assignedTo; // athleteId — solo en planes privados asignados
  @override
  RoutineVisibility get visibility;

  /// Create a copy of Routine
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoutineImplCopyWith<_$RoutineImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
