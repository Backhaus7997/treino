import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/solicitudes/solicitudes_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// SolicitudesScreen — `/solicitudes`, reached from the Coach Hub top-bar
// bell. Mirror of the mobile FriendRequestsInboxScreen: lists PENDING
// trainer-link requests, accept/decline via the shared PendingRequestsList
// (extracted from the dashboard's former _PendingRequestsList/_PendingRequestTile).

class _MockLinkRepo extends Mock implements TrainerLinkRepository {}

TrainerLink _pending(String id, String athleteId) => TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.pending,
      requestedAt: DateTime.utc(2026, 1, 1),
    );

TrainerLink _active(String id, String athleteId) => TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

List<Override> _stubLinks(List<TrainerLink> links,
    {TrainerLinkRepository? repo}) {
  return <Override>[
    trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
    for (final l in links)
      userPublicProfileProvider(l.athleteId).overrideWith(
        (ref) => Stream.value(UserPublicProfile(
          uid: l.athleteId,
          displayName: 'Atleta ${l.id}',
          displayNameLowercase: 'atleta ${l.id}',
        )),
      ),
    if (repo != null) trainerLinkRepositoryProvider.overrideWithValue(repo),
  ];
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  group('SolicitudesScreen — pending requests list', () {
    testWidgets('with pending links → lists the athlete tile', (tester) async {
      final links = [_pending('r1', 'a1')];
      await tester.pumpWidget(_wrap(
        const SolicitudesScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Atleta r1'), findsOneWidget);
      expect(find.byKey(const Key('accept_r1')), findsOneWidget);
      expect(find.byKey(const Key('decline_r1')), findsOneWidget);
    });

    testWidgets('no pending links → shows empty state', (tester) async {
      final links = [_active('a1', 'a1')];
      await tester.pumpWidget(_wrap(
        const SolicitudesScreen(),
        overrides: _stubLinks(links),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('No tenés solicitudes pendientes.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('accept_a1')), findsNothing);
    });

    testWidgets('empty links list → shows empty state', (tester) async {
      await tester.pumpWidget(_wrap(
        const SolicitudesScreen(),
        overrides: _stubLinks(const []),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('No tenés solicitudes pendientes.'),
        findsOneWidget,
      );
    });
  });

  group('SolicitudesScreen — accept / decline', () {
    // NOTE: on a successful accept/decline the tile's `_busy` flag has no
    // reset (only the catch-path resets it — see PendingRequestTile) since
    // in the real app the stream re-emits without the resolved link. Here
    // the stubbed stream is static, so the tile is left showing a
    // CircularProgressIndicator forever — an indefinite animation that
    // `pumpAndSettle` cannot settle. Use a bounded `pump` instead, same as
    // the mobile trainer_dashboard_bell_test.dart does for this exact shape.
    testWidgets('tapping accept calls trainerLinkRepository.accept',
        (tester) async {
      final repo = _MockLinkRepo();
      when(() => repo.accept(any())).thenAnswer((_) async {});
      final links = [_pending('r1', 'a1')];

      await tester.pumpWidget(_wrap(
        const SolicitudesScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('accept_r1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => repo.accept('r1')).called(1);
    });

    testWidgets('tapping decline calls trainerLinkRepository.decline',
        (tester) async {
      final repo = _MockLinkRepo();
      when(() => repo.decline(any())).thenAnswer((_) async {});
      final links = [_pending('r1', 'a1')];

      await tester.pumpWidget(_wrap(
        const SolicitudesScreen(),
        overrides: _stubLinks(links, repo: repo),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('decline_r1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => repo.decline('r1')).called(1);
    });
  });
}
