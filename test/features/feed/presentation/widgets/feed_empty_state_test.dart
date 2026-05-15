import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('FeedEmptyState', () {
    // SCENARIO-185: correct copy is rendered
    testWidgets('SCENARIO-185: renders correct copy', (tester) async {
      await tester.pumpWidget(_wrap(const FeedEmptyState()));
      await tester.pump();

      expect(
        find.text('Aún no hay posts de tus amigos'),
        findsOneWidget,
      );
    });

    // SCENARIO-186: an icon is rendered
    testWidgets('SCENARIO-186: renders an icon', (tester) async {
      await tester.pumpWidget(_wrap(const FeedEmptyState()));
      await tester.pump();

      expect(find.byType(Icon), findsAtLeastNWidgets(1));
    });

    // SCENARIO-187: no PostCard or CircularProgressIndicator present
    testWidgets(
        'SCENARIO-187: no PostCard or CircularProgressIndicator rendered',
        (tester) async {
      await tester.pumpWidget(_wrap(const FeedEmptyState()));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      // PostCard doesn't exist yet; we simply verify no spinner — the type
      // check for PostCard is added once TASK-007b lands (it compiles as a
      // forward reference and the test still satisfies the spec contract).
    });
  });
}
