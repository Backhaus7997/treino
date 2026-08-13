// ignore: unused_import — Timestamp is used by the generated reaction.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'reaction_type.dart';

part 'reaction.freezed.dart';
part 'reaction.g.dart';

@freezed
class Reaction with _$Reaction {
  const factory Reaction({
    required String uid,
    required ReactionType type,
    @TimestampConverter() required DateTime createdAt,
  }) = _Reaction;

  factory Reaction.fromJson(Map<String, Object?> json) =>
      _$ReactionFromJson(json);
}
