// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'routine_tag.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

RoutineTag _$RoutineTagFromJson(Map<String, dynamic> json) {
  return _RoutineTag.fromJson(json);
}

/// @nodoc
mixin _$RoutineTag {
  String get routineId => throw _privateConstructorUsedError;
  String get routineName => throw _privateConstructorUsedError;

  /// Serializes this RoutineTag to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RoutineTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RoutineTagCopyWith<RoutineTag> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RoutineTagCopyWith<$Res> {
  factory $RoutineTagCopyWith(
          RoutineTag value, $Res Function(RoutineTag) then) =
      _$RoutineTagCopyWithImpl<$Res, RoutineTag>;
  @useResult
  $Res call({String routineId, String routineName});
}

/// @nodoc
class _$RoutineTagCopyWithImpl<$Res, $Val extends RoutineTag>
    implements $RoutineTagCopyWith<$Res> {
  _$RoutineTagCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RoutineTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? routineId = null,
    Object? routineName = null,
  }) {
    return _then(_value.copyWith(
      routineId: null == routineId
          ? _value.routineId
          : routineId // ignore: cast_nullable_to_non_nullable
              as String,
      routineName: null == routineName
          ? _value.routineName
          : routineName // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$RoutineTagImplCopyWith<$Res>
    implements $RoutineTagCopyWith<$Res> {
  factory _$$RoutineTagImplCopyWith(
          _$RoutineTagImpl value, $Res Function(_$RoutineTagImpl) then) =
      __$$RoutineTagImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String routineId, String routineName});
}

/// @nodoc
class __$$RoutineTagImplCopyWithImpl<$Res>
    extends _$RoutineTagCopyWithImpl<$Res, _$RoutineTagImpl>
    implements _$$RoutineTagImplCopyWith<$Res> {
  __$$RoutineTagImplCopyWithImpl(
      _$RoutineTagImpl _value, $Res Function(_$RoutineTagImpl) _then)
      : super(_value, _then);

  /// Create a copy of RoutineTag
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? routineId = null,
    Object? routineName = null,
  }) {
    return _then(_$RoutineTagImpl(
      routineId: null == routineId
          ? _value.routineId
          : routineId // ignore: cast_nullable_to_non_nullable
              as String,
      routineName: null == routineName
          ? _value.routineName
          : routineName // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RoutineTagImpl implements _RoutineTag {
  const _$RoutineTagImpl({required this.routineId, required this.routineName});

  factory _$RoutineTagImpl.fromJson(Map<String, dynamic> json) =>
      _$$RoutineTagImplFromJson(json);

  @override
  final String routineId;
  @override
  final String routineName;

  @override
  String toString() {
    return 'RoutineTag(routineId: $routineId, routineName: $routineName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RoutineTagImpl &&
            (identical(other.routineId, routineId) ||
                other.routineId == routineId) &&
            (identical(other.routineName, routineName) ||
                other.routineName == routineName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, routineId, routineName);

  /// Create a copy of RoutineTag
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RoutineTagImplCopyWith<_$RoutineTagImpl> get copyWith =>
      __$$RoutineTagImplCopyWithImpl<_$RoutineTagImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RoutineTagImplToJson(
      this,
    );
  }
}

abstract class _RoutineTag implements RoutineTag {
  const factory _RoutineTag(
      {required final String routineId,
      required final String routineName}) = _$RoutineTagImpl;

  factory _RoutineTag.fromJson(Map<String, dynamic> json) =
      _$RoutineTagImpl.fromJson;

  @override
  String get routineId;
  @override
  String get routineName;

  /// Create a copy of RoutineTag
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RoutineTagImplCopyWith<_$RoutineTagImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
