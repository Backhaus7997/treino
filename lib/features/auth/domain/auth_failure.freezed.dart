// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'auth_failure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$AuthFailure {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AuthFailureCopyWith<$Res> {
  factory $AuthFailureCopyWith(
          AuthFailure value, $Res Function(AuthFailure) then) =
      _$AuthFailureCopyWithImpl<$Res, AuthFailure>;
}

/// @nodoc
class _$AuthFailureCopyWithImpl<$Res, $Val extends AuthFailure>
    implements $AuthFailureCopyWith<$Res> {
  _$AuthFailureCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$InvalidEmailImplCopyWith<$Res> {
  factory _$$InvalidEmailImplCopyWith(
          _$InvalidEmailImpl value, $Res Function(_$InvalidEmailImpl) then) =
      __$$InvalidEmailImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$InvalidEmailImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$InvalidEmailImpl>
    implements _$$InvalidEmailImplCopyWith<$Res> {
  __$$InvalidEmailImplCopyWithImpl(
      _$InvalidEmailImpl _value, $Res Function(_$InvalidEmailImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$InvalidEmailImpl extends _InvalidEmail {
  const _$InvalidEmailImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.invalidEmail()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$InvalidEmailImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return invalidEmail();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return invalidEmail?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (invalidEmail != null) {
      return invalidEmail();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return invalidEmail(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return invalidEmail?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (invalidEmail != null) {
      return invalidEmail(this);
    }
    return orElse();
  }
}

abstract class _InvalidEmail extends AuthFailure {
  const factory _InvalidEmail() = _$InvalidEmailImpl;
  const _InvalidEmail._() : super._();
}

/// @nodoc
abstract class _$$UserDisabledImplCopyWith<$Res> {
  factory _$$UserDisabledImplCopyWith(
          _$UserDisabledImpl value, $Res Function(_$UserDisabledImpl) then) =
      __$$UserDisabledImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$UserDisabledImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$UserDisabledImpl>
    implements _$$UserDisabledImplCopyWith<$Res> {
  __$$UserDisabledImplCopyWithImpl(
      _$UserDisabledImpl _value, $Res Function(_$UserDisabledImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$UserDisabledImpl extends _UserDisabled {
  const _$UserDisabledImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.userDisabled()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$UserDisabledImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return userDisabled();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return userDisabled?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (userDisabled != null) {
      return userDisabled();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return userDisabled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return userDisabled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (userDisabled != null) {
      return userDisabled(this);
    }
    return orElse();
  }
}

abstract class _UserDisabled extends AuthFailure {
  const factory _UserDisabled() = _$UserDisabledImpl;
  const _UserDisabled._() : super._();
}

/// @nodoc
abstract class _$$UserNotFoundImplCopyWith<$Res> {
  factory _$$UserNotFoundImplCopyWith(
          _$UserNotFoundImpl value, $Res Function(_$UserNotFoundImpl) then) =
      __$$UserNotFoundImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$UserNotFoundImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$UserNotFoundImpl>
    implements _$$UserNotFoundImplCopyWith<$Res> {
  __$$UserNotFoundImplCopyWithImpl(
      _$UserNotFoundImpl _value, $Res Function(_$UserNotFoundImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$UserNotFoundImpl extends _UserNotFound {
  const _$UserNotFoundImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.userNotFound()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$UserNotFoundImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return userNotFound();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return userNotFound?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (userNotFound != null) {
      return userNotFound();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return userNotFound(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return userNotFound?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (userNotFound != null) {
      return userNotFound(this);
    }
    return orElse();
  }
}

abstract class _UserNotFound extends AuthFailure {
  const factory _UserNotFound() = _$UserNotFoundImpl;
  const _UserNotFound._() : super._();
}

/// @nodoc
abstract class _$$WrongPasswordImplCopyWith<$Res> {
  factory _$$WrongPasswordImplCopyWith(
          _$WrongPasswordImpl value, $Res Function(_$WrongPasswordImpl) then) =
      __$$WrongPasswordImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$WrongPasswordImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$WrongPasswordImpl>
    implements _$$WrongPasswordImplCopyWith<$Res> {
  __$$WrongPasswordImplCopyWithImpl(
      _$WrongPasswordImpl _value, $Res Function(_$WrongPasswordImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$WrongPasswordImpl extends _WrongPassword {
  const _$WrongPasswordImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.wrongPassword()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$WrongPasswordImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return wrongPassword();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return wrongPassword?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (wrongPassword != null) {
      return wrongPassword();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return wrongPassword(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return wrongPassword?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (wrongPassword != null) {
      return wrongPassword(this);
    }
    return orElse();
  }
}

abstract class _WrongPassword extends AuthFailure {
  const factory _WrongPassword() = _$WrongPasswordImpl;
  const _WrongPassword._() : super._();
}

/// @nodoc
abstract class _$$EmailAlreadyInUseImplCopyWith<$Res> {
  factory _$$EmailAlreadyInUseImplCopyWith(_$EmailAlreadyInUseImpl value,
          $Res Function(_$EmailAlreadyInUseImpl) then) =
      __$$EmailAlreadyInUseImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$EmailAlreadyInUseImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$EmailAlreadyInUseImpl>
    implements _$$EmailAlreadyInUseImplCopyWith<$Res> {
  __$$EmailAlreadyInUseImplCopyWithImpl(_$EmailAlreadyInUseImpl _value,
      $Res Function(_$EmailAlreadyInUseImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$EmailAlreadyInUseImpl extends _EmailAlreadyInUse {
  const _$EmailAlreadyInUseImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.emailAlreadyInUse()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$EmailAlreadyInUseImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return emailAlreadyInUse();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return emailAlreadyInUse?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (emailAlreadyInUse != null) {
      return emailAlreadyInUse();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return emailAlreadyInUse(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return emailAlreadyInUse?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (emailAlreadyInUse != null) {
      return emailAlreadyInUse(this);
    }
    return orElse();
  }
}

abstract class _EmailAlreadyInUse extends AuthFailure {
  const factory _EmailAlreadyInUse() = _$EmailAlreadyInUseImpl;
  const _EmailAlreadyInUse._() : super._();
}

/// @nodoc
abstract class _$$WeakPasswordImplCopyWith<$Res> {
  factory _$$WeakPasswordImplCopyWith(
          _$WeakPasswordImpl value, $Res Function(_$WeakPasswordImpl) then) =
      __$$WeakPasswordImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$WeakPasswordImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$WeakPasswordImpl>
    implements _$$WeakPasswordImplCopyWith<$Res> {
  __$$WeakPasswordImplCopyWithImpl(
      _$WeakPasswordImpl _value, $Res Function(_$WeakPasswordImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$WeakPasswordImpl extends _WeakPassword {
  const _$WeakPasswordImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.weakPassword()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$WeakPasswordImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return weakPassword();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return weakPassword?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (weakPassword != null) {
      return weakPassword();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return weakPassword(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return weakPassword?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (weakPassword != null) {
      return weakPassword(this);
    }
    return orElse();
  }
}

abstract class _WeakPassword extends AuthFailure {
  const factory _WeakPassword() = _$WeakPasswordImpl;
  const _WeakPassword._() : super._();
}

/// @nodoc
abstract class _$$TooManyRequestsImplCopyWith<$Res> {
  factory _$$TooManyRequestsImplCopyWith(_$TooManyRequestsImpl value,
          $Res Function(_$TooManyRequestsImpl) then) =
      __$$TooManyRequestsImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$TooManyRequestsImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$TooManyRequestsImpl>
    implements _$$TooManyRequestsImplCopyWith<$Res> {
  __$$TooManyRequestsImplCopyWithImpl(
      _$TooManyRequestsImpl _value, $Res Function(_$TooManyRequestsImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$TooManyRequestsImpl extends _TooManyRequests {
  const _$TooManyRequestsImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.tooManyRequests()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$TooManyRequestsImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return tooManyRequests();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return tooManyRequests?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (tooManyRequests != null) {
      return tooManyRequests();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return tooManyRequests(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return tooManyRequests?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (tooManyRequests != null) {
      return tooManyRequests(this);
    }
    return orElse();
  }
}

abstract class _TooManyRequests extends AuthFailure {
  const factory _TooManyRequests() = _$TooManyRequestsImpl;
  const _TooManyRequests._() : super._();
}

/// @nodoc
abstract class _$$NetworkErrorImplCopyWith<$Res> {
  factory _$$NetworkErrorImplCopyWith(
          _$NetworkErrorImpl value, $Res Function(_$NetworkErrorImpl) then) =
      __$$NetworkErrorImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$NetworkErrorImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$NetworkErrorImpl>
    implements _$$NetworkErrorImplCopyWith<$Res> {
  __$$NetworkErrorImplCopyWithImpl(
      _$NetworkErrorImpl _value, $Res Function(_$NetworkErrorImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$NetworkErrorImpl extends _NetworkError {
  const _$NetworkErrorImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.networkError()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$NetworkErrorImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return networkError();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return networkError?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (networkError != null) {
      return networkError();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return networkError(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return networkError?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (networkError != null) {
      return networkError(this);
    }
    return orElse();
  }
}

abstract class _NetworkError extends AuthFailure {
  const factory _NetworkError() = _$NetworkErrorImpl;
  const _NetworkError._() : super._();
}

/// @nodoc
abstract class _$$SignInCancelledImplCopyWith<$Res> {
  factory _$$SignInCancelledImplCopyWith(_$SignInCancelledImpl value,
          $Res Function(_$SignInCancelledImpl) then) =
      __$$SignInCancelledImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$SignInCancelledImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$SignInCancelledImpl>
    implements _$$SignInCancelledImplCopyWith<$Res> {
  __$$SignInCancelledImplCopyWithImpl(
      _$SignInCancelledImpl _value, $Res Function(_$SignInCancelledImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$SignInCancelledImpl extends _SignInCancelled {
  const _$SignInCancelledImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.signInCancelled()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$SignInCancelledImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return signInCancelled();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return signInCancelled?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (signInCancelled != null) {
      return signInCancelled();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return signInCancelled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return signInCancelled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (signInCancelled != null) {
      return signInCancelled(this);
    }
    return orElse();
  }
}

abstract class _SignInCancelled extends AuthFailure {
  const factory _SignInCancelled() = _$SignInCancelledImpl;
  const _SignInCancelled._() : super._();
}

/// @nodoc
abstract class _$$AccountExistsWithDifferentCredentialImplCopyWith<$Res> {
  factory _$$AccountExistsWithDifferentCredentialImplCopyWith(
          _$AccountExistsWithDifferentCredentialImpl value,
          $Res Function(_$AccountExistsWithDifferentCredentialImpl) then) =
      __$$AccountExistsWithDifferentCredentialImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$AccountExistsWithDifferentCredentialImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res,
        _$AccountExistsWithDifferentCredentialImpl>
    implements _$$AccountExistsWithDifferentCredentialImplCopyWith<$Res> {
  __$$AccountExistsWithDifferentCredentialImplCopyWithImpl(
      _$AccountExistsWithDifferentCredentialImpl _value,
      $Res Function(_$AccountExistsWithDifferentCredentialImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$AccountExistsWithDifferentCredentialImpl
    extends _AccountExistsWithDifferentCredential {
  const _$AccountExistsWithDifferentCredentialImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.accountExistsWithDifferentCredential()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AccountExistsWithDifferentCredentialImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return accountExistsWithDifferentCredential();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return accountExistsWithDifferentCredential?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (accountExistsWithDifferentCredential != null) {
      return accountExistsWithDifferentCredential();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return accountExistsWithDifferentCredential(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return accountExistsWithDifferentCredential?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (accountExistsWithDifferentCredential != null) {
      return accountExistsWithDifferentCredential(this);
    }
    return orElse();
  }
}

abstract class _AccountExistsWithDifferentCredential extends AuthFailure {
  const factory _AccountExistsWithDifferentCredential() =
      _$AccountExistsWithDifferentCredentialImpl;
  const _AccountExistsWithDifferentCredential._() : super._();
}

/// @nodoc
abstract class _$$UnknownImplCopyWith<$Res> {
  factory _$$UnknownImplCopyWith(
          _$UnknownImpl value, $Res Function(_$UnknownImpl) then) =
      __$$UnknownImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String code});
}

/// @nodoc
class __$$UnknownImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$UnknownImpl>
    implements _$$UnknownImplCopyWith<$Res> {
  __$$UnknownImplCopyWithImpl(
      _$UnknownImpl _value, $Res Function(_$UnknownImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? code = null,
  }) {
    return _then(_$UnknownImpl(
      null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$UnknownImpl extends _Unknown {
  const _$UnknownImpl(this.code) : super._();

  @override
  final String code;

  @override
  String toString() {
    return 'AuthFailure.unknown(code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UnknownImpl &&
            (identical(other.code, code) || other.code == code));
  }

  @override
  int get hashCode => Object.hash(runtimeType, code);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UnknownImplCopyWith<_$UnknownImpl> get copyWith =>
      __$$UnknownImplCopyWithImpl<_$UnknownImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return unknown(code);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return unknown?.call(code);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown(code);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return unknown(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return unknown?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (unknown != null) {
      return unknown(this);
    }
    return orElse();
  }
}

abstract class _Unknown extends AuthFailure {
  const factory _Unknown(final String code) = _$UnknownImpl;
  const _Unknown._() : super._();

  String get code;

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UnknownImplCopyWith<_$UnknownImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ProfileCreateFailedImplCopyWith<$Res> {
  factory _$$ProfileCreateFailedImplCopyWith(_$ProfileCreateFailedImpl value,
          $Res Function(_$ProfileCreateFailedImpl) then) =
      __$$ProfileCreateFailedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Object? cause});
}

/// @nodoc
class __$$ProfileCreateFailedImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$ProfileCreateFailedImpl>
    implements _$$ProfileCreateFailedImplCopyWith<$Res> {
  __$$ProfileCreateFailedImplCopyWithImpl(_$ProfileCreateFailedImpl _value,
      $Res Function(_$ProfileCreateFailedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? cause = freezed,
  }) {
    return _then(_$ProfileCreateFailedImpl(
      cause: freezed == cause ? _value.cause : cause,
    ));
  }
}

/// @nodoc

class _$ProfileCreateFailedImpl extends _ProfileCreateFailed {
  const _$ProfileCreateFailedImpl({this.cause}) : super._();

  @override
  final Object? cause;

  @override
  String toString() {
    return 'AuthFailure.profileCreateFailed(cause: $cause)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ProfileCreateFailedImpl &&
            const DeepCollectionEquality().equals(other.cause, cause));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(cause));

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ProfileCreateFailedImplCopyWith<_$ProfileCreateFailedImpl> get copyWith =>
      __$$ProfileCreateFailedImplCopyWithImpl<_$ProfileCreateFailedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return profileCreateFailed(cause);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return profileCreateFailed?.call(cause);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (profileCreateFailed != null) {
      return profileCreateFailed(cause);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return profileCreateFailed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return profileCreateFailed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (profileCreateFailed != null) {
      return profileCreateFailed(this);
    }
    return orElse();
  }
}

abstract class _ProfileCreateFailed extends AuthFailure {
  const factory _ProfileCreateFailed({final Object? cause}) =
      _$ProfileCreateFailedImpl;
  const _ProfileCreateFailed._() : super._();

  Object? get cause;

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ProfileCreateFailedImplCopyWith<_$ProfileCreateFailedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$RequiresRecentLoginImplCopyWith<$Res> {
  factory _$$RequiresRecentLoginImplCopyWith(_$RequiresRecentLoginImpl value,
          $Res Function(_$RequiresRecentLoginImpl) then) =
      __$$RequiresRecentLoginImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$RequiresRecentLoginImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$RequiresRecentLoginImpl>
    implements _$$RequiresRecentLoginImplCopyWith<$Res> {
  __$$RequiresRecentLoginImplCopyWithImpl(_$RequiresRecentLoginImpl _value,
      $Res Function(_$RequiresRecentLoginImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$RequiresRecentLoginImpl extends _RequiresRecentLogin {
  const _$RequiresRecentLoginImpl() : super._();

  @override
  String toString() {
    return 'AuthFailure.requiresRecentLogin()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RequiresRecentLoginImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return requiresRecentLogin();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return requiresRecentLogin?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (requiresRecentLogin != null) {
      return requiresRecentLogin();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return requiresRecentLogin(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return requiresRecentLogin?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (requiresRecentLogin != null) {
      return requiresRecentLogin(this);
    }
    return orElse();
  }
}

abstract class _RequiresRecentLogin extends AuthFailure {
  const factory _RequiresRecentLogin() = _$RequiresRecentLoginImpl;
  const _RequiresRecentLogin._() : super._();
}

/// @nodoc
abstract class _$$ReAuthFailedImplCopyWith<$Res> {
  factory _$$ReAuthFailedImplCopyWith(
          _$ReAuthFailedImpl value, $Res Function(_$ReAuthFailedImpl) then) =
      __$$ReAuthFailedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String? provider});
}

/// @nodoc
class __$$ReAuthFailedImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$ReAuthFailedImpl>
    implements _$$ReAuthFailedImplCopyWith<$Res> {
  __$$ReAuthFailedImplCopyWithImpl(
      _$ReAuthFailedImpl _value, $Res Function(_$ReAuthFailedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? provider = freezed,
  }) {
    return _then(_$ReAuthFailedImpl(
      provider: freezed == provider
          ? _value.provider
          : provider // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$ReAuthFailedImpl extends _ReAuthFailed {
  const _$ReAuthFailedImpl({this.provider}) : super._();

  @override
  final String? provider;

  @override
  String toString() {
    return 'AuthFailure.reAuthFailed(provider: $provider)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ReAuthFailedImpl &&
            (identical(other.provider, provider) ||
                other.provider == provider));
  }

  @override
  int get hashCode => Object.hash(runtimeType, provider);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ReAuthFailedImplCopyWith<_$ReAuthFailedImpl> get copyWith =>
      __$$ReAuthFailedImplCopyWithImpl<_$ReAuthFailedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return reAuthFailed(provider);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return reAuthFailed?.call(provider);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (reAuthFailed != null) {
      return reAuthFailed(provider);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return reAuthFailed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return reAuthFailed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (reAuthFailed != null) {
      return reAuthFailed(this);
    }
    return orElse();
  }
}

abstract class _ReAuthFailed extends AuthFailure {
  const factory _ReAuthFailed({final String? provider}) = _$ReAuthFailedImpl;
  const _ReAuthFailed._() : super._();

  String? get provider;

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ReAuthFailedImplCopyWith<_$ReAuthFailedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$DeletionFailedImplCopyWith<$Res> {
  factory _$$DeletionFailedImplCopyWith(_$DeletionFailedImpl value,
          $Res Function(_$DeletionFailedImpl) then) =
      __$$DeletionFailedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({Object? cause});
}

/// @nodoc
class __$$DeletionFailedImplCopyWithImpl<$Res>
    extends _$AuthFailureCopyWithImpl<$Res, _$DeletionFailedImpl>
    implements _$$DeletionFailedImplCopyWith<$Res> {
  __$$DeletionFailedImplCopyWithImpl(
      _$DeletionFailedImpl _value, $Res Function(_$DeletionFailedImpl) _then)
      : super(_value, _then);

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? cause = freezed,
  }) {
    return _then(_$DeletionFailedImpl(
      cause: freezed == cause ? _value.cause : cause,
    ));
  }
}

/// @nodoc

class _$DeletionFailedImpl extends _DeletionFailed {
  const _$DeletionFailedImpl({this.cause}) : super._();

  @override
  final Object? cause;

  @override
  String toString() {
    return 'AuthFailure.deletionFailed(cause: $cause)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeletionFailedImpl &&
            const DeepCollectionEquality().equals(other.cause, cause));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(cause));

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeletionFailedImplCopyWith<_$DeletionFailedImpl> get copyWith =>
      __$$DeletionFailedImplCopyWithImpl<_$DeletionFailedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() invalidEmail,
    required TResult Function() userDisabled,
    required TResult Function() userNotFound,
    required TResult Function() wrongPassword,
    required TResult Function() emailAlreadyInUse,
    required TResult Function() weakPassword,
    required TResult Function() tooManyRequests,
    required TResult Function() networkError,
    required TResult Function() signInCancelled,
    required TResult Function() accountExistsWithDifferentCredential,
    required TResult Function(String code) unknown,
    required TResult Function(Object? cause) profileCreateFailed,
    required TResult Function() requiresRecentLogin,
    required TResult Function(String? provider) reAuthFailed,
    required TResult Function(Object? cause) deletionFailed,
  }) {
    return deletionFailed(cause);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? invalidEmail,
    TResult? Function()? userDisabled,
    TResult? Function()? userNotFound,
    TResult? Function()? wrongPassword,
    TResult? Function()? emailAlreadyInUse,
    TResult? Function()? weakPassword,
    TResult? Function()? tooManyRequests,
    TResult? Function()? networkError,
    TResult? Function()? signInCancelled,
    TResult? Function()? accountExistsWithDifferentCredential,
    TResult? Function(String code)? unknown,
    TResult? Function(Object? cause)? profileCreateFailed,
    TResult? Function()? requiresRecentLogin,
    TResult? Function(String? provider)? reAuthFailed,
    TResult? Function(Object? cause)? deletionFailed,
  }) {
    return deletionFailed?.call(cause);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? invalidEmail,
    TResult Function()? userDisabled,
    TResult Function()? userNotFound,
    TResult Function()? wrongPassword,
    TResult Function()? emailAlreadyInUse,
    TResult Function()? weakPassword,
    TResult Function()? tooManyRequests,
    TResult Function()? networkError,
    TResult Function()? signInCancelled,
    TResult Function()? accountExistsWithDifferentCredential,
    TResult Function(String code)? unknown,
    TResult Function(Object? cause)? profileCreateFailed,
    TResult Function()? requiresRecentLogin,
    TResult Function(String? provider)? reAuthFailed,
    TResult Function(Object? cause)? deletionFailed,
    required TResult orElse(),
  }) {
    if (deletionFailed != null) {
      return deletionFailed(cause);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(_InvalidEmail value) invalidEmail,
    required TResult Function(_UserDisabled value) userDisabled,
    required TResult Function(_UserNotFound value) userNotFound,
    required TResult Function(_WrongPassword value) wrongPassword,
    required TResult Function(_EmailAlreadyInUse value) emailAlreadyInUse,
    required TResult Function(_WeakPassword value) weakPassword,
    required TResult Function(_TooManyRequests value) tooManyRequests,
    required TResult Function(_NetworkError value) networkError,
    required TResult Function(_SignInCancelled value) signInCancelled,
    required TResult Function(_AccountExistsWithDifferentCredential value)
        accountExistsWithDifferentCredential,
    required TResult Function(_Unknown value) unknown,
    required TResult Function(_ProfileCreateFailed value) profileCreateFailed,
    required TResult Function(_RequiresRecentLogin value) requiresRecentLogin,
    required TResult Function(_ReAuthFailed value) reAuthFailed,
    required TResult Function(_DeletionFailed value) deletionFailed,
  }) {
    return deletionFailed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_InvalidEmail value)? invalidEmail,
    TResult? Function(_UserDisabled value)? userDisabled,
    TResult? Function(_UserNotFound value)? userNotFound,
    TResult? Function(_WrongPassword value)? wrongPassword,
    TResult? Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult? Function(_WeakPassword value)? weakPassword,
    TResult? Function(_TooManyRequests value)? tooManyRequests,
    TResult? Function(_NetworkError value)? networkError,
    TResult? Function(_SignInCancelled value)? signInCancelled,
    TResult? Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult? Function(_Unknown value)? unknown,
    TResult? Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult? Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult? Function(_ReAuthFailed value)? reAuthFailed,
    TResult? Function(_DeletionFailed value)? deletionFailed,
  }) {
    return deletionFailed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_InvalidEmail value)? invalidEmail,
    TResult Function(_UserDisabled value)? userDisabled,
    TResult Function(_UserNotFound value)? userNotFound,
    TResult Function(_WrongPassword value)? wrongPassword,
    TResult Function(_EmailAlreadyInUse value)? emailAlreadyInUse,
    TResult Function(_WeakPassword value)? weakPassword,
    TResult Function(_TooManyRequests value)? tooManyRequests,
    TResult Function(_NetworkError value)? networkError,
    TResult Function(_SignInCancelled value)? signInCancelled,
    TResult Function(_AccountExistsWithDifferentCredential value)?
        accountExistsWithDifferentCredential,
    TResult Function(_Unknown value)? unknown,
    TResult Function(_ProfileCreateFailed value)? profileCreateFailed,
    TResult Function(_RequiresRecentLogin value)? requiresRecentLogin,
    TResult Function(_ReAuthFailed value)? reAuthFailed,
    TResult Function(_DeletionFailed value)? deletionFailed,
    required TResult orElse(),
  }) {
    if (deletionFailed != null) {
      return deletionFailed(this);
    }
    return orElse();
  }
}

abstract class _DeletionFailed extends AuthFailure {
  const factory _DeletionFailed({final Object? cause}) = _$DeletionFailedImpl;
  const _DeletionFailed._() : super._();

  Object? get cause;

  /// Create a copy of AuthFailure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeletionFailedImplCopyWith<_$DeletionFailedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
