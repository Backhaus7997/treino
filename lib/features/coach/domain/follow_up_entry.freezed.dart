// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'follow_up_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

FollowUpEntry _$FollowUpEntryFromJson(Map<String, dynamic> json) {
  return _FollowUpEntry.fromJson(json);
}

/// @nodoc
mixin _$FollowUpEntry {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;
  FollowUpTag get tag => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get recordedAt => throw _privateConstructorUsedError;

  /// Serializes this FollowUpEntry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FollowUpEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FollowUpEntryCopyWith<FollowUpEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FollowUpEntryCopyWith<$Res> {
  factory $FollowUpEntryCopyWith(
          FollowUpEntry value, $Res Function(FollowUpEntry) then) =
      _$FollowUpEntryCopyWithImpl<$Res, FollowUpEntry>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String text,
      FollowUpTag tag,
      @TimestampConverter() DateTime recordedAt});
}

/// @nodoc
class _$FollowUpEntryCopyWithImpl<$Res, $Val extends FollowUpEntry>
    implements $FollowUpEntryCopyWith<$Res> {
  _$FollowUpEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FollowUpEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? text = null,
    Object? tag = null,
    Object? recordedAt = null,
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
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      tag: null == tag
          ? _value.tag
          : tag // ignore: cast_nullable_to_non_nullable
              as FollowUpTag,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FollowUpEntryImplCopyWith<$Res>
    implements $FollowUpEntryCopyWith<$Res> {
  factory _$$FollowUpEntryImplCopyWith(
          _$FollowUpEntryImpl value, $Res Function(_$FollowUpEntryImpl) then) =
      __$$FollowUpEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String text,
      FollowUpTag tag,
      @TimestampConverter() DateTime recordedAt});
}

/// @nodoc
class __$$FollowUpEntryImplCopyWithImpl<$Res>
    extends _$FollowUpEntryCopyWithImpl<$Res, _$FollowUpEntryImpl>
    implements _$$FollowUpEntryImplCopyWith<$Res> {
  __$$FollowUpEntryImplCopyWithImpl(
      _$FollowUpEntryImpl _value, $Res Function(_$FollowUpEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of FollowUpEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? text = null,
    Object? tag = null,
    Object? recordedAt = null,
  }) {
    return _then(_$FollowUpEntryImpl(
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
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      tag: null == tag
          ? _value.tag
          : tag // ignore: cast_nullable_to_non_nullable
              as FollowUpTag,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$FollowUpEntryImpl implements _FollowUpEntry {
  const _$FollowUpEntryImpl(
      {required this.id,
      required this.trainerId,
      required this.athleteId,
      required this.text,
      required this.tag,
      @TimestampConverter() required this.recordedAt});

  factory _$FollowUpEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$FollowUpEntryImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final String text;
  @override
  final FollowUpTag tag;
  @override
  @TimestampConverter()
  final DateTime recordedAt;

  @override
  String toString() {
    return 'FollowUpEntry(id: $id, trainerId: $trainerId, athleteId: $athleteId, text: $text, tag: $tag, recordedAt: $recordedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FollowUpEntryImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.tag, tag) || other.tag == tag) &&
            (identical(other.recordedAt, recordedAt) ||
                other.recordedAt == recordedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, id, trainerId, athleteId, text, tag, recordedAt);

  /// Create a copy of FollowUpEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FollowUpEntryImplCopyWith<_$FollowUpEntryImpl> get copyWith =>
      __$$FollowUpEntryImplCopyWithImpl<_$FollowUpEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FollowUpEntryImplToJson(
      this,
    );
  }
}

abstract class _FollowUpEntry implements FollowUpEntry {
  const factory _FollowUpEntry(
          {required final String id,
          required final String trainerId,
          required final String athleteId,
          required final String text,
          required final FollowUpTag tag,
          @TimestampConverter() required final DateTime recordedAt}) =
      _$FollowUpEntryImpl;

  factory _FollowUpEntry.fromJson(Map<String, dynamic> json) =
      _$FollowUpEntryImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  String get text;
  @override
  FollowUpTag get tag;
  @override
  @TimestampConverter()
  DateTime get recordedAt;

  /// Create a copy of FollowUpEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FollowUpEntryImplCopyWith<_$FollowUpEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
