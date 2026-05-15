import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

void main() {
  group('PostAvatar', () {
    // SCENARIO-180: URL present → CachedNetworkImage, no Image.network
    testWidgets(
        'SCENARIO-180: renders CachedNetworkImage when authorAvatarUrl is non-null',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostAvatar(
            authorAvatarUrl: 'https://example.com/av.jpg',
            authorDisplayName: 'Tincho',
            size: 40,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsAtLeastNWidgets(1));
      // Spec: must NOT use Image.network directly (CachedNetworkImage is fine —
      // it internally uses Image but wraps it; we check there's no raw
      // Image.network constructor at the avatar subtree root by verifying there
      // is no widget whose image provider is a NetworkImage directly exposed).
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.image is NetworkImage,
        ),
        findsNothing,
      );
    });

    // SCENARIO-181: null URL + valid name → first letter
    testWidgets(
        'SCENARIO-181: initials fallback renders first letter when URL is null',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostAvatar(
            authorAvatarUrl: null,
            authorDisplayName: 'Tincho',
            size: 40,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('T'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    // SCENARIO-182: null URL + 'Anónimo' → '?'
    testWidgets(
        'SCENARIO-182: shows ? for displayName Anónimo',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostAvatar(
            authorAvatarUrl: null,
            authorDisplayName: 'Anónimo',
            size: 40,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    // SCENARIO-183: null URL + empty displayName → '?'
    testWidgets(
        'SCENARIO-183: shows ? for empty displayName',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostAvatar(
            authorAvatarUrl: null,
            authorDisplayName: '',
            size: 40,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    // SCENARIO-184: gradient decoration uses palette.accent and palette.highlight
    testWidgets(
        'SCENARIO-184: initials fallback uses accent→highlight gradient',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PostAvatar(
            authorAvatarUrl: null,
            authorDisplayName: 'Tincho',
            size: 40,
          ),
        ),
      );
      await tester.pump();

      const palette = AppPalette.mintMagenta;

      // Find a Container with a BoxDecoration that has a LinearGradient
      // containing accent and highlight colors.
      final containers = tester.widgetList<Container>(find.byType(Container));
      bool foundGradient = false;
      for (final container in containers) {
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          final gradient = decoration.gradient;
          if (gradient is LinearGradient) {
            if (gradient.colors.contains(palette.accent) &&
                gradient.colors.contains(palette.highlight)) {
              foundGradient = true;
              break;
            }
          }
        }
      }
      expect(foundGradient, isTrue,
          reason:
              'Expected a Container with LinearGradient using accent and highlight colors');
    });
  });
}
