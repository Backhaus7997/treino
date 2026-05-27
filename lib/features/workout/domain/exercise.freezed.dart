// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Exercise _$ExerciseFromJson(Map<String, dynamic> json) {
  return _Exercise.fromJson(json);
}

/// @nodoc
mixin _$Exercise {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get muscleGroup => throw _privateConstructorUsedError;
  String get category =>
      throw _privateConstructorUsedError; // 'compound' | 'isolation' (free-form String, validated in seed)
  List<String>? get techniqueInstructions =>
      throw _privateConstructorUsedError; // null means "not yet authored" (ADR-1)
  String? get videoUrl => throw _privateConstructorUsedError;
  int? get defaultRestSeconds => throw _privateConstructorUsedError;
  List<String> get aliases => throw _privateConstructorUsedError;

  /// Serializes this Exercise to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Exercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ExerciseCopyWith<Exercise> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseCopyWith<$Res> {
  factory $ExerciseCopyWith(Exercise value, $Res Function(Exercise) then) =
      _$ExerciseCopyWithImpl<$Res, Exercise>;
  @useResult
  $Res call(
      {String id,
      String name,
      String muscleGroup,
      String category,
      List<String>? techniqueInstructions,
      String? videoUrl,
      int? defaultRestSeconds,
      List<String> aliases});
}

/// @nodoc
class _$ExerciseCopyWithImpl<$Res, $Val extends Exercise>
    implements $ExerciseCopyWith<$Res> {
  _$ExerciseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Exercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? muscleGroup = null,
    Object? category = null,
    Object? techniqueInstructions = freezed,
    Object? videoUrl = freezed,
    Object? defaultRestSeconds = freezed,
    Object? aliases = null,
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
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
      techniqueInstructions: freezed == techniqueInstructions
          ? _value.techniqueInstructions
          : techniqueInstructions // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      videoUrl: freezed == videoUrl
          ? _value.videoUrl
          : videoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      defaultRestSeconds: freezed == defaultRestSeconds
          ? _value.defaultRestSeconds
          : defaultRestSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      aliases: null == aliases
          ? _value.aliases
          : aliases // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseImplCopyWith<$Res>
    implements $ExerciseCopyWith<$Res> {
  factory _$$ExerciseImplCopyWith(
          _$ExerciseImpl value, $Res Function(_$ExerciseImpl) then) =
      __$$ExerciseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String muscleGroup,
      String category,
      List<String>? techniqueInstructions,
      String? videoUrl,
      int? defaultRestSeconds,
      List<String> aliases});
}

/// @nodoc
class __$$ExerciseImplCopyWithImpl<$Res>
    extends _$ExerciseCopyWithImpl<$Res, _$ExerciseImpl>
    implements _$$ExerciseImplCopyWith<$Res> {
  __$$ExerciseImplCopyWithImpl(
      _$ExerciseImpl _value, $Res Function(_$ExerciseImpl) _then)
      : super(_value, _then);

  /// Create a copy of Exercise
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? muscleGroup = null,
    Object? category = null,
    Object? techniqueInstructions = freezed,
    Object? videoUrl = freezed,
    Object? defaultRestSeconds = freezed,
    Object? aliases = null,
  }) {
    return _then(_$ExerciseImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      muscleGroup: null == muscleGroup
          ? _value.muscleGroup
          : muscleGroup // ignore: cast_nullable_to_non_nullable
              as String,
      category: null == category
          ? _value.category
          : category // ignore: cast_nullable_to_non_nullable
              as String,
      techniqueInstructions: freezed == techniqueInstructions
          ? _value._techniqueInstructions
          : techniqueInstructions // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      videoUrl: freezed == videoUrl
          ? _value.videoUrl
          : videoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      defaultRestSeconds: freezed == defaultRestSeconds
          ? _value.defaultRestSeconds
          : defaultRestSeconds // ignore: cast_nullable_to_non_nullable
              as int?,
      aliases: null == aliases
          ? _value._aliases
          : aliases // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExerciseImpl implements _Exercise {
  const _$ExerciseImpl(
      {required this.id,
      required this.name,
      required this.muscleGroup,
      required this.category,
      final List<String>? techniqueInstructions,
      this.videoUrl,
      this.defaultRestSeconds,
      final List<String> aliases = const <String>[]})
      : _techniqueInstructions = techniqueInstructions,
        _aliases = aliases;

  factory _$ExerciseImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExerciseImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String muscleGroup;
  @override
  final String category;
// 'compound' | 'isolation' (free-form String, validated in seed)
  final List<String>? _techniqueInstructions;
// 'compound' | 'isolation' (free-form String, validated in seed)
  @override
  List<String>? get techniqueInstructions {
    final value = _techniqueInstructions;
    if (value == null) return null;
    if (_techniqueInstructions is EqualUnmodifiableListView)
      return _techniqueInstructions;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

// null means "not yet authored" (ADR-1)
  @override
  final String? videoUrl;
  @override
  final int? defaultRestSeconds;
  final List<String> _aliases;
  @override
  @JsonKey()
  List<String> get aliases {
    if (_aliases is EqualUnmodifiableListView) return _aliases;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_aliases);
  }

  @override
  String toString() {
    return 'Exercise(id: $id, name: $name, muscleGroup: $muscleGroup, category: $category, techniqueInstructions: $techniqueInstructions, videoUrl: $videoUrl, defaultRestSeconds: $defaultRestSeconds, aliases: $aliases)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.muscleGroup, muscleGroup) ||
                other.muscleGroup == muscleGroup) &&
            (identical(other.category, category) ||
                other.category == category) &&
            const DeepCollectionEquality()
                .equals(other._techniqueInstructions, _techniqueInstructions) &&
            (identical(other.videoUrl, videoUrl) ||
                other.videoUrl == videoUrl) &&
            (identical(other.defaultRestSeconds, defaultRestSeconds) ||
                other.defaultRestSeconds == defaultRestSeconds) &&
            const DeepCollectionEquality().equals(other._aliases, _aliases));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      muscleGroup,
      category,
      const DeepCollectionEquality().hash(_techniqueInstructions),
      videoUrl,
      defaultRestSeconds,
      const DeepCollectionEquality().hash(_aliases));

  /// Create a copy of Exercise
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseImplCopyWith<_$ExerciseImpl> get copyWith =>
      __$$ExerciseImplCopyWithImpl<_$ExerciseImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExerciseImplToJson(
      this,
    );
  }
}

abstract class _Exercise implements Exercise {
  const factory _Exercise(
      {required final String id,
      required final String name,
      required final String muscleGroup,
      required final String category,
      final List<String>? techniqueInstructions,
      final String? videoUrl,
      final int? defaultRestSeconds,
      final List<String> aliases}) = _$ExerciseImpl;

  factory _Exercise.fromJson(Map<String, dynamic> json) =
      _$ExerciseImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get muscleGroup;
  @override
  String
      get category; // 'compound' | 'isolation' (free-form String, validated in seed)
  @override
  List<String>?
      get techniqueInstructions; // null means "not yet authored" (ADR-1)
  @override
  String? get videoUrl;
  @override
  int? get defaultRestSeconds;
  @override
  List<String> get aliases;

  /// Create a copy of Exercise
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ExerciseImplCopyWith<_$ExerciseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
