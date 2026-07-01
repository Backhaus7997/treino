import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_hero.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';

Gym _gym({
  String id = 'sportclub-belgrano',
  String name = 'SportClub - Belgrano',
}) =>
    Gym(
      id: id,
      name: name,
      lat: -34.56,
      lng: -58.45,
      geohash: 'abc123',
      source: GymSource.seed,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// [overrides] lets each test stub `gymByIdProvider` per the [authorGymId] it
/// passes to [_view] — DETAIL context resolves live via the provider now
/// (gyms-foundation Phase 3), not a hardcoded map.
Widget _wrap(Widget w, {List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: w),
      ),
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

    testWidgets('SCENARIO-212: display name is rendered UPPERCASE',
        (tester) async {
      await tester.pumpWidget(
          _wrap(PublicProfileHero(view: _view(authorDisplayName: 'Tincho'))));
      await tester.pump();
      expect(find.text('TINCHO'), findsOneWidget);
      expect(find.text('Tincho'), findsNothing);
    });

    testWidgets(
        'SCENARIO-213: known gymId resolves to the real composed gym name '
        'via gymByIdProvider', (tester) async {
      await tester.pumpWidget(_wrap(
        PublicProfileHero(view: _view(authorGymId: 'sportclub-belgrano')),
        overrides: [
          gymByIdProvider('sportclub-belgrano').overrideWith(
            (ref) async => _gym(name: 'SportClub - Belgrano'),
          ),
        ],
      ));
      await tester.pump();
      expect(find.text('SportClub - Belgrano'), findsOneWidget);
    });

    testWidgets('SCENARIO-214: null gymId → no gym subtitle rendered',
        (tester) async {
      await tester
          .pumpWidget(_wrap(PublicProfileHero(view: _view(authorGymId: null))));
      await tester.pump();
      // No gym name visible; only "TINCHO" header
      expect(find.text('TINCHO'), findsOneWidget);
      expect(find.text('SportClub - Belgrano'), findsNothing);
    });

    testWidgets(
        'SCENARIO-532: unknown gymId (gymByIdProvider resolves null) → no '
        'gym subtitle rendered, no crash', (tester) async {
      await tester.pumpWidget(_wrap(
        PublicProfileHero(view: _view(authorGymId: 'ghost-gym-id')),
        overrides: [
          gymByIdProvider('ghost-gym-id').overrideWith((ref) async => null),
        ],
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('TINCHO'), findsOneWidget);
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
