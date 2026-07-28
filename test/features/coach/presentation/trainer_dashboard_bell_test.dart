import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// #393: the trainer home bell used to be a bare, inert Icon (no tap handler).
// It OPENS A MODAL listing the pending link requests (accept/decline). (The
// first cut scrolled to the inline card, which was useless since that card is
// already on screen when the bell is reachable.)
//
// It was then gated on badgeCount > 0 and sat inert at zero, which read as
// broken — tapping did nothing and there was no way to tell that from a bug.
// It always opens now, and the sheet owns the empty state.

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: Center(child: child)),
    );

TrainerLink _pending(String id, String athleteId) => TrainerLink(
      id: id,
      trainerId: 't1',
      athleteId: athleteId,
      status: TrainerLinkStatus.pending,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: null,
      sharedWithTrainer: false,
    );

void main() {
  group('trainer home bell (#393)', () {
    testWidgets(
        'with pending requests → tapping the bell invokes onTap (was inert)',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        BellWithBadgeTestHarness(badgeCount: 3, onTap: () => taps++),
      ));

      expect(find.byIcon(TreinoIcon.bell), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // badge rendered

      // warnIfMissed: the visible badge overlaps the icon's centre, but the tap
      // still lands on the wrapping GestureDetector — which is the point.
      await tester.tap(find.byIcon(TreinoIcon.bell), warnIfMissed: false);
      expect(taps, 1);
    });

    // Superseded: the bell used to be INERT at badgeCount == 0, which read as
    // broken — a trainer with no requests tapped it and nothing happened, with
    // no way to tell that from a bug. It always opens now; the sheet owns the
    // empty state.
    testWidgets('with zero pending requests → the bell still opens',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        BellWithBadgeTestHarness(badgeCount: 0, onTap: () => taps++),
      ));

      expect(find.byIcon(TreinoIcon.bell), findsOneWidget);
      expect(find.text('0'), findsNothing); // still no badge at zero

      await tester.tap(find.byIcon(TreinoIcon.bell), warnIfMissed: false);
      expect(taps, 1);
    });
  });

  group('pending-requests modal (#393)', () {
    testWidgets('renders one accept/decline card per pending request',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value([
              _pending('l1', 'a1'),
              _pending('l2', 'a2'),
            ]),
          ),
          // Athlete names resolve to the fallback (no Firebase in the test).
          userPublicProfileProvider.overrideWith(
            (ref, uid) => Stream<UserPublicProfile?>.value(null),
          ),
        ],
        child: _wrap(const PendingRequestsSheetTestHarness()),
      ));
      await tester.pumpAndSettle();

      // One card per pending request → 2 Aceptar (ElevatedButton) + 2 Rechazar
      // (OutlinedButton) actions.
      expect(find.byType(ElevatedButton), findsNWidgets(2));
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    });

    // The sheet reaches "empty" two ways that need OPPOSITE behaviour, so both
    // are pinned here.

    testWidgets('opened with none → empty state, and it STAYS open',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(const <TrainerLink>[]),
          ),
          userPublicProfileProvider.overrideWith(
            (ref, uid) => Stream<UserPublicProfile?>.value(null),
          ),
        ],
        child: _wrap(const PendingRequestsSheetTestHarness()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No tenés solicitudes pendientes.'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      // Still mounted — it must not auto-close on this path.
      expect(find.byType(PendingRequestsSheetTestHarness), findsOneWidget);
    });

    testWidgets(
        'the LAST request disappearing still auto-closes (not an empty state)',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          trainerLinksStreamProvider.overrideWith((ref) => controller.stream),
          userPublicProfileProvider.overrideWith(
            (ref, uid) => Stream<UserPublicProfile?>.value(null),
          ),
        ],
        child: _wrap(const Text('BASE')),
      ));

      // Pushed as a real route: `maybePop` is a no-op on the only route in the
      // stack, so the sheet needs something underneath for the auto-close to
      // be observable at all.
      Navigator.of(tester.element(find.text('BASE'))).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const Scaffold(body: PendingRequestsSheetTestHarness()),
        ),
      );
      await tester.pumpAndSettle();

      // Opens WITH a request…
      controller.add([_pending('l1', 'a1')]);
      await tester.pumpAndSettle();
      expect(find.byType(ElevatedButton), findsOneWidget);

      // …and the trainer resolves the last one.
      controller.add(const <TrainerLink>[]);
      await tester.pumpAndSettle();

      expect(
        find.byType(PendingRequestsSheetTestHarness),
        findsNothing,
        reason: 'must auto-close, not sit on an empty state — the trainer '
            'just acted, they did not come to browse',
      );
      expect(find.text('BASE'), findsOneWidget);
      expect(find.text('No tenés solicitudes pendientes.'), findsNothing);
    });
  });
}
