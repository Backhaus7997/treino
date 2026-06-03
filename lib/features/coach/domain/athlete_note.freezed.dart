// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'athlete_note.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AthleteNote _$AthleteNoteFromJson(Map<String, dynamic> json) {
  return _AthleteNote.fromJson(json);
}

/// @nodoc
mixin _$AthleteNote {
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  String get note => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this AthleteNote to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AthleteNote
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AthleteNoteCopyWith<AthleteNote> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AthleteNoteCopyWith<$Res> {
  factory $AthleteNoteCopyWith(
          AthleteNote value, $Res Function(AthleteNote) then) =
      _$AthleteNoteCopyWithImpl<$Res, AthleteNote>;
  @useResult
  $Res call(
      {String trainerId,
      String athleteId,
      String note,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class _$AthleteNoteCopyWithImpl<$Res, $Val extends AthleteNote>
    implements $AthleteNoteCopyWith<$Res> {
  _$AthleteNoteCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AthleteNote
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? athleteId = null,
    Object? note = null,
    Object? updatedAt = null,
  }) {
    return _then(_value.copyWith(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AthleteNoteImplCopyWith<$Res>
    implements $AthleteNoteCopyWith<$Res> {
  factory _$$AthleteNoteImplCopyWith(
          _$AthleteNoteImpl value, $Res Function(_$AthleteNoteImpl) then) =
      __$$AthleteNoteImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String trainerId,
      String athleteId,
      String note,
      @TimestampConverter() DateTime updatedAt});
}

/// @nodoc
class __$$AthleteNoteImplCopyWithImpl<$Res>
    extends _$AthleteNoteCopyWithImpl<$Res, _$AthleteNoteImpl>
    implements _$$AthleteNoteImplCopyWith<$Res> {
  __$$AthleteNoteImplCopyWithImpl(
      _$AthleteNoteImpl _value, $Res Function(_$AthleteNoteImpl) _then)
      : super(_value, _then);

  /// Create a copy of AthleteNote
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? trainerId = null,
    Object? athleteId = null,
    Object? note = null,
    Object? updatedAt = null,
  }) {
    return _then(_$AthleteNoteImpl(
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      athleteId: null == athleteId
          ? _value.athleteId
          : athleteId // ignore: cast_nullable_to_non_nullable
              as String,
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
      updatedAt: null == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AthleteNoteImpl implements _AthleteNote {
  const _$AthleteNoteImpl(
      {required this.trainerId,
      required this.athleteId,
      required this.note,
      @TimestampConverter() required this.updatedAt});

  factory _$AthleteNoteImpl.fromJson(Map<String, dynamic> json) =>
      _$$AthleteNoteImplFromJson(json);

  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final String note;
  @override
  @TimestampConverter()
  final DateTime updatedAt;

  @override
  String toString() {
    return 'AthleteNote(trainerId: $trainerId, athleteId: $athleteId, note: $note, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AthleteNoteImpl &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, trainerId, athleteId, note, updatedAt);

  /// Create a copy of AthleteNote
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AthleteNoteImplCopyWith<_$AthleteNoteImpl> get copyWith =>
      __$$AthleteNoteImplCopyWithImpl<_$AthleteNoteImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AthleteNoteImplToJson(
      this,
    );
  }
}

abstract class _AthleteNote implements AthleteNote {
  const factory _AthleteNote(
          {required final String trainerId,
          required final String athleteId,
          required final String note,
          @TimestampConverter() required final DateTime updatedAt}) =
      _$AthleteNoteImpl;

  factory _AthleteNote.fromJson(Map<String, dynamic> json) =
      _$AthleteNoteImpl.fromJson;

  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  String get note;
  @override
  @TimestampConverter()
  DateTime get updatedAt;

  /// Create a copy of AthleteNote
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AthleteNoteImplCopyWith<_$AthleteNoteImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
