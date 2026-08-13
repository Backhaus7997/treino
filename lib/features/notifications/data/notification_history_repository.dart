import 'package:cloud_firestore/cloud_firestore.dart'
    show FieldValue, FirebaseFirestore, Timestamp;

import '../domain/notification_history_item.dart';

class NotificationHistoryRepository {
  NotificationHistoryRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  Stream<List<NotificationHistoryItem>> watchLatest(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationHistoryItem.fromJson(
                  doc.data(),
                  id: doc.id,
                ))
            .toList(growable: false));
  }

  Stream<DateTime?> watchLastSeenAt(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((doc) {
      final value = doc.data()?['notificationsLastSeenAt'];
      return value is Timestamp ? value.toDate() : null;
    });
  }

  Future<void> markSeen(String uid) =>
      _firestore.collection('users').doc(uid).update({
        'notificationsLastSeenAt': FieldValue.serverTimestamp(),
      });
}
