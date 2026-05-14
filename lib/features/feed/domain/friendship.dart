// ignore: unused_import — Timestamp is used by the generated friendship.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'friendship_status.dart';

part 'friendship.freezed.dart';
part 'friendship.g.dart';

@freezed
class Friendship with _$Friendship {
  const Friendship._();

  const factory Friendship({
    required String id,
    required String uidA,
    required String uidB,
    required FriendshipStatus status,
    required String requesterId,
    required List<String> members,
    @TimestampConverter() required DateTime createdAt,
  }) = _Friendship;

  factory Friendship.fromJson(Map<String, Object?> json) =>
      _$FriendshipFromJson(json);

  /// Returns `'${min}_${max}'` where min < max lexicographically.
  /// Ensures the same doc ID regardless of argument order.
  static String sortedDocId(String a, String b) =>
      a.compareTo(b) <= 0 ? '${a}_$b' : '${b}_$a';
}
