// ignore: unused_import — Timestamp is used by the generated post.g.dart part
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';
import 'post_privacy.dart';
import 'routine_tag.dart';

part 'post.freezed.dart';
part 'post.g.dart';

@freezed
class Post with _$Post {
  const factory Post({
    required String id,
    required String authorUid,
    required String? authorGymId,
    required String text,
    required RoutineTag? routineTag,
    required PostPrivacy privacy,
    @TimestampConverter() required DateTime createdAt,
  }) = _Post;

  factory Post.fromJson(Map<String, Object?> json) => _$PostFromJson(json);
}
