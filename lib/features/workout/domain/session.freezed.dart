// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Session _$SessionFromJson(Map<String, dynamic> json) {
  return _Session.fromJson(json);
}

/// @nodoc
mixin _$Session {
  String get id => throw _privateConstructorUsedError;
  String get uid => throw _privateConstructorUsedError;
  String get routineId => throw _privateConstructorUsedError;
  String get routineName => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get startedAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get finishedAt => throw _privateConstructorUsedError;
  double get totalVolumeKg => throw _privateConstructorUsedError;
  int get durationMin => throw _privateConstructorUsedError;
  SessionStatus get status => throw _privateConstructorUsedError;
  int get dayNumber => throw _privateConstructorUsedError;
  bool get wasFullyCompleted =>
      throw _privateConstructorUsedError; // Periodization (Model B): 0-based week of the plan this session belongs to.
// @Default(0) keeps single-week sessions intact and retro-compatible.
  int get weekNumber =>
      throw _privateConstructorUsedError; // Cuántos reportes (#628) tiene esta sesión, por kind. Lo escribe SÓLO
// `maintainSessionFeedbackCounters` (functions/), recontando desde la
// subcolección; las reglas rechazan que un cliente lo toque.
//
// Existe para que el historial del PF marque de un vistazo qué sesiones
// traen una molestia o una nota. Sin esto la marca cuesta una lectura de
// subcolección por fila.
//
// `@Default({})` y no `required`: las sesiones anteriores al agregado no
// tienen el campo, y una sesión sin reportes tampoco lo tiene — el mapa
// vacío es la respuesta correcta para las dos. Ojo con lo que NO significa:
// vacío es "ningún reporte", no "no se pudo leer".
//
// ⚠️ `includeToJson: false` — ESTE CAMPO SE LEE, NO SE ESCRIBE.
//
// Sin esto, `SessionRepository.create()` —que es `ref.set(session.toJson())`,
// el único write de una Session ENTERA— mandaba `feedbackCounts: {}` en
// cada sesión nueva. Y la regla de Firestore rechaza la clave presente en
// el `create`, así que el servidor devolvía `permission-denied` y el
// atleta veía "No pudimos iniciar la sesión": **no se podía empezar a
// entrenar**.
//
// El arreglo correcto no era ablandar la regla para aceptar el mapa vacío,
// sino que el cliente deje de mandarlo. El campo es del backend: lo escribe
// sólo `maintainSessionFeedbackCounters` recontando desde
// `exerciseFeedback`, y que el modelo no pueda emitirlo hace que eso sea
// cierto por construcción y no por disciplina.
//
// Sacarlo del `toJson` es seguro porque `create()` escribe un documento
// NUEVO: no hay contador que pisar. `finish()` y el barrido usan `update()`
// con campos explícitos, y los otros `set(x.toJson())` del repositorio son
// de `SetLog`, no de `Session`.
  @JsonKey(includeToJson: false)
  @FeedbackCountsConverter()
  Map<ExerciseFeedbackKind, int> get feedbackCounts =>
      throw _privateConstructorUsedError;

  /// Serializes this Session to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionCopyWith<Session> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionCopyWith<$Res> {
  factory $SessionCopyWith(Session value, $Res Function(Session) then) =
      _$SessionCopyWithImpl<$Res, Session>;
  @useResult
  $Res call(
      {String id,
      String uid,
      String routineId,
      String routineName,
      @TimestampConverter() DateTime startedAt,
      @TimestampConverter() DateTime? finishedAt,
      double totalVolumeKg,
      int durationMin,
      SessionStatus status,
      int dayNumber,
      bool wasFullyCompleted,
      int weekNumber,
      @JsonKey(includeToJson: false)
      @FeedbackCountsConverter()
      Map<ExerciseFeedbackKind, int> feedbackCounts});
}

/// @nodoc
class _$SessionCopyWithImpl<$Res, $Val extends Session>
    implements $SessionCopyWith<$Res> {
  _$SessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? uid = null,
    Object? routineId = null,
    Object? routineName = null,
    Object? startedAt = null,
    Object? finishedAt = freezed,
    Object? totalVolumeKg = null,
    Object? durationMin = null,
    Object? status = null,
    Object? dayNumber = null,
    Object? wasFullyCompleted = null,
    Object? weekNumber = null,
    Object? feedbackCounts = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      routineId: null == routineId
          ? _value.routineId
          : routineId // ignore: cast_nullable_to_non_nullable
              as String,
      routineName: null == routineName
          ? _value.routineName
          : routineName // ignore: cast_nullable_to_non_nullable
              as String,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      finishedAt: freezed == finishedAt
          ? _value.finishedAt
          : finishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVolumeKg: null == totalVolumeKg
          ? _value.totalVolumeKg
          : totalVolumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SessionStatus,
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      wasFullyCompleted: null == wasFullyCompleted
          ? _value.wasFullyCompleted
          : wasFullyCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      weekNumber: null == weekNumber
          ? _value.weekNumber
          : weekNumber // ignore: cast_nullable_to_non_nullable
              as int,
      feedbackCounts: null == feedbackCounts
          ? _value.feedbackCounts
          : feedbackCounts // ignore: cast_nullable_to_non_nullable
              as Map<ExerciseFeedbackKind, int>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SessionImplCopyWith<$Res> implements $SessionCopyWith<$Res> {
  factory _$$SessionImplCopyWith(
          _$SessionImpl value, $Res Function(_$SessionImpl) then) =
      __$$SessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String uid,
      String routineId,
      String routineName,
      @TimestampConverter() DateTime startedAt,
      @TimestampConverter() DateTime? finishedAt,
      double totalVolumeKg,
      int durationMin,
      SessionStatus status,
      int dayNumber,
      bool wasFullyCompleted,
      int weekNumber,
      @JsonKey(includeToJson: false)
      @FeedbackCountsConverter()
      Map<ExerciseFeedbackKind, int> feedbackCounts});
}

/// @nodoc
class __$$SessionImplCopyWithImpl<$Res>
    extends _$SessionCopyWithImpl<$Res, _$SessionImpl>
    implements _$$SessionImplCopyWith<$Res> {
  __$$SessionImplCopyWithImpl(
      _$SessionImpl _value, $Res Function(_$SessionImpl) _then)
      : super(_value, _then);

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? uid = null,
    Object? routineId = null,
    Object? routineName = null,
    Object? startedAt = null,
    Object? finishedAt = freezed,
    Object? totalVolumeKg = null,
    Object? durationMin = null,
    Object? status = null,
    Object? dayNumber = null,
    Object? wasFullyCompleted = null,
    Object? weekNumber = null,
    Object? feedbackCounts = null,
  }) {
    return _then(_$SessionImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      uid: null == uid
          ? _value.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      routineId: null == routineId
          ? _value.routineId
          : routineId // ignore: cast_nullable_to_non_nullable
              as String,
      routineName: null == routineName
          ? _value.routineName
          : routineName // ignore: cast_nullable_to_non_nullable
              as String,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      finishedAt: freezed == finishedAt
          ? _value.finishedAt
          : finishedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      totalVolumeKg: null == totalVolumeKg
          ? _value.totalVolumeKg
          : totalVolumeKg // ignore: cast_nullable_to_non_nullable
              as double,
      durationMin: null == durationMin
          ? _value.durationMin
          : durationMin // ignore: cast_nullable_to_non_nullable
              as int,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as SessionStatus,
      dayNumber: null == dayNumber
          ? _value.dayNumber
          : dayNumber // ignore: cast_nullable_to_non_nullable
              as int,
      wasFullyCompleted: null == wasFullyCompleted
          ? _value.wasFullyCompleted
          : wasFullyCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      weekNumber: null == weekNumber
          ? _value.weekNumber
          : weekNumber // ignore: cast_nullable_to_non_nullable
              as int,
      feedbackCounts: null == feedbackCounts
          ? _value._feedbackCounts
          : feedbackCounts // ignore: cast_nullable_to_non_nullable
              as Map<ExerciseFeedbackKind, int>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionImpl implements _Session {
  const _$SessionImpl(
      {required this.id,
      required this.uid,
      required this.routineId,
      required this.routineName,
      @TimestampConverter() required this.startedAt,
      @TimestampConverter() this.finishedAt,
      this.totalVolumeKg = 0.0,
      this.durationMin = 0,
      required this.status,
      this.dayNumber = 1,
      this.wasFullyCompleted = false,
      this.weekNumber = 0,
      @JsonKey(includeToJson: false)
      @FeedbackCountsConverter()
      final Map<ExerciseFeedbackKind, int> feedbackCounts =
          const <ExerciseFeedbackKind, int>{}})
      : _feedbackCounts = feedbackCounts;

  factory _$SessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionImplFromJson(json);

  @override
  final String id;
  @override
  final String uid;
  @override
  final String routineId;
  @override
  final String routineName;
  @override
  @TimestampConverter()
  final DateTime startedAt;
  @override
  @TimestampConverter()
  final DateTime? finishedAt;
  @override
  @JsonKey()
  final double totalVolumeKg;
  @override
  @JsonKey()
  final int durationMin;
  @override
  final SessionStatus status;
  @override
  @JsonKey()
  final int dayNumber;
  @override
  @JsonKey()
  final bool wasFullyCompleted;
// Periodization (Model B): 0-based week of the plan this session belongs to.
// @Default(0) keeps single-week sessions intact and retro-compatible.
  @override
  @JsonKey()
  final int weekNumber;
// Cuántos reportes (#628) tiene esta sesión, por kind. Lo escribe SÓLO
// `maintainSessionFeedbackCounters` (functions/), recontando desde la
// subcolección; las reglas rechazan que un cliente lo toque.
//
// Existe para que el historial del PF marque de un vistazo qué sesiones
// traen una molestia o una nota. Sin esto la marca cuesta una lectura de
// subcolección por fila.
//
// `@Default({})` y no `required`: las sesiones anteriores al agregado no
// tienen el campo, y una sesión sin reportes tampoco lo tiene — el mapa
// vacío es la respuesta correcta para las dos. Ojo con lo que NO significa:
// vacío es "ningún reporte", no "no se pudo leer".
//
// ⚠️ `includeToJson: false` — ESTE CAMPO SE LEE, NO SE ESCRIBE.
//
// Sin esto, `SessionRepository.create()` —que es `ref.set(session.toJson())`,
// el único write de una Session ENTERA— mandaba `feedbackCounts: {}` en
// cada sesión nueva. Y la regla de Firestore rechaza la clave presente en
// el `create`, así que el servidor devolvía `permission-denied` y el
// atleta veía "No pudimos iniciar la sesión": **no se podía empezar a
// entrenar**.
//
// El arreglo correcto no era ablandar la regla para aceptar el mapa vacío,
// sino que el cliente deje de mandarlo. El campo es del backend: lo escribe
// sólo `maintainSessionFeedbackCounters` recontando desde
// `exerciseFeedback`, y que el modelo no pueda emitirlo hace que eso sea
// cierto por construcción y no por disciplina.
//
// Sacarlo del `toJson` es seguro porque `create()` escribe un documento
// NUEVO: no hay contador que pisar. `finish()` y el barrido usan `update()`
// con campos explícitos, y los otros `set(x.toJson())` del repositorio son
// de `SetLog`, no de `Session`.
  final Map<ExerciseFeedbackKind, int> _feedbackCounts;
// Cuántos reportes (#628) tiene esta sesión, por kind. Lo escribe SÓLO
// `maintainSessionFeedbackCounters` (functions/), recontando desde la
// subcolección; las reglas rechazan que un cliente lo toque.
//
// Existe para que el historial del PF marque de un vistazo qué sesiones
// traen una molestia o una nota. Sin esto la marca cuesta una lectura de
// subcolección por fila.
//
// `@Default({})` y no `required`: las sesiones anteriores al agregado no
// tienen el campo, y una sesión sin reportes tampoco lo tiene — el mapa
// vacío es la respuesta correcta para las dos. Ojo con lo que NO significa:
// vacío es "ningún reporte", no "no se pudo leer".
//
// ⚠️ `includeToJson: false` — ESTE CAMPO SE LEE, NO SE ESCRIBE.
//
// Sin esto, `SessionRepository.create()` —que es `ref.set(session.toJson())`,
// el único write de una Session ENTERA— mandaba `feedbackCounts: {}` en
// cada sesión nueva. Y la regla de Firestore rechaza la clave presente en
// el `create`, así que el servidor devolvía `permission-denied` y el
// atleta veía "No pudimos iniciar la sesión": **no se podía empezar a
// entrenar**.
//
// El arreglo correcto no era ablandar la regla para aceptar el mapa vacío,
// sino que el cliente deje de mandarlo. El campo es del backend: lo escribe
// sólo `maintainSessionFeedbackCounters` recontando desde
// `exerciseFeedback`, y que el modelo no pueda emitirlo hace que eso sea
// cierto por construcción y no por disciplina.
//
// Sacarlo del `toJson` es seguro porque `create()` escribe un documento
// NUEVO: no hay contador que pisar. `finish()` y el barrido usan `update()`
// con campos explícitos, y los otros `set(x.toJson())` del repositorio son
// de `SetLog`, no de `Session`.
  @override
  @JsonKey(includeToJson: false)
  @FeedbackCountsConverter()
  Map<ExerciseFeedbackKind, int> get feedbackCounts {
    if (_feedbackCounts is EqualUnmodifiableMapView) return _feedbackCounts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_feedbackCounts);
  }

  @override
  String toString() {
    return 'Session(id: $id, uid: $uid, routineId: $routineId, routineName: $routineName, startedAt: $startedAt, finishedAt: $finishedAt, totalVolumeKg: $totalVolumeKg, durationMin: $durationMin, status: $status, dayNumber: $dayNumber, wasFullyCompleted: $wasFullyCompleted, weekNumber: $weekNumber, feedbackCounts: $feedbackCounts)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.routineId, routineId) ||
                other.routineId == routineId) &&
            (identical(other.routineName, routineName) ||
                other.routineName == routineName) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.finishedAt, finishedAt) ||
                other.finishedAt == finishedAt) &&
            (identical(other.totalVolumeKg, totalVolumeKg) ||
                other.totalVolumeKg == totalVolumeKg) &&
            (identical(other.durationMin, durationMin) ||
                other.durationMin == durationMin) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.dayNumber, dayNumber) ||
                other.dayNumber == dayNumber) &&
            (identical(other.wasFullyCompleted, wasFullyCompleted) ||
                other.wasFullyCompleted == wasFullyCompleted) &&
            (identical(other.weekNumber, weekNumber) ||
                other.weekNumber == weekNumber) &&
            const DeepCollectionEquality()
                .equals(other._feedbackCounts, _feedbackCounts));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      uid,
      routineId,
      routineName,
      startedAt,
      finishedAt,
      totalVolumeKg,
      durationMin,
      status,
      dayNumber,
      wasFullyCompleted,
      weekNumber,
      const DeepCollectionEquality().hash(_feedbackCounts));

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      __$$SessionImplCopyWithImpl<_$SessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionImplToJson(
      this,
    );
  }
}

abstract class _Session implements Session {
  const factory _Session(
      {required final String id,
      required final String uid,
      required final String routineId,
      required final String routineName,
      @TimestampConverter() required final DateTime startedAt,
      @TimestampConverter() final DateTime? finishedAt,
      final double totalVolumeKg,
      final int durationMin,
      required final SessionStatus status,
      final int dayNumber,
      final bool wasFullyCompleted,
      final int weekNumber,
      @JsonKey(includeToJson: false)
      @FeedbackCountsConverter()
      final Map<ExerciseFeedbackKind, int> feedbackCounts}) = _$SessionImpl;

  factory _Session.fromJson(Map<String, dynamic> json) = _$SessionImpl.fromJson;

  @override
  String get id;
  @override
  String get uid;
  @override
  String get routineId;
  @override
  String get routineName;
  @override
  @TimestampConverter()
  DateTime get startedAt;
  @override
  @TimestampConverter()
  DateTime? get finishedAt;
  @override
  double get totalVolumeKg;
  @override
  int get durationMin;
  @override
  SessionStatus get status;
  @override
  int get dayNumber;
  @override
  bool
      get wasFullyCompleted; // Periodization (Model B): 0-based week of the plan this session belongs to.
// @Default(0) keeps single-week sessions intact and retro-compatible.
  @override
  int get weekNumber; // Cuántos reportes (#628) tiene esta sesión, por kind. Lo escribe SÓLO
// `maintainSessionFeedbackCounters` (functions/), recontando desde la
// subcolección; las reglas rechazan que un cliente lo toque.
//
// Existe para que el historial del PF marque de un vistazo qué sesiones
// traen una molestia o una nota. Sin esto la marca cuesta una lectura de
// subcolección por fila.
//
// `@Default({})` y no `required`: las sesiones anteriores al agregado no
// tienen el campo, y una sesión sin reportes tampoco lo tiene — el mapa
// vacío es la respuesta correcta para las dos. Ojo con lo que NO significa:
// vacío es "ningún reporte", no "no se pudo leer".
//
// ⚠️ `includeToJson: false` — ESTE CAMPO SE LEE, NO SE ESCRIBE.
//
// Sin esto, `SessionRepository.create()` —que es `ref.set(session.toJson())`,
// el único write de una Session ENTERA— mandaba `feedbackCounts: {}` en
// cada sesión nueva. Y la regla de Firestore rechaza la clave presente en
// el `create`, así que el servidor devolvía `permission-denied` y el
// atleta veía "No pudimos iniciar la sesión": **no se podía empezar a
// entrenar**.
//
// El arreglo correcto no era ablandar la regla para aceptar el mapa vacío,
// sino que el cliente deje de mandarlo. El campo es del backend: lo escribe
// sólo `maintainSessionFeedbackCounters` recontando desde
// `exerciseFeedback`, y que el modelo no pueda emitirlo hace que eso sea
// cierto por construcción y no por disciplina.
//
// Sacarlo del `toJson` es seguro porque `create()` escribe un documento
// NUEVO: no hay contador que pisar. `finish()` y el barrido usan `update()`
// con campos explícitos, y los otros `set(x.toJson())` del repositorio son
// de `SetLog`, no de `Session`.
  @override
  @JsonKey(includeToJson: false)
  @FeedbackCountsConverter()
  Map<ExerciseFeedbackKind, int> get feedbackCounts;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
