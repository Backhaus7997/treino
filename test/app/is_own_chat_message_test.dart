import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/app.dart';

/// Guard that suppresses self-notifications even when a device's FCM token is
/// cross-registered under another account (two accounts on one phone). The
/// device's own uid is the only token-independent source of truth.
void main() {
  group('isOwnChatMessage', () {
    test('true when data.senderId matches currentUid (own message)', () {
      const m = RemoteMessage(data: <String, dynamic>{'senderId': 'vicente'});
      expect(isOwnChatMessage(m, 'vicente'), isTrue);
    });

    test('false when the sender is someone else', () {
      const m = RemoteMessage(data: <String, dynamic>{'senderId': 'mateo'});
      expect(isOwnChatMessage(m, 'vicente'), isFalse);
    });

    test('falls back to the deepLink "other" param when senderId is absent',
        () {
      const m = RemoteMessage(data: <String, dynamic>{
        'deepLink': '/coach/chat/mateo_vicente?other=vicente',
      });
      expect(isOwnChatMessage(m, 'vicente'), isTrue);
    });

    test('fail-open: no sender info → false (shows the notification)', () {
      const m = RemoteMessage(data: <String, dynamic>{});
      expect(isOwnChatMessage(m, 'vicente'), isFalse);
    });

    test('false when there is no current user', () {
      const m = RemoteMessage(data: <String, dynamic>{'senderId': 'vicente'});
      expect(isOwnChatMessage(m, null), isFalse);
    });
  });
}
