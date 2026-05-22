// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'appointment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CancellationEntry _$CancellationEntryFromJson(Map<String, dynamic> json) {
  return _CancellationEntry.fromJson(json);
}

/// @nodoc
mixin _$CancellationEntry {
  String get byUid => throw _privateConstructorUsedError;
  int get atMs => throw _privateConstructorUsedError;
  String? get reason => throw _privateConstructorUsedError;

  /// Serializes this CancellationEntry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CancellationEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CancellationEntryCopyWith<CancellationEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CancellationEntryCopyWith<$Res> {
  factory $CancellationEntryCopyWith(
          CancellationEntry value, $Res Function(CancellationEntry) then) =
      _$CancellationEntryCopyWithImpl<$Res, CancellationEntry>;
  @useResult
  $Res call({String byUid, int atMs, String? reason});
}

/// @nodoc
class _$CancellationEntryCopyWithImpl<$Res, $Val extends CancellationEntry>
    implements $CancellationEntryCopyWith<$Res> {
  _$CancellationEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CancellationEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? byUid = null,
    Object? atMs = null,
    Object? reason = freezed,
  }) {
    return _then(_value.copyWith(
      byUid: null == byUid
          ? _value.byUid
          : byUid // ignore: cast_nullable_to_non_nullable
              as String,
      atMs: null == atMs
          ? _value.atMs
          : atMs // ignore: cast_nullable_to_non_nullable
              as int,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CancellationEntryImplCopyWith<$Res>
    implements $CancellationEntryCopyWith<$Res> {
  factory _$$CancellationEntryImplCopyWith(_$CancellationEntryImpl value,
          $Res Function(_$CancellationEntryImpl) then) =
      __$$CancellationEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String byUid, int atMs, String? reason});
}

/// @nodoc
class __$$CancellationEntryImplCopyWithImpl<$Res>
    extends _$CancellationEntryCopyWithImpl<$Res, _$CancellationEntryImpl>
    implements _$$CancellationEntryImplCopyWith<$Res> {
  __$$CancellationEntryImplCopyWithImpl(_$CancellationEntryImpl _value,
      $Res Function(_$CancellationEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of CancellationEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? byUid = null,
    Object? atMs = null,
    Object? reason = freezed,
  }) {
    return _then(_$CancellationEntryImpl(
      byUid: null == byUid
          ? _value.byUid
          : byUid // ignore: cast_nullable_to_non_nullable
              as String,
      atMs: null == atMs
          ? _value.atMs
          : atMs // ignore: cast_nullable_to_non_nullable
              as int,
      reason: freezed == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CancellationEntryImpl implements _CancellationEntry {
  const _$CancellationEntryImpl(
      {required this.byUid, required this.atMs, this.reason});

  factory _$CancellationEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$CancellationEntryImplFromJson(json);

  @override
  final String byUid;
  @override
  final int atMs;
  @override
  final String? reason;

  @override
  String toString() {
    return 'CancellationEntry(byUid: $byUid, atMs: $atMs, reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CancellationEntryImpl &&
            (identical(other.byUid, byUid) || other.byUid == byUid) &&
            (identical(other.atMs, atMs) || other.atMs == atMs) &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, byUid, atMs, reason);

  /// Create a copy of CancellationEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CancellationEntryImplCopyWith<_$CancellationEntryImpl> get copyWith =>
      __$$CancellationEntryImplCopyWithImpl<_$CancellationEntryImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CancellationEntryImplToJson(
      this,
    );
  }
}

abstract class _CancellationEntry implements CancellationEntry {
  const factory _CancellationEntry(
      {required final String byUid,
      required final int atMs,
      final String? reason}) = _$CancellationEntryImpl;

  factory _CancellationEntry.fromJson(Map<String, dynamic> json) =
      _$CancellationEntryImpl.fromJson;

  @override
  String get byUid;
  @override
  int get atMs;
  @override
  String? get reason;

  /// Create a copy of CancellationEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CancellationEntryImplCopyWith<_$CancellationEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

Appointment _$AppointmentFromJson(Map<String, dynamic> json) {
  return _Appointment.fromJson(json);
}

/// @nodoc
mixin _$Appointment {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  String get athleteDisplayName => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get startsAt => throw _privateConstructorUsedError;
  int get durationMin => throw _privateConstructorUsedError;
  AppointmentStatus get status => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get cancelledAt => throw _privateConstructorUsedError;
  String? get cancelledBy => throw _privateConstructorUsedError;
  List<CancellationEntry> get cancellationLog =>
      throw _privateConstructorUsedError;

  /// Serializes this Appointment to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Appointment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AppointmentCopyWith<Appointment> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AppointmentCopyWith<$Res> {
  factory $AppointmentCopyWith(
          Appointment value, $Res Function(Appointment) then) =
      _$AppointmentCopyWithImpl<$Res, Appointment>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String athleteDisplayName,
      @TimestampConverter() DateTime startsAt,
      int durationMin,
      AppointmentStatus status,
      @TimestampConverter() DateTime? cancelledAt,
      String? cancelledBy,
      List<CancellationEntry> cancellationLog});
}

/// @nodoc
class _$AppointmentCopyWithImpl<$Res, $Val extends Appointment>
    implements $AppointmentCopyWith<$Res> {
  _$AppointmentCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Appointment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? athleteDisplayName = null,
    Object? startsAt = null,
    Object? durationMin = null,
    Object? status = null,
    Object? cancelledAt = freezed,
    Object? cancelledBy = freezed,
    Object? cancellationLog = null,
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
      athleteDisplayName: null == athleteDisplayName
          ? _value.athleteDisplayName
          : athleteDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      startsAt: null == startsAt
          ? _value.startsAt
          : startsAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as AppointmentStatus,
      cancelledAt: freezed == cancelledAt
          ? _value.cancelledAt
          : cancelledAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cancelledBy: freezed == cancelledBy
          ? _value.cancelledBy
          : cancelledBy // ignore: cast_nullable_to_non_nullable
              as String?,
      cancellationLog: null == cancellationLog
          ? _value.cancellationLog
          : cancellationLog // ignore: cast_nullable_to_non_nullable
              as List<CancellationEntry>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AppointmentImplCopyWith<$Res>
    implements $AppointmentCopyWith<$Res> {
  factory _$$AppointmentImplCopyWith(
          _$AppointmentImpl value, $Res Function(_$AppointmentImpl) then) =
      __$$AppointmentImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String athleteDisplayName,
      @TimestampConverter() DateTime startsAt,
      int durationMin,
      AppointmentStatus status,
      @TimestampConverter() DateTime? cancelledAt,
      String? cancelledBy,
      List<CancellationEntry> cancellationLog});
}

/// @nodoc
class __$$AppointmentImplCopyWithImpl<$Res>
    extends _$AppointmentCopyWithImpl<$Res, _$AppointmentImpl>
    implements _$$AppointmentImplCopyWith<$Res> {
  __$$AppointmentImplCopyWithImpl(
      _$AppointmentImpl _value, $Res Function(_$AppointmentImpl) _then)
      : super(_value, _then);

  /// Create a copy of Appointment
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? athleteDisplayName = null,
    Object? startsAt = null,
    Object? durationMin = null,
    Object? status = null,
    Object? cancelledAt = freezed,
    Object? cancelledBy = freezed,
    Object? cancellationLog = null,
  }) {
    return _then(_$AppointmentImpl(
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
      athleteDisplayName: null == athleteDisplayName
          ? _value.athleteDisplayName
          : athleteDisplayName // ignore: cast_nullable_to_non_nullable
              as String,
      startsAt: null == startsAt
          ? _value.startsAt
          : startsAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as AppointmentStatus,
      cancelledAt: freezed == cancelledAt
          ? _value.cancelledAt
          : cancelledAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cancelledBy: freezed == cancelledBy
          ? _value.cancelledBy
          : cancelledBy // ignore: cast_nullable_to_non_nullable
              as String?,
      cancellationLog: null == cancellationLog
          ? _value._cancellationLog
          : cancellationLog // ignore: cast_nullable_to_non_nullable
              as List<CancellationEntry>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AppointmentImpl extends _Appointment {
  const _$AppointmentImpl(
      {required this.id,
      required this.trainerId,
      required this.athleteId,
      required this.athleteDisplayName,
      @TimestampConverter() required this.startsAt,
      required this.durationMin,
      required this.status,
      @TimestampConverter() this.cancelledAt,
      this.cancelledBy,
      final List<CancellationEntry> cancellationLog = const []})
      : _cancellationLog = cancellationLog,
        super._();

  factory _$AppointmentImpl.fromJson(Map<String, dynamic> json) =>
      _$$AppointmentImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final String athleteDisplayName;
  @override
  @TimestampConverter()
  final DateTime startsAt;
  @override
  final int durationMin;
  @override
  final AppointmentStatus status;
  @override
  @TimestampConverter()
  final DateTime? cancelledAt;
  @override
  final String? cancelledBy;
  final List<CancellationEntry> _cancellationLog;
  @override
  @JsonKey()
  List<CancellationEntry> get cancellationLog {
    if (_cancellationLog is EqualUnmodifiableListView) return _cancellationLog;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_cancellationLog);
  }

  @override
  String toString() {
    return 'Appointment(id: $id, trainerId: $trainerId, athleteId: $athleteId, athleteDisplayName: $athleteDisplayName, startsAt: $startsAt, durationMin: $durationMin, status: $status, cancelledAt: $cancelledAt, cancelledBy: $cancelledBy, cancellationLog: $cancellationLog)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AppointmentImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.athleteDisplayName, athleteDisplayName) ||
                other.athleteDisplayName == athleteDisplayName) &&
            (identical(other.startsAt, startsAt) ||
                other.startsAt == startsAt) &&
            (identical(other.durationMin, durationMin) ||
                other.durationMin == durationMin) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.cancelledAt, cancelledAt) ||
                other.cancelledAt == cancelledAt) &&
            (identical(other.cancelledBy, cancelledBy) ||
                other.cancelledBy == cancelledBy) &&
            const DeepCollectionEquality()
                .equals(other._cancellationLog, _cancellationLog));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      trainerId,
      athleteId,
      athleteDisplayName,
      startsAt,
      durationMin,
      status,
      cancelledAt,
      cancelledBy,
      const DeepCollectionEquality().hash(_cancellationLog));

  /// Create a copy of Appointment
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AppointmentImplCopyWith<_$AppointmentImpl> get copyWith =>
      __$$AppointmentImplCopyWithImpl<_$AppointmentImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AppointmentImplToJson(
      this,
    );
  }
}

abstract class _Appointment extends Appointment {
  const factory _Appointment(
      {required final String id,
      required final String trainerId,
      required final String athleteId,
      required final String athleteDisplayName,
      @TimestampConverter() required final DateTime startsAt,
      required final int durationMin,
      required final AppointmentStatus status,
      @TimestampConverter() final DateTime? cancelledAt,
      final String? cancelledBy,
      final List<CancellationEntry> cancellationLog}) = _$AppointmentImpl;
  const _Appointment._() : super._();

  factory _Appointment.fromJson(Map<String, dynamic> json) =
      _$AppointmentImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  String get athleteDisplayName;
  @override
  @TimestampConverter()
  DateTime get startsAt;
  @override
  int get durationMin;
  @override
  AppointmentStatus get status;
  @override
  @TimestampConverter()
  DateTime? get cancelledAt;
  @override
  String? get cancelledBy;
  @override
  List<CancellationEntry> get cancellationLog;

  /// Create a copy of Appointment
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AppointmentImplCopyWith<_$AppointmentImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
