// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'content_report.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ContentReport _$ContentReportFromJson(Map<String, dynamic> json) {
  return _ContentReport.fromJson(json);
}

/// @nodoc
mixin _$ContentReport {
  @JsonKey(includeToJson: false)
  String get id => throw _privateConstructorUsedError;
  String get reporterUid => throw _privateConstructorUsedError;
  ReportTargetKind get targetKind => throw _privateConstructorUsedError;
  String get targetId => throw _privateConstructorUsedError;

  /// Uid del dueño del contenido reportado (autor del post/mensaje/review,
  /// o el propio perfil cuando `targetKind == profile`). No participa del
  /// id — sólo viaja como dato para que la revisión en consola no tenga que
  /// resolverlo a mano.
  String get targetOwnerUid => throw _privateConstructorUsedError;
  ReportReason get reason => throw _privateConstructorUsedError;

  /// Detalle libre opcional, ≤ 1000 caracteres (lo valida el sheet y,
  /// server-side, las reglas de Firestore).
  String? get detail => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;

  /// Serializes this ContentReport to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ContentReport
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ContentReportCopyWith<ContentReport> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ContentReportCopyWith<$Res> {
  factory $ContentReportCopyWith(
          ContentReport value, $Res Function(ContentReport) then) =
      _$ContentReportCopyWithImpl<$Res, ContentReport>;
  @useResult
  $Res call(
      {@JsonKey(includeToJson: false) String id,
      String reporterUid,
      ReportTargetKind targetKind,
      String targetId,
      String targetOwnerUid,
      ReportReason reason,
      String? detail,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class _$ContentReportCopyWithImpl<$Res, $Val extends ContentReport>
    implements $ContentReportCopyWith<$Res> {
  _$ContentReportCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ContentReport
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? reporterUid = null,
    Object? targetKind = null,
    Object? targetId = null,
    Object? targetOwnerUid = null,
    Object? reason = null,
    Object? detail = freezed,
    Object? createdAt = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      reporterUid: null == reporterUid
          ? _value.reporterUid
          : reporterUid // ignore: cast_nullable_to_non_nullable
              as String,
      targetKind: null == targetKind
          ? _value.targetKind
          : targetKind // ignore: cast_nullable_to_non_nullable
              as ReportTargetKind,
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String,
      targetOwnerUid: null == targetOwnerUid
          ? _value.targetOwnerUid
          : targetOwnerUid // ignore: cast_nullable_to_non_nullable
              as String,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as ReportReason,
      detail: freezed == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
              as String?,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ContentReportImplCopyWith<$Res>
    implements $ContentReportCopyWith<$Res> {
  factory _$$ContentReportImplCopyWith(
          _$ContentReportImpl value, $Res Function(_$ContentReportImpl) then) =
      __$$ContentReportImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {@JsonKey(includeToJson: false) String id,
      String reporterUid,
      ReportTargetKind targetKind,
      String targetId,
      String targetOwnerUid,
      ReportReason reason,
      String? detail,
      @TimestampConverter() DateTime createdAt});
}

/// @nodoc
class __$$ContentReportImplCopyWithImpl<$Res>
    extends _$ContentReportCopyWithImpl<$Res, _$ContentReportImpl>
    implements _$$ContentReportImplCopyWith<$Res> {
  __$$ContentReportImplCopyWithImpl(
      _$ContentReportImpl _value, $Res Function(_$ContentReportImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentReport
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? reporterUid = null,
    Object? targetKind = null,
    Object? targetId = null,
    Object? targetOwnerUid = null,
    Object? reason = null,
    Object? detail = freezed,
    Object? createdAt = null,
  }) {
    return _then(_$ContentReportImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      reporterUid: null == reporterUid
          ? _value.reporterUid
          : reporterUid // ignore: cast_nullable_to_non_nullable
              as String,
      targetKind: null == targetKind
          ? _value.targetKind
          : targetKind // ignore: cast_nullable_to_non_nullable
              as ReportTargetKind,
      targetId: null == targetId
          ? _value.targetId
          : targetId // ignore: cast_nullable_to_non_nullable
              as String,
      targetOwnerUid: null == targetOwnerUid
          ? _value.targetOwnerUid
          : targetOwnerUid // ignore: cast_nullable_to_non_nullable
              as String,
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as ReportReason,
      detail: freezed == detail
          ? _value.detail
          : detail // ignore: cast_nullable_to_non_nullable
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
class _$ContentReportImpl implements _ContentReport {
  const _$ContentReportImpl(
      {@JsonKey(includeToJson: false) required this.id,
      required this.reporterUid,
      required this.targetKind,
      required this.targetId,
      required this.targetOwnerUid,
      required this.reason,
      this.detail,
      @TimestampConverter() required this.createdAt});

  factory _$ContentReportImpl.fromJson(Map<String, dynamic> json) =>
      _$$ContentReportImplFromJson(json);

  @override
  @JsonKey(includeToJson: false)
  final String id;
  @override
  final String reporterUid;
  @override
  final ReportTargetKind targetKind;
  @override
  final String targetId;

  /// Uid del dueño del contenido reportado (autor del post/mensaje/review,
  /// o el propio perfil cuando `targetKind == profile`). No participa del
  /// id — sólo viaja como dato para que la revisión en consola no tenga que
  /// resolverlo a mano.
  @override
  final String targetOwnerUid;
  @override
  final ReportReason reason;

  /// Detalle libre opcional, ≤ 1000 caracteres (lo valida el sheet y,
  /// server-side, las reglas de Firestore).
  @override
  final String? detail;
  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'ContentReport(id: $id, reporterUid: $reporterUid, targetKind: $targetKind, targetId: $targetId, targetOwnerUid: $targetOwnerUid, reason: $reason, detail: $detail, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ContentReportImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.reporterUid, reporterUid) ||
                other.reporterUid == reporterUid) &&
            (identical(other.targetKind, targetKind) ||
                other.targetKind == targetKind) &&
            (identical(other.targetId, targetId) ||
                other.targetId == targetId) &&
            (identical(other.targetOwnerUid, targetOwnerUid) ||
                other.targetOwnerUid == targetOwnerUid) &&
            (identical(other.reason, reason) || other.reason == reason) &&
            (identical(other.detail, detail) || other.detail == detail) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, reporterUid, targetKind,
      targetId, targetOwnerUid, reason, detail, createdAt);

  /// Create a copy of ContentReport
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ContentReportImplCopyWith<_$ContentReportImpl> get copyWith =>
      __$$ContentReportImplCopyWithImpl<_$ContentReportImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ContentReportImplToJson(
      this,
    );
  }
}

abstract class _ContentReport implements ContentReport {
  const factory _ContentReport(
          {@JsonKey(includeToJson: false) required final String id,
          required final String reporterUid,
          required final ReportTargetKind targetKind,
          required final String targetId,
          required final String targetOwnerUid,
          required final ReportReason reason,
          final String? detail,
          @TimestampConverter() required final DateTime createdAt}) =
      _$ContentReportImpl;

  factory _ContentReport.fromJson(Map<String, dynamic> json) =
      _$ContentReportImpl.fromJson;

  @override
  @JsonKey(includeToJson: false)
  String get id;
  @override
  String get reporterUid;
  @override
  ReportTargetKind get targetKind;
  @override
  String get targetId;

  /// Uid del dueño del contenido reportado (autor del post/mensaje/review,
  /// o el propio perfil cuando `targetKind == profile`). No participa del
  /// id — sólo viaja como dato para que la revisión en consola no tenga que
  /// resolverlo a mano.
  @override
  String get targetOwnerUid;
  @override
  ReportReason get reason;

  /// Detalle libre opcional, ≤ 1000 caracteres (lo valida el sheet y,
  /// server-side, las reglas de Firestore).
  @override
  String? get detail;
  @override
  @TimestampConverter()
  DateTime get createdAt;

  /// Create a copy of ContentReport
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ContentReportImplCopyWith<_$ContentReportImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
