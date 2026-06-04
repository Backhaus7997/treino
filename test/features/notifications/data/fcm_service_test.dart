import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/data/fcm_service.dart';
import 'package:treino/features/notifications/data/fcm_token_repository.dart';

class MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class MockFcmTokenRepository extends Mock implements FcmTokenRepository {}

void main() {
  late MockFirebaseMessaging messaging;
  late MockFcmTokenRepository repo;
  late FcmService service;

  setUp(() {
    messaging = MockFirebaseMessaging();
    repo = MockFcmTokenRepository();
    service = FcmService(messaging: messaging, repository: repo);

    // Default stubs — can be overridden per test.
    when(() => repo.saveToken(any(), any())).thenAnswer((_) async {});
    when(() => repo.removeToken(any(), any())).thenAnswer((_) async {});
    when(
      () => messaging.requestPermission(
        alert: any(named: 'alert'),
        announcement: any(named: 'announcement'),
        badge: any(named: 'badge'),
        carPlay: any(named: 'carPlay'),
        criticalAlert: any(named: 'criticalAlert'),
        provisional: any(named: 'provisional'),
        sound: any(named: 'sound'),
      ),
    ).thenAnswer(
      (_) async => const NotificationSettings(
        authorizationStatus: AuthorizationStatus.authorized,
        alert: AppleNotificationSetting.enabled,
        announcement: AppleNotificationSetting.notSupported,
        badge: AppleNotificationSetting.enabled,
        carPlay: AppleNotificationSetting.notSupported,
        criticalAlert: AppleNotificationSetting.notSupported,
        notificationCenter: AppleNotificationSetting.enabled,
        sound: AppleNotificationSetting.enabled,
        lockScreen: AppleNotificationSetting.enabled,
        timeSensitive: AppleNotificationSetting.notSupported,
        showPreviews: AppleShowPreviewSetting.always,
        providesAppNotificationSettings: AppleNotificationSetting.notSupported,
      ),
    );
  });

  group('FcmService.init', () {
    // SCENARIO-645: init saves initial token
    test(
      'SCENARIO-645: init calls getToken once and saveToken with result',
      () async {
        const uid = 'user-645';
        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-init');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());

        await service.init(uid);

        verify(() => messaging.getToken()).called(1);
        verify(() => repo.saveToken(uid, 'tok-init')).called(1);
      },
    );

    // SCENARIO-647: init does NOT call requestPermission
    test(
      'SCENARIO-647: init does NOT call requestPermission',
      () async {
        const uid = 'user-647';
        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-647');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());

        await service.init(uid);

        verifyNever(
          () => messaging.requestPermission(
            alert: any(named: 'alert'),
            announcement: any(named: 'announcement'),
            badge: any(named: 'badge'),
            carPlay: any(named: 'carPlay'),
            criticalAlert: any(named: 'criticalAlert'),
            provisional: any(named: 'provisional'),
            sound: any(named: 'sound'),
          ),
        );
      },
    );

    // SCENARIO-646: onTokenRefresh emits → saveToken called with new token
    test(
      'SCENARIO-646: onTokenRefresh emits new token → saveToken called',
      () async {
        const uid = 'user-646';
        final refreshController = StreamController<String>();

        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-initial');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => refreshController.stream);

        await service.init(uid);

        refreshController.add('tok-refreshed');
        await Future<void>.delayed(Duration.zero);

        verify(() => repo.saveToken(uid, 'tok-refreshed')).called(1);

        await refreshController.close();
      },
    );

    // SCENARIO-678: getToken returns null → saveToken NOT called
    test(
      'SCENARIO-678: getToken returns null → saveToken not called, no error',
      () async {
        const uid = 'user-678';
        when(() => messaging.getToken()).thenAnswer((_) async => null);
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());

        await expectLater(
          () => service.init(uid),
          returnsNormally,
        );

        verifyNever(() => repo.saveToken(any(), any()));
      },
    );

    // SCENARIO-685: regression — init swallows apns-token-not-set FirebaseException
    // (raised when APNS isn't provisioned yet — iOS Simulator, or real device
    // before requestPermission completes). Caller MUST NOT see the throw, and
    // the onTokenRefresh subscription MUST still be registered so that a later
    // permission grant flowing through the refresh stream can save a token.
    test(
      'SCENARIO-685: init swallows apns-token-not-set exception, '
      'subscribes to onTokenRefresh anyway',
      () async {
        const uid = 'user-685';
        final refreshController = StreamController<String>();

        when(() => messaging.getToken()).thenThrow(
          FirebaseException(
            plugin: 'firebase_messaging',
            code: 'apns-token-not-set',
            message: 'APNS token has not been set yet.',
          ),
        );
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => refreshController.stream);

        await expectLater(service.init(uid), completes);

        // saveToken was not called because getToken failed.
        verifyNever(() => repo.saveToken(any(), any()));

        // onTokenRefresh subscription is still registered — a later refresh
        // (e.g. after permission is granted and APNS provisions) triggers
        // saveToken.
        refreshController.add('tok-after-permission');
        await Future<void>.delayed(Duration.zero);
        verify(() => repo.saveToken(uid, 'tok-after-permission')).called(1);

        await refreshController.close();
      },
    );
  });

  group('FcmService.dispose', () {
    // SCENARIO-648: dispose calls removeToken with the current token
    test(
      'SCENARIO-648: dispose calls removeToken with current token',
      () async {
        const uid = 'user-648';
        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-current');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());

        await service.init(uid);
        await service.dispose(uid);

        // getToken called again for dispose
        verify(() => messaging.getToken()).called(2);
        verify(() => repo.removeToken(uid, 'tok-current')).called(1);
      },
    );

    // SCENARIO-649: removeToken throws → error swallowed, no propagation
    test(
      'SCENARIO-649: removeToken throws → error swallowed, no propagation',
      () async {
        const uid = 'user-649';
        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-current');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => const Stream.empty());
        when(() => repo.removeToken(any(), any()))
            .thenThrow(Exception('Firestore unavailable'));

        await service.init(uid);

        await expectLater(
          () => service.dispose(uid),
          returnsNormally,
        );
      },
    );

    // SCENARIO-679: onTokenRefresh subscription cancelled on dispose
    test(
      'SCENARIO-679: dispose cancels onTokenRefresh subscription — '
      'subsequent refresh events do not trigger saveToken',
      () async {
        const uid = 'user-679';
        final refreshController = StreamController<String>();

        when(() => messaging.getToken()).thenAnswer((_) async => 'tok-initial');
        when(() => messaging.onTokenRefresh)
            .thenAnswer((_) => refreshController.stream);

        await service.init(uid);
        await service.dispose(uid);

        // Reset saveToken call count after init
        clearInteractions(repo);

        // Emit after dispose — should NOT trigger saveToken
        refreshController.add('tok-after-dispose');
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => repo.saveToken(any(), any()));

        await refreshController.close();
      },
    );
  });
}
