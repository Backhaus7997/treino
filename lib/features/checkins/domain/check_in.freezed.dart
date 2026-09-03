// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'check_in.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CheckIn _$CheckInFromJson(Map<String, dynamic> json) {
  return _CheckIn.fromJson(json);
}

/// @nodoc
mixin _$CheckIn {
  /// Fecha local `YYYY-MM-DD` a la que pertenece el registro. Campo real del
  /// documento (ya no se deriva del id) — es sobre él que consulta el rango
  /// de la curva de tendencia, sin índice compuesto.
  String get date => throw _privateConstructorUsedError;

  /// Cómo se sintió. Único campo obligatorio del registro.
  CheckInFeeling get feeling => throw _privateConstructorUsedError;

  /// Si reportó dolor o molestia. Se guarda aparte de [painAreas] porque
  /// "me duele pero no sé bien dónde" es una respuesta válida y distinta de
  /// "no me duele".
  bool get hasPain => throw _privateConstructorUsedError;

  /// Zonas del dolor, en el vocabulario de [MuscleGroup]. Vacío cuando
  /// [hasPain] es `false` o cuando el usuario no precisó la zona.
  @MuscleGroupKeysConverter()
  List<MuscleGroup> get painAreas => throw _privateConstructorUsedError;

  /// Nota libre opcional, hasta [kCheckInNoteMaxLength] caracteres.
  /// Complementa el dato estructurado; no lo reemplaza (el texto libre no
  /// se agrega y sin agregación no hay curva).
  String? get note => throw _privateConstructorUsedError;

  /// Cuándo se registró, en UTC. [date] es la fecha LOCAL: cerca de
  /// medianoche los dos pueden caer en días distintos, y eso es correcto —
  /// el usuario piensa en su día, no en el de UTC.
  @TimestampConverter()
  DateTime get recordedAt => throw _privateConstructorUsedError;

  /// Sesión que originó el registro, cuando se capturó al terminar de
  /// entrenar. `null` para el check-in diario, que no sale de una sesión.
  ///
  /// Es también lo que distingue "otro entreno del mismo día" de "el mismo
  /// registro editado": el resumen post-sesión sólo reconoce como propio el
  /// check-in cuyo `sessionId` coincide con el suyo.
  String? get sessionId => throw _privateConstructorUsedError;

  /// Id del documento. Ausente hasta que el repositorio lo persiste; lo
  /// inyecta la lectura. NO viaja en el body — el id ya lo lleva el doc.
  @JsonKey(includeToJson: false, includeFromJson: false)
  String? get id => throw _privateConstructorUsedError;

  /// Serializes this CheckIn to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CheckInCopyWith<CheckIn> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CheckInCopyWith<$Res> {
  factory $CheckInCopyWith(CheckIn value, $Res Function(CheckIn) then) =
      _$CheckInCopyWithImpl<$Res, CheckIn>;
  @useResult
  $Res call(
      {String date,
      CheckInFeeling feeling,
      bool hasPain,
      @MuscleGroupKeysConverter() List<MuscleGroup> painAreas,
      String? note,
      @TimestampConverter() DateTime recordedAt,
      String? sessionId,
      @JsonKey(includeToJson: false, includeFromJson: false) String? id});
}

/// @nodoc
class _$CheckInCopyWithImpl<$Res, $Val extends CheckIn>
    implements $CheckInCopyWith<$Res> {
  _$CheckInCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? feeling = null,
    Object? hasPain = null,
    Object? painAreas = null,
    Object? note = freezed,
    Object? recordedAt = null,
    Object? sessionId = freezed,
    Object? id = freezed,
  }) {
    return _then(_value.copyWith(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      feeling: null == feeling
          ? _value.feeling
          : feeling // ignore: cast_nullable_to_non_nullable
              as CheckInFeeling,
      hasPain: null == hasPain
          ? _value.hasPain
          : hasPain // ignore: cast_nullable_to_non_nullable
              as bool,
      painAreas: null == painAreas
          ? _value.painAreas
          : painAreas // ignore: cast_nullable_to_non_nullable
              as List<MuscleGroup>,
      note: freezed == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String?,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CheckInImplCopyWith<$Res> implements $CheckInCopyWith<$Res> {
  factory _$$CheckInImplCopyWith(
          _$CheckInImpl value, $Res Function(_$CheckInImpl) then) =
      __$$CheckInImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String date,
      CheckInFeeling feeling,
      bool hasPain,
      @MuscleGroupKeysConverter() List<MuscleGroup> painAreas,
      String? note,
      @TimestampConverter() DateTime recordedAt,
      String? sessionId,
      @JsonKey(includeToJson: false, includeFromJson: false) String? id});
}

/// @nodoc
class __$$CheckInImplCopyWithImpl<$Res>
    extends _$CheckInCopyWithImpl<$Res, _$CheckInImpl>
    implements _$$CheckInImplCopyWith<$Res> {
  __$$CheckInImplCopyWithImpl(
      _$CheckInImpl _value, $Res Function(_$CheckInImpl) _then)
      : super(_value, _then);

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? date = null,
    Object? feeling = null,
    Object? hasPain = null,
    Object? painAreas = null,
    Object? note = freezed,
    Object? recordedAt = null,
    Object? sessionId = freezed,
    Object? id = freezed,
  }) {
    return _then(_$CheckInImpl(
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as String,
      feeling: null == feeling
          ? _value.feeling
          : feeling // ignore: cast_nullable_to_non_nullable
              as CheckInFeeling,
      hasPain: null == hasPain
          ? _value.hasPain
          : hasPain // ignore: cast_nullable_to_non_nullable
              as bool,
      painAreas: null == painAreas
          ? _value._painAreas
          : painAreas // ignore: cast_nullable_to_non_nullable
              as List<MuscleGroup>,
      note: freezed == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String?,
      recordedAt: null == recordedAt
          ? _value.recordedAt
          : recordedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      sessionId: freezed == sessionId
          ? _value.sessionId
          : sessionId // ignore: cast_nullable_to_non_nullable
              as String?,
      id: freezed == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CheckInImpl implements _CheckIn {
  const _$CheckInImpl(
      {required this.date,
      required this.feeling,
      this.hasPain = false,
      @MuscleGroupKeysConverter()
      final List<MuscleGroup> painAreas = const <MuscleGroup>[],
      this.note,
      @TimestampConverter() required this.recordedAt,
      this.sessionId,
      @JsonKey(includeToJson: false, includeFromJson: false) this.id})
      : _painAreas = painAreas;

  factory _$CheckInImpl.fromJson(Map<String, dynamic> json) =>
      _$$CheckInImplFromJson(json);

  /// Fecha local `YYYY-MM-DD` a la que pertenece el registro. Campo real del
  /// documento (ya no se deriva del id) — es sobre él que consulta el rango
  /// de la curva de tendencia, sin índice compuesto.
  @override
  final String date;

  /// Cómo se sintió. Único campo obligatorio del registro.
  @override
  final CheckInFeeling feeling;

  /// Si reportó dolor o molestia. Se guarda aparte de [painAreas] porque
  /// "me duele pero no sé bien dónde" es una respuesta válida y distinta de
  /// "no me duele".
  @override
  @JsonKey()
  final bool hasPain;

  /// Zonas del dolor, en el vocabulario de [MuscleGroup]. Vacío cuando
  /// [hasPain] es `false` o cuando el usuario no precisó la zona.
  final List<MuscleGroup> _painAreas;

  /// Zonas del dolor, en el vocabulario de [MuscleGroup]. Vacío cuando
  /// [hasPain] es `false` o cuando el usuario no precisó la zona.
  @override
  @JsonKey()
  @MuscleGroupKeysConverter()
  List<MuscleGroup> get painAreas {
    if (_painAreas is EqualUnmodifiableListView) return _painAreas;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_painAreas);
  }

  /// Nota libre opcional, hasta [kCheckInNoteMaxLength] caracteres.
  /// Complementa el dato estructurado; no lo reemplaza (el texto libre no
  /// se agrega y sin agregación no hay curva).
  @override
  final String? note;

  /// Cuándo se registró, en UTC. [date] es la fecha LOCAL: cerca de
  /// medianoche los dos pueden caer en días distintos, y eso es correcto —
  /// el usuario piensa en su día, no en el de UTC.
  @override
  @TimestampConverter()
  final DateTime recordedAt;

  /// Sesión que originó el registro, cuando se capturó al terminar de
  /// entrenar. `null` para el check-in diario, que no sale de una sesión.
  ///
  /// Es también lo que distingue "otro entreno del mismo día" de "el mismo
  /// registro editado": el resumen post-sesión sólo reconoce como propio el
  /// check-in cuyo `sessionId` coincide con el suyo.
  @override
  final String? sessionId;

  /// Id del documento. Ausente hasta que el repositorio lo persiste; lo
  /// inyecta la lectura. NO viaja en el body — el id ya lo lleva el doc.
  @override
  @JsonKey(includeToJson: false, includeFromJson: false)
  final String? id;

  @override
  String toString() {
    return 'CheckIn(date: $date, feeling: $feeling, hasPain: $hasPain, painAreas: $painAreas, note: $note, recordedAt: $recordedAt, sessionId: $sessionId, id: $id)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CheckInImpl &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.feeling, feeling) || other.feeling == feeling) &&
            (identical(other.hasPain, hasPain) || other.hasPain == hasPain) &&
            const DeepCollectionEquality()
                .equals(other._painAreas, _painAreas) &&
            (identical(other.note, note) || other.note == note) &&
            (identical(other.recordedAt, recordedAt) ||
                other.recordedAt == recordedAt) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.id, id) || other.id == id));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      date,
      feeling,
      hasPain,
      const DeepCollectionEquality().hash(_painAreas),
      note,
      recordedAt,
      sessionId,
      id);

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CheckInImplCopyWith<_$CheckInImpl> get copyWith =>
      __$$CheckInImplCopyWithImpl<_$CheckInImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CheckInImplToJson(
      this,
    );
  }
}

abstract class _CheckIn implements CheckIn {
  const factory _CheckIn(
      {required final String date,
      required final CheckInFeeling feeling,
      final bool hasPain,
      @MuscleGroupKeysConverter() final List<MuscleGroup> painAreas,
      final String? note,
      @TimestampConverter() required final DateTime recordedAt,
      final String? sessionId,
      @JsonKey(includeToJson: false, includeFromJson: false)
      final String? id}) = _$CheckInImpl;

  factory _CheckIn.fromJson(Map<String, dynamic> json) = _$CheckInImpl.fromJson;

  /// Fecha local `YYYY-MM-DD` a la que pertenece el registro. Campo real del
  /// documento (ya no se deriva del id) — es sobre él que consulta el rango
  /// de la curva de tendencia, sin índice compuesto.
  @override
  String get date;

  /// Cómo se sintió. Único campo obligatorio del registro.
  @override
  CheckInFeeling get feeling;

  /// Si reportó dolor o molestia. Se guarda aparte de [painAreas] porque
  /// "me duele pero no sé bien dónde" es una respuesta válida y distinta de
  /// "no me duele".
  @override
  bool get hasPain;

  /// Zonas del dolor, en el vocabulario de [MuscleGroup]. Vacío cuando
  /// [hasPain] es `false` o cuando el usuario no precisó la zona.
  @override
  @MuscleGroupKeysConverter()
  List<MuscleGroup> get painAreas;

  /// Nota libre opcional, hasta [kCheckInNoteMaxLength] caracteres.
  /// Complementa el dato estructurado; no lo reemplaza (el texto libre no
  /// se agrega y sin agregación no hay curva).
  @override
  String? get note;

  /// Cuándo se registró, en UTC. [date] es la fecha LOCAL: cerca de
  /// medianoche los dos pueden caer en días distintos, y eso es correcto —
  /// el usuario piensa en su día, no en el de UTC.
  @override
  @TimestampConverter()
  DateTime get recordedAt;

  /// Sesión que originó el registro, cuando se capturó al terminar de
  /// entrenar. `null` para el check-in diario, que no sale de una sesión.
  ///
  /// Es también lo que distingue "otro entreno del mismo día" de "el mismo
  /// registro editado": el resumen post-sesión sólo reconoce como propio el
  /// check-in cuyo `sessionId` coincide con el suyo.
  @override
  String? get sessionId;

  /// Id del documento. Ausente hasta que el repositorio lo persiste; lo
  /// inyecta la lectura. NO viaja en el body — el id ya lo lleva el doc.
  @override
  @JsonKey(includeToJson: false, includeFromJson: false)
  String? get id;

  /// Create a copy of CheckIn
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CheckInImplCopyWith<_$CheckInImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
