// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'verified_email.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

VerifiedEmail _$VerifiedEmailFromJson(Map<String, dynamic> json) {
  return _VerifiedEmail.fromJson(json);
}

/// @nodoc
mixin _$VerifiedEmail {
// `''` y no `required`: una entrada sin mail no confirma nada (el gate la
// lee como "no verificado"), pero tampoco puede tirar el parseo y dejar el
// perfil entero en `/profile-unavailable`.
  String get email => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get verifiedAt => throw _privateConstructorUsedError;

  /// Serializes this VerifiedEmail to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of VerifiedEmail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $VerifiedEmailCopyWith<VerifiedEmail> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VerifiedEmailCopyWith<$Res> {
  factory $VerifiedEmailCopyWith(
          VerifiedEmail value, $Res Function(VerifiedEmail) then) =
      _$VerifiedEmailCopyWithImpl<$Res, VerifiedEmail>;
  @useResult
  $Res call({String email, @TimestampConverter() DateTime? verifiedAt});
}

/// @nodoc
class _$VerifiedEmailCopyWithImpl<$Res, $Val extends VerifiedEmail>
    implements $VerifiedEmailCopyWith<$Res> {
  _$VerifiedEmailCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of VerifiedEmail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? verifiedAt = freezed,
  }) {
    return _then(_value.copyWith(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      verifiedAt: freezed == verifiedAt
          ? _value.verifiedAt
          : verifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$VerifiedEmailImplCopyWith<$Res>
    implements $VerifiedEmailCopyWith<$Res> {
  factory _$$VerifiedEmailImplCopyWith(
          _$VerifiedEmailImpl value, $Res Function(_$VerifiedEmailImpl) then) =
      __$$VerifiedEmailImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String email, @TimestampConverter() DateTime? verifiedAt});
}

/// @nodoc
class __$$VerifiedEmailImplCopyWithImpl<$Res>
    extends _$VerifiedEmailCopyWithImpl<$Res, _$VerifiedEmailImpl>
    implements _$$VerifiedEmailImplCopyWith<$Res> {
  __$$VerifiedEmailImplCopyWithImpl(
      _$VerifiedEmailImpl _value, $Res Function(_$VerifiedEmailImpl) _then)
      : super(_value, _then);

  /// Create a copy of VerifiedEmail
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? verifiedAt = freezed,
  }) {
    return _then(_$VerifiedEmailImpl(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      verifiedAt: freezed == verifiedAt
          ? _value.verifiedAt
          : verifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$VerifiedEmailImpl implements _VerifiedEmail {
  const _$VerifiedEmailImpl(
      {this.email = '', @TimestampConverter() this.verifiedAt});

  factory _$VerifiedEmailImpl.fromJson(Map<String, dynamic> json) =>
      _$$VerifiedEmailImplFromJson(json);

// `''` y no `required`: una entrada sin mail no confirma nada (el gate la
// lee como "no verificado"), pero tampoco puede tirar el parseo y dejar el
// perfil entero en `/profile-unavailable`.
  @override
  @JsonKey()
  final String email;
  @override
  @TimestampConverter()
  final DateTime? verifiedAt;

  @override
  String toString() {
    return 'VerifiedEmail(email: $email, verifiedAt: $verifiedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VerifiedEmailImpl &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.verifiedAt, verifiedAt) ||
                other.verifiedAt == verifiedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, email, verifiedAt);

  /// Create a copy of VerifiedEmail
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$VerifiedEmailImplCopyWith<_$VerifiedEmailImpl> get copyWith =>
      __$$VerifiedEmailImplCopyWithImpl<_$VerifiedEmailImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$VerifiedEmailImplToJson(
      this,
    );
  }
}

abstract class _VerifiedEmail implements VerifiedEmail {
  const factory _VerifiedEmail(
      {final String email,
      @TimestampConverter() final DateTime? verifiedAt}) = _$VerifiedEmailImpl;

  factory _VerifiedEmail.fromJson(Map<String, dynamic> json) =
      _$VerifiedEmailImpl.fromJson;

// `''` y no `required`: una entrada sin mail no confirma nada (el gate la
// lee como "no verificado"), pero tampoco puede tirar el parseo y dejar el
// perfil entero en `/profile-unavailable`.
  @override
  String get email;
  @override
  @TimestampConverter()
  DateTime? get verifiedAt;

  /// Create a copy of VerifiedEmail
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$VerifiedEmailImplCopyWith<_$VerifiedEmailImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
