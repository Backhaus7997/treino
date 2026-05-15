import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_hero.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: w),
    );

PublicProfileView _view({
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
}) =>
    PublicProfileView(
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      friendship: null,
      isSelf: false,
    );

void main() {
  group('PublicProfileHero', () {
    testWidgets('SCENARIO-211: renders PostAvatar with size 96',
        (tester) async {
      await tester.pumpWidget(_wrap(PublicProfileHero(view: _view())));
      await tester.pump();

      final avatar = tester.widget<PostAvatar>(find.byType(PostAvatar));
      expect(avatar.size, equals(96));
      expect(avatar.authorDisplayName, equals('Tincho'));
    });

    testWidgets(
        'SCENARIO-212: display name is rendered UPPERCASE',
        (tester) async {
      await tester
          .pumpWidget(_wrap(PublicProfileHero(view: _view(authorDisplayName: 'Tincho'))));
      await tester.pump();
      expect(find.text('TINCHO'), findsOneWidget);
      expect(find.text('Tincho'), findsNothing);
    });

    testWidgets('SCENARIO-213: known gymId resolves to gym name', (tester) async {
      await tester.pumpWidget(_wrap(PublicProfileHero(
        view: _view(authorGymId: 'smart-fit-palermo'),
      )));
      await tester.pump();
      expect(find.text('SMART FIT'), findsOneWidget);
    });

    testWidgets('SCENARIO-214: null gymId → no gym subtitle rendered',
        (tester) async {
      await tester
          .pumpWidget(_wrap(PublicProfileHero(view: _view(authorGymId: null))));
      await tester.pump();
      // No gym name visible; only "TINCHO" header
      expect(find.text('TINCHO'), findsOneWidget);
      expect(find.text('SMART FIT'), findsNothing);
      expect(find.text('SPORTCLUB'), findsNothing);
      expect(find.text('MEGATLON'), findsNothing);
    });

    testWidgets(
        'SCENARIO-215: "Anónimo" displayName → PostAvatar shows "?" initial',
        (tester) async {
      await tester.pumpWidget(_wrap(PublicProfileHero(
        view: _view(authorDisplayName: 'Anónimo'),
      )));
      await tester.pump();
      expect(find.text('ANÓNIMO'), findsOneWidget);
      // PostAvatar's _computeInitial maps 'Anónimo' → '?'
      expect(find.text('?'), findsOneWidget);
    });
  });
}
