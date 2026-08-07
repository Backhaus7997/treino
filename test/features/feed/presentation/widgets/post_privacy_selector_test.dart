import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/presentation/widgets/post_privacy_selector.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Locale pinned so the assertions below are stable regardless of the host
/// locale; labels are still read from [AppL10n] instead of hardcoded literals.
const _locale = Locale('es', 'AR');

Widget _wrap({
  PostPrivacy selected = PostPrivacy.followers,
  bool hasGym = true,
  required ValueChanged<PostPrivacy> onSelect,
}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      locale: _locale,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: PostPrivacySelector(
          selected: selected,
          hasGym: hasGym,
          onSelect: onSelect,
        ),
      ),
    );

void main() {
  late AppL10n l10n;

  setUpAll(() async {
    l10n = await AppL10n.delegate.load(_locale);
  });

  group('PostPrivacySelector', () {
    testWidgets('renders the friends, gym and public privacy labels',
        (tester) async {
      await tester.pumpWidget(_wrap(onSelect: (_) {}));

      expect(find.text(l10n.postPrivacySelectorTitle), findsOneWidget);
      expect(find.text(l10n.postPrivacyFriends), findsOneWidget);
      expect(find.text(l10n.postPrivacyGym), findsOneWidget);
      expect(find.text(l10n.postPrivacyPublic), findsOneWidget);
    });

    testWidgets(
      'uses TreinoTappable for every privacy pill without an extra '
      'GestureDetector',
      (tester) async {
        await tester.pumpWidget(_wrap(onSelect: (_) {}));

        final selector = find.byType(PostPrivacySelector);
        final tappables = find.descendant(
          of: selector,
          matching: find.byType(TreinoTappable),
        );
        final gestureDetectors = find.descendant(
          of: selector,
          matching: find.byType(GestureDetector),
        );

        expect(tappables, findsNWidgets(3));
        expect(
          gestureDetectors,
          findsNWidgets(3),
          reason: 'Each enabled TreinoTappable owns exactly one '
              'GestureDetector; the selector must not add another.',
        );

        for (final label in [
          l10n.postPrivacyFriends,
          l10n.postPrivacyGym,
          l10n.postPrivacyPublic,
        ]) {
          final pillTappable = find.ancestor(
            of: find.text(label),
            matching: find.byType(TreinoTappable),
          );
          expect(
            pillTappable,
            findsOneWidget,
            reason: '$label must use TreinoTappable.',
          );
        }

        for (final element in gestureDetectors.evaluate()) {
          expect(
            find.ancestor(
              of: find.byWidget(element.widget),
              matching: find.byType(TreinoTappable),
            ),
            findsOneWidget,
            reason: 'GestureDetector must belong to TreinoTappable, not the '
                'selector.',
          );
        }
      },
    );

    testWidgets('tapping a pill reports the selected privacy', (tester) async {
      PostPrivacy? selectedPrivacy;
      await tester.pumpWidget(
        _wrap(onSelect: (privacy) => selectedPrivacy = privacy),
      );

      await tester.tap(find.text(l10n.postPrivacyPublic));
      await tester.pump();

      expect(selectedPrivacy, PostPrivacy.public);
    });
  });
}
