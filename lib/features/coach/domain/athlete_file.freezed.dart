// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'athlete_file.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AthleteFile _$AthleteFileFromJson(Map<String, dynamic> json) {
  return _AthleteFile.fromJson(json);
}

/// @nodoc
mixin _$AthleteFile {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  String get athleteId => throw _privateConstructorUsedError;
  String get fileName => throw _privateConstructorUsedError;
  AthleteFileKind get kind => throw _privateConstructorUsedError;
  String get contentType => throw _privateConstructorUsedError;
  int get sizeBytes => throw _privateConstructorUsedError;
  String get storagePath => throw _privateConstructorUsedError;
  String get downloadUrl => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get uploadedAt => throw _privateConstructorUsedError;

  /// Serializes this AthleteFile to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AthleteFile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AthleteFileCopyWith<AthleteFile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AthleteFileCopyWith<$Res> {
  factory $AthleteFileCopyWith(
          AthleteFile value, $Res Function(AthleteFile) then) =
      _$AthleteFileCopyWithImpl<$Res, AthleteFile>;
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String fileName,
      AthleteFileKind kind,
      String contentType,
      int sizeBytes,
      String storagePath,
      String downloadUrl,
      @TimestampConverter() DateTime uploadedAt});
}

/// @nodoc
class _$AthleteFileCopyWithImpl<$Res, $Val extends AthleteFile>
    implements $AthleteFileCopyWith<$Res> {
  _$AthleteFileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AthleteFile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? fileName = null,
    Object? kind = null,
    Object? contentType = null,
    Object? sizeBytes = null,
    Object? storagePath = null,
    Object? downloadUrl = null,
    Object? uploadedAt = null,
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
      fileName: null == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as AthleteFileKind,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as String,
      sizeBytes: null == sizeBytes
          ? _value.sizeBytes
          : sizeBytes // ignore: cast_nullable_to_non_nullable
              as int,
      storagePath: null == storagePath
          ? _value.storagePath
          : storagePath // ignore: cast_nullable_to_non_nullable
              as String,
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      uploadedAt: null == uploadedAt
          ? _value.uploadedAt
          : uploadedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AthleteFileImplCopyWith<$Res>
    implements $AthleteFileCopyWith<$Res> {
  factory _$$AthleteFileImplCopyWith(
          _$AthleteFileImpl value, $Res Function(_$AthleteFileImpl) then) =
      __$$AthleteFileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      String athleteId,
      String fileName,
      AthleteFileKind kind,
      String contentType,
      int sizeBytes,
      String storagePath,
      String downloadUrl,
      @TimestampConverter() DateTime uploadedAt});
}

/// @nodoc
class __$$AthleteFileImplCopyWithImpl<$Res>
    extends _$AthleteFileCopyWithImpl<$Res, _$AthleteFileImpl>
    implements _$$AthleteFileImplCopyWith<$Res> {
  __$$AthleteFileImplCopyWithImpl(
      _$AthleteFileImpl _value, $Res Function(_$AthleteFileImpl) _then)
      : super(_value, _then);

  /// Create a copy of AthleteFile
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? athleteId = null,
    Object? fileName = null,
    Object? kind = null,
    Object? contentType = null,
    Object? sizeBytes = null,
    Object? storagePath = null,
    Object? downloadUrl = null,
    Object? uploadedAt = null,
  }) {
    return _then(_$AthleteFileImpl(
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
      fileName: null == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String,
      kind: null == kind
          ? _value.kind
          : kind // ignore: cast_nullable_to_non_nullable
              as AthleteFileKind,
      contentType: null == contentType
          ? _value.contentType
          : contentType // ignore: cast_nullable_to_non_nullable
              as String,
      sizeBytes: null == sizeBytes
          ? _value.sizeBytes
          : sizeBytes // ignore: cast_nullable_to_non_nullable
              as int,
      storagePath: null == storagePath
          ? _value.storagePath
          : storagePath // ignore: cast_nullable_to_non_nullable
              as String,
      downloadUrl: null == downloadUrl
          ? _value.downloadUrl
          : downloadUrl // ignore: cast_nullable_to_non_nullable
              as String,
      uploadedAt: null == uploadedAt
          ? _value.uploadedAt
          : uploadedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AthleteFileImpl implements _AthleteFile {
  const _$AthleteFileImpl(
      {required this.id,
      required this.trainerId,
      required this.athleteId,
      required this.fileName,
      required this.kind,
      required this.contentType,
      required this.sizeBytes,
      required this.storagePath,
      required this.downloadUrl,
      @TimestampConverter() required this.uploadedAt});

  factory _$AthleteFileImpl.fromJson(Map<String, dynamic> json) =>
      _$$AthleteFileImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  final String athleteId;
  @override
  final String fileName;
  @override
  final AthleteFileKind kind;
  @override
  final String contentType;
  @override
  final int sizeBytes;
  @override
  final String storagePath;
  @override
  final String downloadUrl;
  @override
  @TimestampConverter()
  final DateTime uploadedAt;

  @override
  String toString() {
    return 'AthleteFile(id: $id, trainerId: $trainerId, athleteId: $athleteId, fileName: $fileName, kind: $kind, contentType: $contentType, sizeBytes: $sizeBytes, storagePath: $storagePath, downloadUrl: $downloadUrl, uploadedAt: $uploadedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AthleteFileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.athleteId, athleteId) ||
                other.athleteId == athleteId) &&
            (identical(other.fileName, fileName) ||
                other.fileName == fileName) &&
            (identical(other.kind, kind) || other.kind == kind) &&
            (identical(other.contentType, contentType) ||
                other.contentType == contentType) &&
            (identical(other.sizeBytes, sizeBytes) ||
                other.sizeBytes == sizeBytes) &&
            (identical(other.storagePath, storagePath) ||
                other.storagePath == storagePath) &&
            (identical(other.downloadUrl, downloadUrl) ||
                other.downloadUrl == downloadUrl) &&
            (identical(other.uploadedAt, uploadedAt) ||
                other.uploadedAt == uploadedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      trainerId,
      athleteId,
      fileName,
      kind,
      contentType,
      sizeBytes,
      storagePath,
      downloadUrl,
      uploadedAt);

  /// Create a copy of AthleteFile
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AthleteFileImplCopyWith<_$AthleteFileImpl> get copyWith =>
      __$$AthleteFileImplCopyWithImpl<_$AthleteFileImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AthleteFileImplToJson(
      this,
    );
  }
}

abstract class _AthleteFile implements AthleteFile {
  const factory _AthleteFile(
          {required final String id,
          required final String trainerId,
          required final String athleteId,
          required final String fileName,
          required final AthleteFileKind kind,
          required final String contentType,
          required final int sizeBytes,
          required final String storagePath,
          required final String downloadUrl,
          @TimestampConverter() required final DateTime uploadedAt}) =
      _$AthleteFileImpl;

  factory _AthleteFile.fromJson(Map<String, dynamic> json) =
      _$AthleteFileImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  String get athleteId;
  @override
  String get fileName;
  @override
  AthleteFileKind get kind;
  @override
  String get contentType;
  @override
  int get sizeBytes;
  @override
  String get storagePath;
  @override
  String get downloadUrl;
  @override
  @TimestampConverter()
  DateTime get uploadedAt;

  /// Create a copy of AthleteFile
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AthleteFileImplCopyWith<_$AthleteFileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
