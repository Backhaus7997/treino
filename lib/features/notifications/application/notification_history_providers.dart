import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/application/follow_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/notification_history_repository.dart';
import '../domain/notification_history_item.dart';

bool notificationIsUnread(
  NotificationHistoryItem notification,
  DateTime? lastSeenAt,
) =>
    lastSeenAt == null || notification.createdAt.isAfter(lastSeenAt);

final notificationHistoryRepositoryProvider =
    Provider<NotificationHistoryRepository>(
  (ref) => NotificationHistoryRepository(
    firestore: ref.watch(firestoreProvider),
  ),
);

final notificationHistoryProvider =
    StreamProvider.autoDispose<List<NotificationHistoryItem>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationHistoryRepositoryProvider).watchLatest(uid);
});

final notificationLastSeenAtProvider =
    StreamProvider.autoDispose<DateTime?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(notificationHistoryRepositoryProvider).watchLastSeenAt(uid);
});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationHistoryProvider).valueOrNull;
  if (notifications == null) return 0;
  final lastSeen = ref.watch(notificationLastSeenAtProvider).valueOrNull;
  return notifications
      .where((notification) => notificationIsUnread(notification, lastSeen))
      .length;
});

final notificationHeaderBadgeProvider =
    Provider.family.autoDispose<int, String>((ref, uid) {
  return ref.watch(unreadNotificationCountProvider) +
      ref.watch(pendingFollowRequestCountProvider(uid));
});
