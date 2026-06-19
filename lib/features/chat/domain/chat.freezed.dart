// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Chat _$ChatFromJson(Map<String, dynamic> json) {
  return _Chat.fromJson(json);
}

/// @nodoc
mixin _$Chat {
  String get chatId => throw _privateConstructorUsedError;
  List<String> get members => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime get createdAt => throw _privateConstructorUsedError;
  @TimestampConverter()
  DateTime? get lastMessageAt => throw _privateConstructorUsedError;
  String? get lastMessageText => throw _privateConstructorUsedError;
  String? get lastMessageSenderId => throw _privateConstructorUsedError;
  @TimestampMapConverter()
  Map<String, DateTime>? get lastRead => throw _privateConstructorUsedError;

  /// Serializes this Chat to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Chat
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatCopyWith<Chat> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatCopyWith<$Res> {
  factory $ChatCopyWith(Chat value, $Res Function(Chat) then) =
      _$ChatCopyWithImpl<$Res, Chat>;
  @useResult
  $Res call(
      {String chatId,
      List<String> members,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime? lastMessageAt,
      String? lastMessageText,
      String? lastMessageSenderId,
      @TimestampMapConverter() Map<String, DateTime>? lastRead});
}

/// @nodoc
class _$ChatCopyWithImpl<$Res, $Val extends Chat>
    implements $ChatCopyWith<$Res> {
  _$ChatCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Chat
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? chatId = null,
    Object? members = null,
    Object? createdAt = null,
    Object? lastMessageAt = freezed,
    Object? lastMessageText = freezed,
    Object? lastMessageSenderId = freezed,
    Object? lastRead = freezed,
  }) {
    return _then(_value.copyWith(
      chatId: null == chatId
          ? _value.chatId
          : chatId // ignore: cast_nullable_to_non_nullable
              as String,
      members: null == members
          ? _value.members
          : members // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastMessageAt: freezed == lastMessageAt
          ? _value.lastMessageAt
          : lastMessageAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMessageText: freezed == lastMessageText
          ? _value.lastMessageText
          : lastMessageText // ignore: cast_nullable_to_non_nullable
              as String?,
      lastMessageSenderId: freezed == lastMessageSenderId
          ? _value.lastMessageSenderId
          : lastMessageSenderId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastRead: freezed == lastRead
          ? _value.lastRead
          : lastRead // ignore: cast_nullable_to_non_nullable
              as Map<String, DateTime>?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ChatImplCopyWith<$Res> implements $ChatCopyWith<$Res> {
  factory _$$ChatImplCopyWith(
          _$ChatImpl value, $Res Function(_$ChatImpl) then) =
      __$$ChatImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String chatId,
      List<String> members,
      @TimestampConverter() DateTime createdAt,
      @TimestampConverter() DateTime? lastMessageAt,
      String? lastMessageText,
      String? lastMessageSenderId,
      @TimestampMapConverter() Map<String, DateTime>? lastRead});
}

/// @nodoc
class __$$ChatImplCopyWithImpl<$Res>
    extends _$ChatCopyWithImpl<$Res, _$ChatImpl>
    implements _$$ChatImplCopyWith<$Res> {
  __$$ChatImplCopyWithImpl(_$ChatImpl _value, $Res Function(_$ChatImpl) _then)
      : super(_value, _then);

  /// Create a copy of Chat
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? chatId = null,
    Object? members = null,
    Object? createdAt = null,
    Object? lastMessageAt = freezed,
    Object? lastMessageText = freezed,
    Object? lastMessageSenderId = freezed,
    Object? lastRead = freezed,
  }) {
    return _then(_$ChatImpl(
      chatId: null == chatId
          ? _value.chatId
          : chatId // ignore: cast_nullable_to_non_nullable
              as String,
      members: null == members
          ? _value._members
          : members // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      lastMessageAt: freezed == lastMessageAt
          ? _value.lastMessageAt
          : lastMessageAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastMessageText: freezed == lastMessageText
          ? _value.lastMessageText
          : lastMessageText // ignore: cast_nullable_to_non_nullable
              as String?,
      lastMessageSenderId: freezed == lastMessageSenderId
          ? _value.lastMessageSenderId
          : lastMessageSenderId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastRead: freezed == lastRead
          ? _value._lastRead
          : lastRead // ignore: cast_nullable_to_non_nullable
              as Map<String, DateTime>?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatImpl implements _Chat {
  const _$ChatImpl(
      {required this.chatId,
      required final List<String> members,
      @TimestampConverter() required this.createdAt,
      @TimestampConverter() this.lastMessageAt,
      this.lastMessageText,
      this.lastMessageSenderId,
      @TimestampMapConverter() final Map<String, DateTime>? lastRead})
      : _members = members,
        _lastRead = lastRead;

  factory _$ChatImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatImplFromJson(json);

  @override
  final String chatId;
  final List<String> _members;
  @override
  List<String> get members {
    if (_members is EqualUnmodifiableListView) return _members;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_members);
  }

  @override
  @TimestampConverter()
  final DateTime createdAt;
  @override
  @TimestampConverter()
  final DateTime? lastMessageAt;
  @override
  final String? lastMessageText;
  @override
  final String? lastMessageSenderId;
  final Map<String, DateTime>? _lastRead;
  @override
  @TimestampMapConverter()
  Map<String, DateTime>? get lastRead {
    final value = _lastRead;
    if (value == null) return null;
    if (_lastRead is EqualUnmodifiableMapView) return _lastRead;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(value);
  }

  @override
  String toString() {
    return 'Chat(chatId: $chatId, members: $members, createdAt: $createdAt, lastMessageAt: $lastMessageAt, lastMessageText: $lastMessageText, lastMessageSenderId: $lastMessageSenderId, lastRead: $lastRead)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatImpl &&
            (identical(other.chatId, chatId) || other.chatId == chatId) &&
            const DeepCollectionEquality().equals(other._members, _members) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.lastMessageAt, lastMessageAt) ||
                other.lastMessageAt == lastMessageAt) &&
            (identical(other.lastMessageText, lastMessageText) ||
                other.lastMessageText == lastMessageText) &&
            (identical(other.lastMessageSenderId, lastMessageSenderId) ||
                other.lastMessageSenderId == lastMessageSenderId) &&
            const DeepCollectionEquality().equals(other._lastRead, _lastRead));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      chatId,
      const DeepCollectionEquality().hash(_members),
      createdAt,
      lastMessageAt,
      lastMessageText,
      lastMessageSenderId,
      const DeepCollectionEquality().hash(_lastRead));

  /// Create a copy of Chat
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatImplCopyWith<_$ChatImpl> get copyWith =>
      __$$ChatImplCopyWithImpl<_$ChatImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatImplToJson(
      this,
    );
  }
}

abstract class _Chat implements Chat {
  const factory _Chat(
          {required final String chatId,
          required final List<String> members,
          @TimestampConverter() required final DateTime createdAt,
          @TimestampConverter() final DateTime? lastMessageAt,
          final String? lastMessageText,
          final String? lastMessageSenderId,
          @TimestampMapConverter() final Map<String, DateTime>? lastRead}) =
      _$ChatImpl;

  factory _Chat.fromJson(Map<String, dynamic> json) = _$ChatImpl.fromJson;

  @override
  String get chatId;
  @override
  List<String> get members;
  @override
  @TimestampConverter()
  DateTime get createdAt;
  @override
  @TimestampConverter()
  DateTime? get lastMessageAt;
  @override
  String? get lastMessageText;
  @override
  String? get lastMessageSenderId;
  @override
  @TimestampMapConverter()
  Map<String, DateTime>? get lastRead;

  /// Create a copy of Chat
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatImplCopyWith<_$ChatImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
