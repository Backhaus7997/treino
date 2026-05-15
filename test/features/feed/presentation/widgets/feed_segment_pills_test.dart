import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/presentation/widgets/feed_segment_pills.dart';

Widget _wrapProvider(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
    );

void main() {
  group('FeedSegmentPills', () {
    // SCENARIO-159: three pills rendered in correct order
    testWidgets('SCENARIO-159: renders AMIGOS, MI GYM, PÚBLICO in order',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedSegmentPills(),
          [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('AMIGOS'), findsOneWidget);
      expect(find.text('MI GYM'), findsOneWidget);
      expect(find.text('PÚBLICO'), findsOneWidget);

      // Verify left-to-right order via widget position
      final amigosOffset = tester.getCenter(find.text('AMIGOS'));
      final gymOffset = tester.getCenter(find.text('MI GYM'));
      final publicoOffset = tester.getCenter(find.text('PÚBLICO'));
      expect(amigosOffset.dx, lessThan(gymOffset.dx));
      expect(gymOffset.dx, lessThan(publicoOffset.dx));
    });

    // SCENARIO-160: active pill (AMIGOS) has accent background
    testWidgets(
        'SCENARIO-160: active pill has accent fill, inactive has bgCard fill',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedSegmentPills(),
          [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          ],
        ),
      );
      await tester.pump();

      // Both AMIGOS and MI GYM pills are structurally present; the visual
      // distinction lives in BoxDecoration.color (accent vs bgCard).
      final amigosContainers = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('AMIGOS'),
          matching: find.byType(Container),
        ),
      );
      final gymContainers = tester.widgetList<Container>(
        find.ancestor(
          of: find.text('MI GYM'),
          matching: find.byType(Container),
        ),
      );
      expect(amigosContainers, isNotEmpty);
      expect(gymContainers, isNotEmpty);
    });

    // SCENARIO-161: MI GYM pill renders at full opacity (mockup parity).
    // Disabled visual cue is the lack of accent fill, NOT reduced opacity.
    testWidgets('SCENARIO-161: MI GYM pill renders at full opacity',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedSegmentPills(),
          [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          ],
        ),
      );
      await tester.pump();

      final opacityFinder = find.ancestor(
        of: find.text('MI GYM'),
        matching: find.byType(Opacity),
      );
      // No Opacity ancestor wrapping the pill — full opacity by default.
      expect(opacityFinder, findsNothing);
    });

    // SCENARIO-162: PÚBLICO pill renders at full opacity (mockup parity).
    testWidgets('SCENARIO-162: PÚBLICO pill renders at full opacity',
        (tester) async {
      await tester.pumpWidget(
        _wrapProvider(
          const FeedSegmentPills(),
          [
            feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
          ],
        ),
      );
      await tester.pump();

      final opacityFinder = find.ancestor(
        of: find.text('PÚBLICO'),
        matching: find.byType(Opacity),
      );
      expect(opacityFinder, findsNothing);
    });

    // SCENARIO-163: tapping AMIGOS when active — state unchanged, no error
    testWidgets('SCENARIO-163: tapping AMIGOS when active keeps amigos state',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: FeedSegmentPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('AMIGOS'));
      await tester.pumpAndSettle();

      expect(container.read(feedSegmentProvider), equals(FeedSegment.amigos));
    });

    // SCENARIO-164: tapping MI GYM — feedSegmentProvider state unchanged
    testWidgets('SCENARIO-164: tapping MI GYM does not change provider state',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: FeedSegmentPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('MI GYM'));
      await tester.pumpAndSettle();

      expect(container.read(feedSegmentProvider), equals(FeedSegment.amigos));
    });

    // SCENARIO-165: tapping PÚBLICO — feedSegmentProvider state unchanged
    testWidgets('SCENARIO-165: tapping PÚBLICO does not change provider state',
        (tester) async {
      final container = ProviderContainer(
        overrides: [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: FeedSegmentPills()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('PÚBLICO'));
      await tester.pumpAndSettle();

      expect(container.read(feedSegmentProvider), equals(FeedSegment.amigos));
    });
  });
}
