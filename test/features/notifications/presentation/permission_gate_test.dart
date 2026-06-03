import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/data/fcm_service.dart';
import 'package:treino/features/notifications/presentation/permission_gate.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFcmService extends Mock implements FcmService {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

NotificationSettings _authorized() => const NotificationSettings(
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
    );

NotificationSettings _denied() => const NotificationSettings(
      authorizationStatus: AuthorizationStatus.denied,
      alert: AppleNotificationSetting.disabled,
      announcement: AppleNotificationSetting.notSupported,
      badge: AppleNotificationSetting.disabled,
      carPlay: AppleNotificationSetting.notSupported,
      criticalAlert: AppleNotificationSetting.notSupported,
      notificationCenter: AppleNotificationSetting.disabled,
      sound: AppleNotificationSetting.disabled,
      lockScreen: AppleNotificationSetting.disabled,
      timeSensitive: AppleNotificationSetting.notSupported,
      showPreviews: AppleShowPreviewSetting.never,
      providesAppNotificationSettings: AppleNotificationSetting.notSupported,
    );

UserProfile _profile({String? displayName}) => UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

Widget _buildGate({
  required MockFcmService fcmService,
  UserProfile? profile,
  String? uid,
}) {
  return ProviderScope(
    overrides: [
      fcmServiceProvider.overrideWithValue(fcmService),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(profile),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: PermissionGate(),
      ),
    ),
  );
}

void main() {
  late MockFcmService fcmService;

  setUp(() {
    fcmService = MockFcmService();
    when(
      () => fcmService.requestPermission(),
    ).thenAnswer((_) async => _authorized());
  });

  group('PermissionGate', () {
    // SCENARIO-659: displayName != null and first build → requestPermission called once
    testWidgets(
      'SCENARIO-659: displayName != null on first build → requestPermission called once',
      (tester) async {
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        verify(() => fcmService.requestPermission()).called(1);
      },
    );

    // SCENARIO-660: displayName == null → requestPermission NOT called
    testWidgets(
      'SCENARIO-660: displayName == null → requestPermission NOT called',
      (tester) async {
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: null),
          ),
        );
        await tester.pumpAndSettle();

        verifyNever(() => fcmService.requestPermission());
      },
    );

    // SCENARIO-661: re-render after first call → requestPermission NOT called again
    testWidgets(
      'SCENARIO-661: re-render after permission called → NOT called again (_attempted guard)',
      (tester) async {
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        // Rebuild widget (simulates parent rebuild)
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        // Should still be exactly 1 — not called again
        verify(() => fcmService.requestPermission()).called(1);
      },
    );

    // SCENARIO-662: permission denied → app continues normally, no crash, no SnackBar
    testWidgets(
      'SCENARIO-662: denial → app continues normally, no error, no retry',
      (tester) async {
        when(
          () => fcmService.requestPermission(),
        ).thenAnswer((_) async => _denied());

        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        // requestPermission called once
        verify(() => fcmService.requestPermission()).called(1);
        // No SnackBar shown on denial
        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });
}
