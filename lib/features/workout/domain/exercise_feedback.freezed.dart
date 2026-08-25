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
  /// Id del documento. Sale del PATH, no del cuerpo — misma trampa que
  /// documenta `SessionRepository._setLogFromDoc`.
  String get id => throw _privateConstructorUsedError;
  String get exerciseId => throw _privateConstructorUsedError;

  /// Denormalizado igual que en [SetLog]: el PF ve el reporte sin resolver
  /// el catálogo de ejercicios, y el nombre queda congelado al momento del
  /// reporte aunque el ejercicio se renombre después.
  String get exerciseName => throw _privateConstructorUsedError;

  /// Serie (1-based) sobre la que se reporta. `null` = comentario a nivel
  /// ejercicio, sin serie. Eso es exactamente lo que el chat no puede dar.
  int? get setNumber => throw _privateConstructorUsedError;

  /// Si algún día el enum crece, un cliente viejo muestra el reporte con la
  /// marca de `comment` en vez de esconderlo. Es la dirección de falla
  /// menos mala: perder el badge es recuperable, perder el reporte no.
  @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
  ExerciseFeedbackKind get kind => throw _privateConstructorUsedError;
  String? get text => throw _privateConstructorUsedError;

  /// URL HTTPS descargable de la foto, o null.
  String? get photoUrl => throw _privateConstructorUsedError;

  /// Object path en Storage (`sessionFeedback/{uid}/{sessionId}/{id}.{ext}`).
  /// Se guarda para poder BORRAR el objeto: sin él, borrar el documento deja
  /// la foto en el bucket con su token vivo para siempre.
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
      int? setNumber,
      @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
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
      int? setNumber,
      @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
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
      this.setNumber,
      @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
      required this.kind,
      this.text,
      this.photoUrl,
      this.photoPath,
      @TimestampConverter() required this.createdAt})
      : super._();

  factory _$ExerciseFeedbackImpl.fromJson(Map<String, dynamic> json) =>
      _$$ExerciseFeedbackImplFromJson(json);

  /// Id del documento. Sale del PATH, no del cuerpo — misma trampa que
  /// documenta `SessionRepository._setLogFromDoc`.
  @override
  final String id;
  @override
  final String exerciseId;

  /// Denormalizado igual que en [SetLog]: el PF ve el reporte sin resolver
  /// el catálogo de ejercicios, y el nombre queda congelado al momento del
  /// reporte aunque el ejercicio se renombre después.
  @override
  final String exerciseName;

  /// Serie (1-based) sobre la que se reporta. `null` = comentario a nivel
  /// ejercicio, sin serie. Eso es exactamente lo que el chat no puede dar.
  @override
  final int? setNumber;

  /// Si algún día el enum crece, un cliente viejo muestra el reporte con la
  /// marca de `comment` en vez de esconderlo. Es la dirección de falla
  /// menos mala: perder el badge es recuperable, perder el reporte no.
  @override
  @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
  final ExerciseFeedbackKind kind;
  @override
  final String? text;

  /// URL HTTPS descargable de la foto, o null.
  @override
  final String? photoUrl;

  /// Object path en Storage (`sessionFeedback/{uid}/{sessionId}/{id}.{ext}`).
  /// Se guarda para poder BORRAR el objeto: sin él, borrar el documento deja
  /// la foto en el bucket con su token vivo para siempre.
  @override
  final String? photoPath;
  @override
  @TimestampConverter()
  final DateTime createdAt;

  @override
  String toString() {
    return 'ExerciseFeedback(id: $id, exerciseId: $exerciseId, exerciseName: $exerciseName, setNumber: $setNumber, kind: $kind, text: $text, photoUrl: $photoUrl, photoPath: $photoPath, createdAt: $createdAt)';
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
      setNumber, kind, text, photoUrl, photoPath, createdAt);

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
          final int? setNumber,
          @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
          required final ExerciseFeedbackKind kind,
          final String? text,
          final String? photoUrl,
          final String? photoPath,
          @TimestampConverter() required final DateTime createdAt}) =
      _$ExerciseFeedbackImpl;
  const _ExerciseFeedback._() : super._();

  factory _ExerciseFeedback.fromJson(Map<String, dynamic> json) =
      _$ExerciseFeedbackImpl.fromJson;

  /// Id del documento. Sale del PATH, no del cuerpo — misma trampa que
  /// documenta `SessionRepository._setLogFromDoc`.
  @override
  String get id;
  @override
  String get exerciseId;

  /// Denormalizado igual que en [SetLog]: el PF ve el reporte sin resolver
  /// el catálogo de ejercicios, y el nombre queda congelado al momento del
  /// reporte aunque el ejercicio se renombre después.
  @override
  String get exerciseName;

  /// Serie (1-based) sobre la que se reporta. `null` = comentario a nivel
  /// ejercicio, sin serie. Eso es exactamente lo que el chat no puede dar.
  @override
  int? get setNumber;

  /// Si algún día el enum crece, un cliente viejo muestra el reporte con la
  /// marca de `comment` en vez de esconderlo. Es la dirección de falla
  /// menos mala: perder el badge es recuperable, perder el reporte no.
  @override
  @JsonKey(unknownEnumValue: ExerciseFeedbackKind.comment)
  ExerciseFeedbackKind get kind;
  @override
  String? get text;

  /// URL HTTPS descargable de la foto, o null.
  @override
  String? get photoUrl;

  /// Object path en Storage (`sessionFeedback/{uid}/{sessionId}/{id}.{ext}`).
  /// Se guarda para poder BORRAR el objeto: sin él, borrar el documento deja
  /// la foto en el bucket con su token vivo para siempre.
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
