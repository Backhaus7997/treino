import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/notifications/application/notification_router.dart';

// ---------------------------------------------------------------------------
// Minimal GoRouter mock via InheritedWidget injection
// ---------------------------------------------------------------------------

class MockGoRouter extends Mock implements GoRouter {}

/// Wraps [child] with a [MockGoRouter] accessible via [GoRouter.of(context)].
Widget _withRouter(MockGoRouter router, Widget child) {
  return MaterialApp(
    home: InheritedGoRouter(
      goRouter: router,
      child: Builder(builder: (_) => child),
    ),
  );
}

void main() {
  late MockGoRouter router;

  setUp(() {
    router = MockGoRouter();
    when(() => router.go(any(), extra: any(named: 'extra'))).thenReturn(null);
    when(() => router.go(any())).thenReturn(null);
  });

  group('goDeepLink', () {
    // SCENARIO-654: null → fallback /coach
    testWidgets(
      'SCENARIO-654: null deepLink → context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, null),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-654: empty string → fallback /coach
    testWidgets(
      'SCENARIO-654: empty deepLink → context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, ''),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-682: no leading slash → log + fallback /coach
    testWidgets(
      'SCENARIO-682: deepLink without leading slash → log + context.go("/coach")',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, 'no-leading-slash'),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // SCENARIO-653: valid path with query → context.go(deepLink)
    testWidgets(
      'SCENARIO-653: valid deepLink /coach/chat/abc?other=xyz → context.go exactly',
      (tester) async {
        const deepLink = '/coach/chat/abc?other=xyz';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // SCENARIO-655: valid path with query parameter
    testWidgets(
      'SCENARIO-655: valid deepLink /coach?tab=agenda → context.go exactly',
      (tester) async {
        const deepLink = '/coach?tab=agenda';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: path without leading slash that looks like a host
    testWidgets(
      'TRIANGULATE: "coach" (no slash) → fallback /coach + log',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, 'coach'),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go('/coach')).called(1);
      },
    );

    // Triangulation: valid trainer profile deep link
    testWidgets(
      'TRIANGULATE: /coach/trainer/uid-1 → context.go exactly',
      (tester) async {
        const deepLink = '/coach/trainer/uid-1';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: valid agenda deep link
    testWidgets(
      'TRIANGULATE: /coach/agenda → context.go exactly',
      (tester) async {
        const deepLink = '/coach/agenda';
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, deepLink),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        verify(() => router.go(deepLink)).called(1);
        verifyNever(() => router.go('/coach'));
      },
    );

    // Triangulation: whitespace-only string → fallback (treated as empty)
    testWidgets(
      'TRIANGULATE: whitespace-only deepLink → goes to "/coach"',
      (tester) async {
        await tester.pumpWidget(
          _withRouter(
            router,
            Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () => goDeepLink(ctx, '   '),
                  child: const Text('tap'),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('tap'));
        // '   ' doesn't start with '/' → logged + falls back
        verify(() => router.go('/coach')).called(1);
      },
    );
  });
}
