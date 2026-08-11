// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exercise_feedback.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ExerciseFeedback _$ExerciseFeedbackFromJson(Map<String, dynamic> json) {
  return _ExerciseFeedback.fromJson(json);
}

/// @nodoc
mixin _$ExerciseFeedback {
  String get id => throw _privateConstructorUsedError;

  /// FK → exercises/{id}. Matches [SetLog.exerciseId] so the trainer can
  /// correlate feedback with the numbers.
  String get exerciseId => throw _privateConstructorUsedError;

  /// Denormalized for display without a catalog read, same rationale as
  /// [SetLog.exerciseName].
  String get exerciseName => throw _privateConstructorUsedError;

  /// Position of the slot within the routine day (0-based).
  ///
  /// Required because the same [exerciseId] may legitimately appear twice in
  /// one day (device feedback 2026-06-12). Anchoring on `exerciseId` alone
  /// would surface a comment left on the second bench-press block on the
  /// first one too.
  int get slotIndex => throw _privateConstructorUsedError;

  /// 1-based set the feedback refers to. Null ⇒ the feedback is about the
  /// exercise as a whole, not one set.
  int? get setNumber => throw _privateConstructorUsedError;
  ExerciseFeedbackKind get kind => throw _privateConstructorUsedError;

  /// Free-form athlete text. Null/empty when the athlete only sent a photo.
  String? get text => throw _privateConstructorUsedError;

  /// Storage download URL of the attached photo, null when text-only.
  String? get photoUrl => throw _privateConstructorUsedError;

  /// Storage object path behind [photoUrl], kept so the object can be
  /// deleted. Mirrors the `athlete_files` pattern: storing both prevents
  /// URL↔path drift, which is why updates are denied by the rules.
  String? get photoPath => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this ExerciseFeedback to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ExerciseFeedback
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ExerciseFeedbackCopyWith<ExerciseFeedback> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ExerciseFeedbackCopyWith<$Res> {
  factory $ExerciseFeedbackCopyWith(
          ExerciseFeedback value, $Res Function(ExerciseFeedback) then) =
      _$ExerciseFeedbackCopyWithImpl<$Res, ExerciseFeedback>;
  @useResult
  $Res call(
      {String id,
      String exerciseId,
      String exerciseName,
      int slotIndex,
      int? setNumber,
      ExerciseFeedbackKind kind,
      String? text,
      String? photoUrl,
      String? photoPath,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$ExerciseFeedbackCopyWithImpl<$Res, $Val extends ExerciseFeedback>
    implements $ExerciseFeedbackCopyWith<$Res> {
  _$ExerciseFeedbackCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ExerciseFeedback
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? slotIndex = null,
    Object? setNumber = freezed,
    Object? kind = null,
    Object? text = freezed,
    Object? photoUrl = freezed,
    Object? photoPath = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      slotIndex: null == slotIndex
          ? _value.slotIndex
          : slotIndex // ignore: cast_nullable_to_non_nullable
              as int,
      setNumber: freezed == setNumber
          ? _value.setNumber
          : setNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as ExerciseFeedbackKind,
      text: freezed == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
      photoUrl: freezed == photoUrl
          ? _value.photoUrl
          : photoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      photoPath: freezed == photoPath
          ? _value.photoPath
          : photoPath // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ExerciseFeedbackImplCopyWith<$Res>
    implements $ExerciseFeedbackCopyWith<$Res> {
  factory _$$ExerciseFeedbackImplCopyWith(_$ExerciseFeedbackImpl value,
          $Res Function(_$ExerciseFeedbackImpl) then) =
      __$$ExerciseFeedbackImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String exerciseId,
      String exerciseName,
      int slotIndex,
      int? setNumber,
      ExerciseFeedbackKind kind,
      String? text,
      String? photoUrl,
      String? photoPath,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$ExerciseFeedbackImplCopyWithImpl<$Res>
    extends _$ExerciseFeedbackCopyWithImpl<$Res, _$ExerciseFeedbackImpl>
    implements _$$ExerciseFeedbackImplCopyWith<$Res> {
  __$$ExerciseFeedbackImplCopyWithImpl(_$ExerciseFeedbackImpl _value,
      $Res Function(_$ExerciseFeedbackImpl) _then)
      : super(_value, _then);

  /// Create a copy of ExerciseFeedback
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? exerciseId = null,
    Object? exerciseName = null,
    Object? slotIndex = null,
    Object? setNumber = freezed,
    Object? kind = null,
    Object? text = freezed,
    Object? photoUrl = freezed,
    Object? photoPath = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$ExerciseFeedbackImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseId: null == exerciseId
          ? _value.exerciseId
          : exerciseId // ignore: cast_nullable_to_non_nullable
              as String,
      exerciseName: null == exerciseName
          ? _value.exerciseName
          : exerciseName // ignore: cast_nullable_to_non_nullable
              as String,
      slotIndex: null == slotIndex
          ? _value.slotIndex
          : slotIndex // ignore: cast_nullable_to_non_nullable
              as int,
      setNumber: freezed == setNumber
          ? _value.setNumber
          : setNumber // ignore: cast_nullable_to_non_nullable
              as int?,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as ExerciseFeedbackKind,
      text: freezed == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String?,
      photoUrl: freezed == photoUrl
          ? _value.photoUrl
          : photoUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      photoPath: freezed == photoPath
          ? _value.photoPath
          : photoPath // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ExerciseFeedbackImpl extends _ExerciseFeedback {
  const _$ExerciseFeedbackImpl(
      {required this.id,
      required this.exerciseId,
      required this.exerciseName,
      required this.slotIndex,
      this.setNumber,
      required this.kind,
      this.text,
      this.photoUrl,
      this.photoPath,
      @TimestampConverter() required this.createdAt})
      : super._();

  factory _$ExerciseFeedbackImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExerciseFeedbackImplFromJson(json);

  @override
  final String id;

  /// FK → exercises/{id}. Matches [SetLog.exerciseId] so the trainer can
  /// correlate feedback with the numbers.
  @override
  final String exerciseId;

  /// Denormalized for display without a catalog read, same rationale as
  /// [SetLog.exerciseName].
  @override
  final String exerciseName;

  /// Position of the slot within the routine day (0-based).
  ///
  /// Required because the same [exerciseId] may legitimately appear twice in
  /// one day (device feedback 2026-06-12). Anchoring on `exerciseId` alone
  /// would surface a comment left on the second bench-press block on the
  /// first one too.
  @override
  final int slotIndex;

  /// 1-based set the feedback refers to. Null ⇒ the feedback is about the
  /// exercise as a whole, not one set.
  @override
  final int? setNumber;
  @override
  final ExerciseFeedbackKind kind;

  /// Free-form athlete text. Null/empty when the athlete only sent a photo.
  @override
  final String? text;

  /// Storage download URL of the attached photo, null when text-only.
  @override
  final String? photoUrl;

  /// Storage object path behind [photoUrl], kept so the object can be
  /// deleted. Mirrors the `athlete_files` pattern: storing both prevents
  /// URL↔path drift, which is why updates are denied by the rules.
  @override
  final String? photoPath;
  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'ExerciseFeedback(id: $id, exerciseId: $exerciseId, exerciseName: $exerciseName, slotIndex: $slotIndex, setNumber: $setNumber, kind: $kind, text: $text, photoUrl: $photoUrl, photoPath: $photoPath, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ExerciseFeedbackImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.exerciseId, exerciseId) ||
                other.exerciseId == exerciseId) &&
            (identical(other.exerciseName, exerciseName) ||
                other.exerciseName == exerciseName) &&
            (identical(other.slotIndex, slotIndex) ||
                other.slotIndex == slotIndex) &&
            (identical(other.setNumber, setNumber) ||
                other.setNumber == setNumber) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.photoUrl, photoUrl) ||
                other.photoUrl == photoUrl) &&
            (identical(other.photoPath, photoPath) ||
                other.photoPath == photoPath) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, exerciseId, exerciseName,
      slotIndex, setNumber, kind, text, photoUrl, photoPath, createdAt);

  /// Create a copy of ExerciseFeedback
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ExerciseFeedbackImplCopyWith<_$ExerciseFeedbackImpl> get copyWith =>
      __$$ExerciseFeedbackImplCopyWithImpl<_$ExerciseFeedbackImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ExerciseFeedbackImplToJson(
      this,
    );
  }
}

abstract class _ExerciseFeedback extends ExerciseFeedback {
  const factory _ExerciseFeedback(
          {required final String id,
          required final String exerciseId,
          required final String exerciseName,
          required final int slotIndex,
          final int? setNumber,
          required final ExerciseFeedbackKind kind,
          final String? text,
          final String? photoUrl,
          final String? photoPath,
          @TimestampConverter() required final DateTime createdAt}) =
      _$ExerciseFeedbackImpl;
  const _ExerciseFeedback._() : super._();

  factory _ExerciseFeedback.fromJson(Map<String, dynamic> json) =
      _$ExerciseFeedbackImpl.fromJson;

  @override
  String get id;

  /// FK → exercises/{id}. Matches [SetLog.exerciseId] so the trainer can
  /// correlate feedback with the numbers.
  @override
  String get exerciseId;

  /// Denormalized for display without a catalog read, same rationale as
  /// [SetLog.exerciseName].
  @override
  String get exerciseName;

  /// Position of the slot within the routine day (0-based).
  ///
  /// Required because the same [exerciseId] may legitimately appear twice in
  /// one day (device feedback 2026-06-12). Anchoring on `exerciseId` alone
  /// would surface a comment left on the second bench-press block on the
  /// first one too.
  @override
  int get slotIndex;

  /// 1-based set the feedback refers to. Null ⇒ the feedback is about the
  /// exercise as a whole, not one set.
  @override
  int? get setNumber;
  @override
  ExerciseFeedbackKind get kind;

  /// Free-form athlete text. Null/empty when the athlete only sent a photo.
  @override
  String? get text;

  /// Storage download URL of the attached photo, null when text-only.
  @override
  String? get photoUrl;

  /// Storage object path behind [photoUrl], kept so the object can be
  /// deleted. Mirrors the `athlete_files` pattern: storing both prevents
  /// URL↔path drift, which is why updates are denied by the rules.
  @override
  String? get photoPath;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of ExerciseFeedback
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ExerciseFeedbackImplCopyWith<_$ExerciseFeedbackImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
