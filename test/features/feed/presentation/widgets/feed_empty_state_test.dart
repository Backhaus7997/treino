import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('FeedEmptyState', () {
    // SCENARIO-185: correct copy is rendered (updated to use message param)
    testWidgets('SCENARIO-185: renders correct copy', (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Aún no hay posts de tus amigos')),
      );
      await tester.pump();

      expect(
        find.text('Aún no hay posts de tus amigos'),
        findsOneWidget,
      );
    });

    // SCENARIO-186: an icon is rendered
    testWidgets('SCENARIO-186: renders an icon', (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Test')),
      );
      await tester.pump();

      expect(find.byType(Icon), findsAtLeastNWidgets(1));
    });

    // SCENARIO-187: no PostCard or CircularProgressIndicator present
    testWidgets(
        'SCENARIO-187: no PostCard or CircularProgressIndicator rendered',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Test')),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    // SCENARIO-195: renders provided message string
    testWidgets('SCENARIO-195: renders provided message string', (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Test message')),
      );
      await tester.pump();

      expect(find.text('Test message'), findsOneWidget);
    });

    // SCENARIO-196: omitting icon defaults to TreinoIcon.users
    testWidgets('SCENARIO-196: omitting icon defaults to TreinoIcon.users',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Test')),
      );
      await tester.pump();

      expect(find.byIcon(TreinoIcon.users), findsOneWidget);
    });

    // SCENARIO-197: custom icon overrides default
    testWidgets('SCENARIO-197: custom icon overrides default', (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedEmptyState(message: 'Test', icon: TreinoIcon.gym)),
      );
      await tester.pump();

      expect(find.byIcon(TreinoIcon.gym), findsOneWidget);
      expect(find.byIcon(TreinoIcon.users), findsNothing);
    });
  });
}
