import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/application/notification_providers.dart';
import 'package:treino/features/notifications/data/fcm_service.dart';
import 'package:treino/features/notifications/presentation/foreground_snackbar_handler.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockFcmService extends Mock implements FcmService {}

class MockGoRouter extends Mock implements GoRouter {}

// ---------------------------------------------------------------------------
// Helper: scaffold with a ScaffoldMessengerKey + GoRouter + ProviderScope
// ---------------------------------------------------------------------------

Widget _buildApp({
  required MockFcmService fcmService,
  required MockGoRouter router,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) {
  final key = messengerKey ?? GlobalKey<ScaffoldMessengerState>();
  return ProviderScope(
    overrides: [
      fcmServiceProvider.overrideWithValue(fcmService),
    ],
    child: MaterialApp(
      scaffoldMessengerKey: key,
      home: InheritedGoRouter(
        goRouter: router,
        child: Scaffold(
          body: ForegroundSnackBarHandler(
            scaffoldMessengerKey: key,
            fcmService: fcmService,
          ),
        ),
      ),
    ),
  );
}

RemoteMessage _message({String? title, String? body, String? deepLink}) {
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
  late GlobalKey<ScaffoldMessengerState> messengerKey;

  setUp(() {
    fcmService = MockFcmService();
    router = MockGoRouter();
    messengerKey = GlobalKey<ScaffoldMessengerState>();
    when(() => router.go(any())).thenReturn(null);
    when(() => router.go(any(), extra: any(named: 'extra'))).thenReturn(null);
    when(() => fcmService.onMessageOpenedApp)
        .thenAnswer((_) => const Stream.empty());
    when(() => fcmService.getInitialMessage()).thenAnswer((_) async => null);
  });

  group('ForegroundSnackBarHandler', () {
    // SCENARIO-652: onMessage emits message → SnackBar visible with title and body
    testWidgets(
      'SCENARIO-652: onMessage fires → SnackBar shows title and body',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => controller.stream);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pump();

        controller.add(_message(title: 'Hola', body: 'Mensaje nuevo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Hola'), findsOneWidget);
        expect(find.text('Mensaje nuevo'), findsOneWidget);

        await controller.close();
      },
    );

    // SCENARIO-653: SnackBar action tap → goDeepLink with data['deepLink']
    testWidgets(
      'SCENARIO-653: SnackBar action tap → router.go(deepLink)',
      (tester) async {
        const deepLink = '/coach/chat/chat-1?other=uid-xyz';
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => controller.stream);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pump();

        controller.add(
          _message(title: 'Nuevo mensaje', body: 'Hola!', deepLink: deepLink),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Invoke SnackBar action directly — avoids viewport hit-test bounds.
        // The SnackBar renders in an overlay that may extend below the default
        // 800×600 test viewport; direct widget invocation is more reliable.
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        snackBar.action!.onPressed();
        await tester.pumpAndSettle();

        verify(() => router.go(deepLink)).called(1);
        await controller.close();
      },
    );

    // SCENARIO-654: data['deepLink'] absent → goDeepLink receives null → /coach
    testWidgets(
      'SCENARIO-654: SnackBar action with no deepLink in data → router.go("/coach")',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => controller.stream);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pump();

        // No deepLink in data
        controller.add(_message(title: 'Sin link', body: 'Cuerpo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Invoke SnackBar action directly.
        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        snackBar.action!.onPressed();
        await tester.pumpAndSettle();

        verify(() => router.go('/coach')).called(1);
        await controller.close();
      },
    );

    // TRIANGULATE: SnackBar duration is 4 seconds
    testWidgets(
      'TRIANGULATE: SnackBar duration is 4 seconds',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => controller.stream);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pump();

        controller.add(_message(title: 'Test', body: 'Body'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.duration, const Duration(seconds: 4));

        await controller.close();
      },
    );

    // TRIANGULATE: SnackBar action label is 'Ver'
    testWidgets(
      'TRIANGULATE: SnackBar action label is "Ver"',
      (tester) async {
        final controller = StreamController<RemoteMessage>();
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => controller.stream);

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pump();

        controller.add(_message(title: 'T', body: 'B', deepLink: '/coach'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.action!.label, 'Ver');

        await controller.close();
      },
    );

    // TRIANGULATE: no SnackBar shown when fcmService emits nothing
    testWidgets(
      'TRIANGULATE: no SnackBar shown when stream is empty',
      (tester) async {
        when(() => fcmService.onForegroundMessage)
            .thenAnswer((_) => const Stream.empty());

        await tester.pumpWidget(
          _buildApp(
            fcmService: fcmService,
            router: router,
            messengerKey: messengerKey,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsNothing);
      },
    );
  });
}
