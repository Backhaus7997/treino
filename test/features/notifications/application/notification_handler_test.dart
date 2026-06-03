import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/application/notification_router.dart';
import 'package:treino/features/notifications/data/fcm_service.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFcmService extends Mock implements FcmService {}

class MockGoRouter extends Mock implements GoRouter {}

// ---------------------------------------------------------------------------
// Helper: build a ProviderScope with overrides + GoRouter + a triggering widget
// ---------------------------------------------------------------------------

Widget _buildApp({
  required MockFcmService fcmService,
  required MockGoRouter router,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      fcmServiceProvider.overrideWithValue(fcmService),
    ],
    child: MaterialApp(
      home: InheritedGoRouter(
        goRouter: router,
        child: Builder(builder: (_) => child),
      ),
    ),
  );
}

RemoteMessage _message({String? deepLink, String? title, String? body}) {
  return RemoteMessage(
    notification: (title != null || body != null)
        ? RemoteNotification(title: title, body: body)
        : null,
    data: {
      if (deepLink != null) 'deepLink': deepLink,
    },
  );
}

void main() {
  late MockFcmService fcmService;
  late MockGoRouter router;

  setUp(() {
    fcmService = MockFcmService();
    router = MockGoRouter();
    when(() => router.go(any())).thenReturn(null);
    when(() => router.go(any(), extra: any(named: 'extra'))).thenReturn(null);
  });

  group('onMessageOpenedApp (background tap)', () {
    // SCENARIO-655: background tap with deepLink → goDeepLink(deepLink)
    testWidgets(
      'SCENARIO-655: onMessageOpenedApp fires with deepLink → go(deepLink)',
      (tester) async {
        const deepLink = '/coach?tab=agenda';
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => controller.stream);
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => null);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _BackgroundTapListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        controller.add(_message(deepLink: deepLink));
        await tester.pumpAndSettle();

        verify(() => router.go(deepLink)).called(1);
        await controller.close();
      },
    );

    // SCENARIO-656: background tap with no deepLink → goDeepLink(null) → /coach
    testWidgets(
      'SCENARIO-656: onMessageOpenedApp fires with no deepLink → go("/coach")',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => controller.stream);
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => null);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _BackgroundTapListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        controller.add(_message()); // no deepLink in data
        await tester.pumpAndSettle();

        verify(() => router.go('/coach')).called(1);
        await controller.close();
      },
    );
  });

  group('getInitialMessage (cold-start)', () {
    // SCENARIO-657: cold-start with deepLink → navigation deferred to post-frame
    testWidgets(
      'SCENARIO-657: getInitialMessage returns message with deepLink → go(deepLink) after frame',
      (tester) async {
        const deepLink = '/coach/trainer/uid-1';
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => const Stream.empty());
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => _message(deepLink: deepLink));

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _ColdStartListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        verify(() => router.go(deepLink)).called(1);
      },
    );

    // SCENARIO-658: cold-start with null → no navigation, no error
    testWidgets(
      'SCENARIO-658: getInitialMessage returns null → no navigation, no error',
      (tester) async {
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => const Stream.empty());
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => null);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _ColdStartListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        verifyNever(() => router.go(any()));
      },
    );

    // TRIANGULATE: cold-start with invalid deepLink → fallback /coach
    testWidgets(
      'TRIANGULATE: cold-start with invalid deepLink → go("/coach")',
      (tester) async {
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => const Stream.empty());
        when(() => fcmService.getInitialMessage()).thenAnswer(
          (_) async => _message(deepLink: 'no-leading-slash'),
        );

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _ColdStartListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        verify(() => router.go('/coach')).called(1);
      },
    );
  });

  group('onMessageOpenedApp — triangulation', () {
    // TRIANGULATE: background tap with invalid deepLink → /coach
    testWidgets(
      'TRIANGULATE: onMessageOpenedApp with invalid deepLink → go("/coach")',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => controller.stream);
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => null);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _BackgroundTapListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        controller.add(_message(deepLink: 'bad-path'));
        await tester.pumpAndSettle();

        verify(() => router.go('/coach')).called(1);
        await controller.close();
      },
    );

    // TRIANGULATE: multiple background taps → each navigates independently
    testWidgets(
      'TRIANGULATE: two background taps → two separate navigations',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onMessageOpenedApp)
            .thenAnswer((_) => controller.stream);
        when(() => fcmService.getInitialMessage())
            .thenAnswer((_) async => null);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            child: _BackgroundTapListener(fcmService: fcmService),
          ),
        );
        await tester.pumpAndSettle();

        controller.add(_message(deepLink: '/coach/trainer/uid-1'));
        await tester.pumpAndSettle();

        controller.add(_message(deepLink: '/coach?tab=agenda'));
        await tester.pumpAndSettle();

        verify(() => router.go('/coach/trainer/uid-1')).called(1);
        verify(() => router.go('/coach?tab=agenda')).called(1);
        await controller.close();
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Helper widgets that simulate the app.dart listener attachment pattern.
// These are the "test harness" for the handler logic tested in T-PN-042.
// ---------------------------------------------------------------------------

/// Simulates background tap subscription from app.dart.
class _BackgroundTapListener extends StatefulWidget {
  const _BackgroundTapListener({required this.fcmService});
  final FcmService fcmService;

  @override
  State<_BackgroundTapListener> createState() => _BackgroundTapListenerState();
}

class _BackgroundTapListenerState extends State<_BackgroundTapListener> {
  StreamSubscription<RemoteMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.fcmService.onMessageOpenedApp.listen((message) {
      if (!mounted) return;
      final deepLink = message.data['deepLink'] as String?;
      goDeepLink(context, deepLink);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Simulates cold-start handler via addPostFrameCallback from app.dart.
class _ColdStartListener extends StatefulWidget {
  const _ColdStartListener({required this.fcmService});
  final FcmService fcmService;

  @override
  State<_ColdStartListener> createState() => _ColdStartListenerState();
}

class _ColdStartListenerState extends State<_ColdStartListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final message = await widget.fcmService.getInitialMessage();
      if (message == null) return;
      if (!mounted) return;
      final deepLink = message.data['deepLink'] as String?;
      goDeepLink(context, deepLink);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
