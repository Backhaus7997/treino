// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'custom_exercise.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CustomExercise _$CustomExerciseFromJson(Map<String, dynamic> json) {
  return _CustomExercise.fromJson(json);
}

/// @nodoc
mixin _$CustomExercise {
  String get id => throw _privateConstructorUsedError;
  String get ownerId => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get muscleGroup => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  String? get videoUrl => throw _privateConstructorUsedError;
  int? get defaultRestSeconds => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this CustomExercise to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CustomExercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CustomExerciseCopyWith<CustomExercise> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CustomExerciseCopyWith<$Res> {
  factory $CustomExerciseCopyWith(
          CustomExercise value, $Res Function(CustomExercise) then) =
      _$CustomExerciseCopyWithImpl<$Res, CustomExercise>;
  @useResult
  $Res call(
      {String id,
      String ownerId,
      String name,
      String muscleGroup,
      String description,
      String? videoUrl,
      int? defaultRestSeconds,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$CustomExerciseCopyWithImpl<$Res, $Val extends CustomExercise>
    implements $CustomExerciseCopyWith<$Res> {
  _$CustomExerciseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CustomExercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ownerId = null,
    Object? name = null,
    Object? muscleGroup = null,
    Object? description = null,
    Object? videoUrl = freezed,
    Object? defaultRestSeconds = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      ownerId: null == ownerId
          ? _value.ownerId
          : ownerId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      videoUrl: freezed == videoUrl
          ? _value.videoUrl
          : videoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      defaultRestSeconds: freezed == defaultRestSeconds
          ? _value.defaultRestSeconds
          : defaultRestSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CustomExerciseImplCopyWith<$Res>
    implements $CustomExerciseCopyWith<$Res> {
  factory _$$CustomExerciseImplCopyWith(_$CustomExerciseImpl value,
          $Res Function(_$CustomExerciseImpl) then) =
      __$$CustomExerciseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String ownerId,
      String name,
      String muscleGroup,
      String description,
      String? videoUrl,
      int? defaultRestSeconds,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$CustomExerciseImplCopyWithImpl<$Res>
    extends _$CustomExerciseCopyWithImpl<$Res, _$CustomExerciseImpl>
    implements _$$CustomExerciseImplCopyWith<$Res> {
  __$$CustomExerciseImplCopyWithImpl(
      _$CustomExerciseImpl _value, $Res Function(_$CustomExerciseImpl) _then)
      : super(_value, _then);

  /// Create a copy of CustomExercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? ownerId = null,
    Object? name = null,
    Object? muscleGroup = null,
    Object? description = null,
    Object? videoUrl = freezed,
    Object? defaultRestSeconds = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$CustomExerciseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      ownerId: null == ownerId
          ? _value.ownerId
          : ownerId // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      videoUrl: freezed == videoUrl
          ? _value.videoUrl
          : videoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      defaultRestSeconds: freezed == defaultRestSeconds
          ? _value.defaultRestSeconds
          : defaultRestSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CustomExerciseImpl implements _CustomExercise {
  const _$CustomExerciseImpl(
      {required this.id,
      required this.ownerId,
      required this.name,
      this.muscleGroup = '',
      this.description = '',
      this.videoUrl,
      this.defaultRestSeconds,
      @TimestampConverter() required this.createdAt,
      @TimestampConverter() required this.updatedAt});

  factory _$CustomExerciseImpl.fromJson(Map<String, dynamic> json) =>
      _$$CustomExerciseImplFromJson(json);

  @override
  final String id;
  @override
  final String ownerId;
  @override
  final String name;
  @override
  @JsonKey()
  final String muscleGroup;
  @override
  @JsonKey()
  final String description;
  @override
  final String? videoUrl;
  @override
  final int? defaultRestSeconds;
  @override
  @TimestampConverter()
  final DateTime createdAt;
  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'CustomExercise(id: $id, ownerId: $ownerId, name: $name, muscleGroup: $muscleGroup, description: $description, videoUrl: $videoUrl, defaultRestSeconds: $defaultRestSeconds, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CustomExerciseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.ownerId, ownerId) || other.ownerId == ownerId) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.videoUrl, videoUrl) ||
                other.videoUrl == videoUrl) &&
            (identical(other.defaultRestSeconds, defaultRestSeconds) ||
                other.defaultRestSeconds == defaultRestSeconds) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, ownerId, name, muscleGroup,
      description, videoUrl, defaultRestSeconds, createdAt, updatedAt);

  /// Create a copy of CustomExercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CustomExerciseImplCopyWith<_$CustomExerciseImpl> get copyWith =>
      __$$CustomExerciseImplCopyWithImpl<_$CustomExerciseImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CustomExerciseImplToJson(
      this,
    );
  }
}

abstract class _CustomExercise implements CustomExercise {
  const factory _CustomExercise(
          {required final String id,
          required final String ownerId,
          required final String name,
          final String muscleGroup,
          final String description,
          final String? videoUrl,
          final int? defaultRestSeconds,
          @TimestampConverter() required final DateTime createdAt,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$CustomExerciseImpl;

  factory _CustomExercise.fromJson(Map<String, dynamic> json) =
      _$CustomExerciseImpl.fromJson;

  @override
  String get id;
  @override
  String get ownerId;
  @override
  String get name;
  @override
  String get muscleGroup;
  @override
  String get description;
  @override
  String? get videoUrl;
  @override
  int? get defaultRestSeconds;
  @override
  @TimestampConverter()
  DateTime get createdAt;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of CustomExercise
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CustomExerciseImplCopyWith<_$CustomExerciseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
