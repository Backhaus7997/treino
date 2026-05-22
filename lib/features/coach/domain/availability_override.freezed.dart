// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'availability_override.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AvailabilityOverride _$AvailabilityOverrideFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'block':
      return AvailabilityOverrideBlock.fromJson(json);
    case 'extra':
      return AvailabilityOverrideExtra.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'type', 'AvailabilityOverride',
          'Invalid union type "${json['type']}"!');
  }
}

/// @nodoc
mixin _$AvailabilityOverride {
  String get id => throw _privateConstructorUsedError;
  String get trainerId => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get date => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)
        block,
    required TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)
        extra,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult? Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AvailabilityOverrideBlock value) block,
    required TResult Function(AvailabilityOverrideExtra value) extra,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AvailabilityOverrideBlock value)? block,
    TResult? Function(AvailabilityOverrideExtra value)? extra,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AvailabilityOverrideBlock value)? block,
    TResult Function(AvailabilityOverrideExtra value)? extra,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this AvailabilityOverride to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $AvailabilityOverrideCopyWith<AvailabilityOverride> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AvailabilityOverrideCopyWith<$Res> {
  factory $AvailabilityOverrideCopyWith(AvailabilityOverride value,
          $Res Function(AvailabilityOverride) then) =
      _$AvailabilityOverrideCopyWithImpl<$Res, AvailabilityOverride>;
  @useResult
  $Res call({String id, String trainerId, @TimestampConverter() DateTime date});
}

/// @nodoc
class _$AvailabilityOverrideCopyWithImpl<$Res,
        $Val extends AvailabilityOverride>
    implements $AvailabilityOverrideCopyWith<$Res> {
  _$AvailabilityOverrideCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? date = null,
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
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AvailabilityOverrideBlockImplCopyWith<$Res>
    implements $AvailabilityOverrideCopyWith<$Res> {
  factory _$$AvailabilityOverrideBlockImplCopyWith(
          _$AvailabilityOverrideBlockImpl value,
          $Res Function(_$AvailabilityOverrideBlockImpl) then) =
      __$$AvailabilityOverrideBlockImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String trainerId, @TimestampConverter() DateTime date});
}

/// @nodoc
class __$$AvailabilityOverrideBlockImplCopyWithImpl<$Res>
    extends _$AvailabilityOverrideCopyWithImpl<$Res,
        _$AvailabilityOverrideBlockImpl>
    implements _$$AvailabilityOverrideBlockImplCopyWith<$Res> {
  __$$AvailabilityOverrideBlockImplCopyWithImpl(
      _$AvailabilityOverrideBlockImpl _value,
      $Res Function(_$AvailabilityOverrideBlockImpl) _then)
      : super(_value, _then);

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? date = null,
  }) {
    return _then(_$AvailabilityOverrideBlockImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AvailabilityOverrideBlockImpl implements AvailabilityOverrideBlock {
  const _$AvailabilityOverrideBlockImpl(
      {required this.id,
      required this.trainerId,
      @TimestampConverter() required this.date,
      final String? $type})
      : $type = $type ?? 'block';

  factory _$AvailabilityOverrideBlockImpl.fromJson(Map<String, dynamic> json) =>
      _$$AvailabilityOverrideBlockImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  @TimestampConverter()
  final DateTime date;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'AvailabilityOverride.block(id: $id, trainerId: $trainerId, date: $date)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AvailabilityOverrideBlockImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.date, date) || other.date == date));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, trainerId, date);

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AvailabilityOverrideBlockImplCopyWith<_$AvailabilityOverrideBlockImpl>
      get copyWith => __$$AvailabilityOverrideBlockImplCopyWithImpl<
          _$AvailabilityOverrideBlockImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)
        block,
    required TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)
        extra,
  }) {
    return block(id, trainerId, date);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult? Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
  }) {
    return block?.call(id, trainerId, date);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
    required TResult orElse(),
  }) {
    if (block != null) {
      return block(id, trainerId, date);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AvailabilityOverrideBlock value) block,
    required TResult Function(AvailabilityOverrideExtra value) extra,
  }) {
    return block(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AvailabilityOverrideBlock value)? block,
    TResult? Function(AvailabilityOverrideExtra value)? extra,
  }) {
    return block?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AvailabilityOverrideBlock value)? block,
    TResult Function(AvailabilityOverrideExtra value)? extra,
    required TResult orElse(),
  }) {
    if (block != null) {
      return block(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$AvailabilityOverrideBlockImplToJson(
      this,
    );
  }
}

abstract class AvailabilityOverrideBlock implements AvailabilityOverride {
  const factory AvailabilityOverrideBlock(
          {required final String id,
          required final String trainerId,
          @TimestampConverter() required final DateTime date}) =
      _$AvailabilityOverrideBlockImpl;

  factory AvailabilityOverrideBlock.fromJson(Map<String, dynamic> json) =
      _$AvailabilityOverrideBlockImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  @TimestampConverter()
  DateTime get date;

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AvailabilityOverrideBlockImplCopyWith<_$AvailabilityOverrideBlockImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$AvailabilityOverrideExtraImplCopyWith<$Res>
    implements $AvailabilityOverrideCopyWith<$Res> {
  factory _$$AvailabilityOverrideExtraImplCopyWith(
          _$AvailabilityOverrideExtraImpl value,
          $Res Function(_$AvailabilityOverrideExtraImpl) then) =
      __$$AvailabilityOverrideExtraImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String trainerId,
      @TimestampConverter() DateTime date,
      int startHour,
      int startMinute,
      int endHour,
      int endMinute,
      int slotDurationMin});
}

/// @nodoc
class __$$AvailabilityOverrideExtraImplCopyWithImpl<$Res>
    extends _$AvailabilityOverrideCopyWithImpl<$Res,
        _$AvailabilityOverrideExtraImpl>
    implements _$$AvailabilityOverrideExtraImplCopyWith<$Res> {
  __$$AvailabilityOverrideExtraImplCopyWithImpl(
      _$AvailabilityOverrideExtraImpl _value,
      $Res Function(_$AvailabilityOverrideExtraImpl) _then)
      : super(_value, _then);

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? trainerId = null,
    Object? date = null,
    Object? startHour = null,
    Object? startMinute = null,
    Object? endHour = null,
    Object? endMinute = null,
    Object? slotDurationMin = null,
  }) {
    return _then(_$AvailabilityOverrideExtraImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      trainerId: null == trainerId
          ? _value.trainerId
          : trainerId // ignore: cast_nullable_to_non_nullable
              as String,
      date: null == date
          ? _value.date
          : date // ignore: cast_nullable_to_non_nullable
              as DateTime,
      startHour: null == startHour
          ? _value.startHour
          : startHour // ignore: cast_nullable_to_non_nullable
              as int,
      startMinute: null == startMinute
          ? _value.startMinute
          : startMinute // ignore: cast_nullable_to_non_nullable
              as int,
      endHour: null == endHour
          ? _value.endHour
          : endHour // ignore: cast_nullable_to_non_nullable
              as int,
      endMinute: null == endMinute
          ? _value.endMinute
          : endMinute // ignore: cast_nullable_to_non_nullable
              as int,
      slotDurationMin: null == slotDurationMin
          ? _value.slotDurationMin
          : slotDurationMin // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AvailabilityOverrideExtraImpl implements AvailabilityOverrideExtra {
  const _$AvailabilityOverrideExtraImpl(
      {required this.id,
      required this.trainerId,
      @TimestampConverter() required this.date,
      required this.startHour,
      required this.startMinute,
      required this.endHour,
      required this.endMinute,
      required this.slotDurationMin,
      final String? $type})
      : assert(
            slotDurationMin == 30 ||
                slotDurationMin == 60 ||
                slotDurationMin == 90 ||
                slotDurationMin == 120,
            'slotDurationMin must be one of {30, 60, 90, 120}'),
        $type = $type ?? 'extra';

  factory _$AvailabilityOverrideExtraImpl.fromJson(Map<String, dynamic> json) =>
      _$$AvailabilityOverrideExtraImplFromJson(json);

  @override
  final String id;
  @override
  final String trainerId;
  @override
  @TimestampConverter()
  final DateTime date;
  @override
  final int startHour;
  @override
  final int startMinute;
  @override
  final int endHour;
  @override
  final int endMinute;
  @override
  final int slotDurationMin;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'AvailabilityOverride.extra(id: $id, trainerId: $trainerId, date: $date, startHour: $startHour, startMinute: $startMinute, endHour: $endHour, endMinute: $endMinute, slotDurationMin: $slotDurationMin)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AvailabilityOverrideExtraImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.trainerId, trainerId) ||
                other.trainerId == trainerId) &&
            (identical(other.date, date) || other.date == date) &&
            (identical(other.startHour, startHour) ||
                other.startHour == startHour) &&
            (identical(other.startMinute, startMinute) ||
                other.startMinute == startMinute) &&
            (identical(other.endHour, endHour) || other.endHour == endHour) &&
            (identical(other.endMinute, endMinute) ||
                other.endMinute == endMinute) &&
            (identical(other.slotDurationMin, slotDurationMin) ||
                other.slotDurationMin == slotDurationMin));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, trainerId, date, startHour,
      startMinute, endHour, endMinute, slotDurationMin);

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$AvailabilityOverrideExtraImplCopyWith<_$AvailabilityOverrideExtraImpl>
      get copyWith => __$$AvailabilityOverrideExtraImplCopyWithImpl<
          _$AvailabilityOverrideExtraImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)
        block,
    required TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)
        extra,
  }) {
    return extra(id, trainerId, date, startHour, startMinute, endHour,
        endMinute, slotDurationMin);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult? Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
  }) {
    return extra?.call(id, trainerId, date, startHour, startMinute, endHour,
        endMinute, slotDurationMin);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String id, String trainerId, @TimestampConverter() DateTime date)?
        block,
    TResult Function(
            String id,
            String trainerId,
            @TimestampConverter() DateTime date,
            int startHour,
            int startMinute,
            int endHour,
            int endMinute,
            int slotDurationMin)?
        extra,
    required TResult orElse(),
  }) {
    if (extra != null) {
      return extra(id, trainerId, date, startHour, startMinute, endHour,
          endMinute, slotDurationMin);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(AvailabilityOverrideBlock value) block,
    required TResult Function(AvailabilityOverrideExtra value) extra,
  }) {
    return extra(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(AvailabilityOverrideBlock value)? block,
    TResult? Function(AvailabilityOverrideExtra value)? extra,
  }) {
    return extra?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(AvailabilityOverrideBlock value)? block,
    TResult Function(AvailabilityOverrideExtra value)? extra,
    required TResult orElse(),
  }) {
    if (extra != null) {
      return extra(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$AvailabilityOverrideExtraImplToJson(
      this,
    );
  }
}

abstract class AvailabilityOverrideExtra implements AvailabilityOverride {
  const factory AvailabilityOverrideExtra(
      {required final String id,
      required final String trainerId,
      @TimestampConverter() required final DateTime date,
      required final int startHour,
      required final int startMinute,
      required final int endHour,
      required final int endMinute,
      required final int slotDurationMin}) = _$AvailabilityOverrideExtraImpl;

  factory AvailabilityOverrideExtra.fromJson(Map<String, dynamic> json) =
      _$AvailabilityOverrideExtraImpl.fromJson;

  @override
  String get id;
  @override
  String get trainerId;
  @override
  @TimestampConverter()
  DateTime get date;
  int get startHour;
  int get startMinute;
  int get endHour;
  int get endMinute;
  int get slotDurationMin;

  /// Create a copy of AvailabilityOverride
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$AvailabilityOverrideExtraImplCopyWith<_$AvailabilityOverrideExtraImpl>
      get copyWith => throw _privateConstructorUsedError;
}
