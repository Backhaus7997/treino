// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'template_rating.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

TemplateRating _$TemplateRatingFromJson(Map<String, dynamic> json) {
  return _TemplateRating.fromJson(json);
}

/// @nodoc
mixin _$TemplateRating {
  /// Rater uid — duplicated from the doc id so list snapshots can render
  /// without re-deriving it from the snapshot path.
  String get userId => throw _privateConstructorUsedError;

  /// 1..5 inclusive. Validated by [RoutineRepository] and Firestore rules.
  int get rating => throw _privateConstructorUsedError;

  /// Optional freeform comment, max 500 chars.
  /// Validated by [RoutineRepository] and Firestore rules.
  String? get comment => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this TemplateRating to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TemplateRating
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TemplateRatingCopyWith<TemplateRating> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TemplateRatingCopyWith<$Res> {
  factory $TemplateRatingCopyWith(
          TemplateRating value, $Res Function(TemplateRating) then) =
      _$TemplateRatingCopyWithImpl<$Res, TemplateRating>;
  @useResult
  $Res call(
      {String userId,
      int rating,
      String? comment,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$TemplateRatingCopyWithImpl<$Res, $Val extends TemplateRating>
    implements $TemplateRatingCopyWith<$Res> {
  _$TemplateRatingCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TemplateRating
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? rating = null,
    Object? comment = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      rating: null == rating
          ? _value.rating
          : rating // ignore: cast_nullable_to_non_nullable
              as int,
      comment: freezed == comment
          ? _value.comment
          : comment // ignore: cast_nullable_to_non_nullable
              as String?,
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
abstract class _$$TemplateRatingImplCopyWith<$Res>
    implements $TemplateRatingCopyWith<$Res> {
  factory _$$TemplateRatingImplCopyWith(_$TemplateRatingImpl value,
          $Res Function(_$TemplateRatingImpl) then) =
      __$$TemplateRatingImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String userId,
      int rating,
      String? comment,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$TemplateRatingImplCopyWithImpl<$Res>
    extends _$TemplateRatingCopyWithImpl<$Res, _$TemplateRatingImpl>
    implements _$$TemplateRatingImplCopyWith<$Res> {
  __$$TemplateRatingImplCopyWithImpl(
      _$TemplateRatingImpl _value, $Res Function(_$TemplateRatingImpl) _then)
      : super(_value, _then);

  /// Create a copy of TemplateRating
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? rating = null,
    Object? comment = freezed,
    Object? createdAt = null,
    Object? updatedAt = null,
  }) {
    return _then(_$TemplateRatingImpl(
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      rating: null == rating
          ? _value.rating
          : rating // ignore: cast_nullable_to_non_nullable
              as int,
      comment: freezed == comment
          ? _value.comment
          : comment // ignore: cast_nullable_to_non_nullable
              as String?,
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
class _$TemplateRatingImpl implements _TemplateRating {
  const _$TemplateRatingImpl(
      {required this.userId,
      required this.rating,
      this.comment,
      @TimestampConverter() required this.createdAt,
      @TimestampConverter() required this.updatedAt});

  factory _$TemplateRatingImpl.fromJson(Map<String, dynamic> json) =>
      _$$TemplateRatingImplFromJson(json);

  /// Rater uid — duplicated from the doc id so list snapshots can render
  /// without re-deriving it from the snapshot path.
  @override
  final String userId;

  /// 1..5 inclusive. Validated by [RoutineRepository] and Firestore rules.
  @override
  final int rating;

  /// Optional freeform comment, max 500 chars.
  /// Validated by [RoutineRepository] and Firestore rules.
  @override
  final String? comment;
  @override
  @TimestampConverter()
  final DateTime createdAt;
  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'TemplateRating(userId: $userId, rating: $rating, comment: $comment, createdAt: $createdAt, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TemplateRatingImpl &&
            (identical(other.userId, userId) || other.userId == userId) &&
            (identical(other.rating, rating) || other.rating == rating) &&
            (identical(other.comment, comment) || other.comment == comment) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, userId, rating, comment, createdAt, updatedAt);

  /// Create a copy of TemplateRating
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TemplateRatingImplCopyWith<_$TemplateRatingImpl> get copyWith =>
      __$$TemplateRatingImplCopyWithImpl<_$TemplateRatingImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TemplateRatingImplToJson(
      this,
    );
  }
}

abstract class _TemplateRating implements TemplateRating {
  const factory _TemplateRating(
          {required final String userId,
          required final int rating,
          final String? comment,
          @TimestampConverter() required final DateTime createdAt,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$TemplateRatingImpl;

  factory _TemplateRating.fromJson(Map<String, dynamic> json) =
      _$TemplateRatingImpl.fromJson;

  /// Rater uid — duplicated from the doc id so list snapshots can render
  /// without re-deriving it from the snapshot path.
  @override
  String get userId;

  /// 1..5 inclusive. Validated by [RoutineRepository] and Firestore rules.
  @override
  int get rating;

  /// Optional freeform comment, max 500 chars.
  /// Validated by [RoutineRepository] and Firestore rules.
  @override
  String? get comment;
  @override
  @TimestampConverter()
  DateTime get createdAt;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of TemplateRating
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TemplateRatingImplCopyWith<_$TemplateRatingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
