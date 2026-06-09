import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
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

class _MockUser extends Mock implements User {
  @override
  String get uid => 'uid-test';
}

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
  User? user,
}) {
  return ProviderScope(
    overrides: [
      fcmServiceProvider.overrideWithValue(fcmService),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(profile),
      ),
      authStateChangesProvider.overrideWith(
        (ref) => Stream.value(user ?? _MockUser()),
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

    // SCENARIO-661: re-mount within the same app session (ProviderScope) →
    // NOT called again. Models tab navigation / parent rebuild where the
    // PermissionGate's State is destroyed and recreated but the root
    // ProviderScope (and therefore permissionGateAttemptedProvider) survives.
    testWidgets(
      'SCENARIO-661: re-mount within same ProviderScope → NOT called again '
      '(permissionGateAttemptedProvider guard)',
      (tester) async {
        when(() => fcmService.init(any())).thenAnswer((_) async {});
        final container = ProviderContainer(
          overrides: [
            fcmServiceProvider.overrideWithValue(fcmService),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(_profile(displayName: 'JuanAthlete')),
            ),
            authStateChangesProvider.overrideWith(
              (ref) => Stream.value(_MockUser()),
            ),
          ],
        );
        addTearDown(container.dispose);

        // First mount → fires once.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: PermissionGate()),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Replace tree shape to force PermissionGate State to be torn down
        // and recreated. Same container — provider state persists.
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: Column(children: [PermissionGate()]),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Should still be exactly 1 — re-mount sees attempted=true.
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

    // TRIANGULATE: null profile (stream not yet resolved) → no call
    testWidgets(
      'TRIANGULATE: null profile (not yet loaded) → requestPermission NOT called',
      (tester) async {
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: null, // stream value is null
          ),
        );
        await tester.pumpAndSettle();

        verifyNever(() => fcmService.requestPermission());
      },
    );

    // TRIANGULATE: permission throws → no crash (error is swallowed)
    testWidgets(
      'TRIANGULATE: requestPermission throws → no crash, no re-attempt',
      (tester) async {
        when(
          () => fcmService.requestPermission(),
        ).thenThrow(Exception('platform error'));

        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        // Attempted once despite the throw
        verify(() => fcmService.requestPermission()).called(1);
        // App did not crash
        expect(find.byType(SizedBox), findsWidgets);
      },
    );

    // TRIANGULATE: PermissionGate renders SizedBox.shrink — zero layout impact
    testWidgets(
      'TRIANGULATE: PermissionGate renders SizedBox.shrink, no visible UI',
      (tester) async {
        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: null),
          ),
        );
        await tester.pumpAndSettle();

        // PermissionGate returns SizedBox.shrink() — renders without error
        // and produces no visible children (no Text, Button, etc.).
        expect(find.byType(PermissionGate), findsOneWidget);
        expect(find.byType(Text), findsNothing);
      },
    );

    // SCENARIO-687: regression — when requestPermission returns
    // authorized/provisional, FcmService.init(uid) MUST be called so that the
    // FCM token is registered now that APNS has been provisioned. Without this
    // re-trigger, the initial init() during sign-in failed silently (no APNS)
    // and the user never receives notifications until the next sign-in cycle.
    testWidgets(
      'SCENARIO-687: requestPermission authorized → init(uid) called to '
      'register token after APNS provisions',
      (tester) async {
        when(() => fcmService.init(any())).thenAnswer((_) async {});
        when(
          () => fcmService.requestPermission(),
        ).thenAnswer((_) async => _authorized());

        await tester.pumpWidget(
          _buildGate(
            fcmService: fcmService,
            profile: _profile(displayName: 'JuanAthlete'),
          ),
        );
        await tester.pumpAndSettle();

        // Permission requested AND init re-fired after grant
        verify(() => fcmService.requestPermission()).called(1);
        verify(() => fcmService.init('uid-test')).called(1);
      },
    );

    // SCENARIO-687: regression — denial path MUST NOT call init (no APNS
    // provisioning happens on denial, so re-init would just fail again).
    testWidgets(
      'SCENARIO-687: requestPermission denied → init NOT called',
      (tester) async {
        when(() => fcmService.init(any())).thenAnswer((_) async {});
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

        verify(() => fcmService.requestPermission()).called(1);
        verifyNever(() => fcmService.init(any()));
      },
    );
  });
}
