import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  group('TreinoBottomBar — Coach tab badge', () {
    testWidgets('coachUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      // No badge text should be visible
      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('coachUnreadCount 3 → badge "3" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('coachUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            coachUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets('coachUnreadCount defaults to 0 (no badge)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            // no coachUnreadCount parameter
          ),
        ),
      );
      await tester.pump();

      // Confirm no badge-style text leaks in
      expect(find.text('0'), findsNothing);
    });
  });

  group('TreinoBottomBar — Feed tab badge', () {
    testWidgets('feedUnreadCount 0 → no badge rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1'), findsNothing);
      expect(find.text('5'), findsNothing);
      expect(find.text('99+'), findsNothing);
    });

    testWidgets('feedUnreadCount 2 → badge "2" visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('feedUnreadCount 100 → badge shows "99+"', (tester) async {
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 100,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('100'), findsNothing);
    });

    testWidgets(
        'feed 2 + coach 3 → both badges visible independently',
        (tester) async {
      // Regression guard: the two badges must not shadow each other. This
      // reproduces the "message from friend surfaces on both tabs" bug —
      // pre-split, only one badge existed and could render on the wrong tab.
      await tester.pumpWidget(
        _wrap(
          TreinoBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            feedUnreadCount: 2,
            coachUnreadCount: 3,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });
}
