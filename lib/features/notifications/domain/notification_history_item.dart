import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;

enum NotificationKind {
  appointment('appointment'),
  chatMessage('chat-message'),
  friendAccepted('friend-accepted'),
  friendFollow('friend-follow'),
  friendRequest('friend-request'),
  linkChange('link-change'),
  overduePayment('overdue-payment'),
  reaction('reaction'),
  review('review'),
  unknown('unknown');

  const NotificationKind(this.value);

  final String value;

  static NotificationKind fromJson(Object? value) => values.firstWhere(
        (kind) => kind.value == value,
        orElse: () => NotificationKind.unknown,
      );
}

class NotificationHistoryItem {
  const NotificationHistoryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.deepLink,
    required this.createdAt,
    this.actorUid,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final String deepLink;
  final DateTime createdAt;
  final String? actorUid;

  factory NotificationHistoryItem.fromJson(
    Map<String, Object?> json, {
    required String id,
  }) {
    final rawCreatedAt = json['createdAt'];
    return NotificationHistoryItem(
      id: id,
      kind: NotificationKind.fromJson(json['kind']),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      deepLink: json['deepLink'] as String? ?? '',
      createdAt: rawCreatedAt is Timestamp
          ? rawCreatedAt.toDate()
          : rawCreatedAt is DateTime
              ? rawCreatedAt
              : DateTime.fromMillisecondsSinceEpoch(0),
      actorUid: json['actorUid'] as String?,
    );
  }
}
