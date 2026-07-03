// gym-selection-v2 Phase 2 tasks 2.6/2.7 — pinned current-gym card,
// design AD-11: reuses gymByIdProvider + gymDisplayNameFromGym (the
// profile_cuenta_section.dart pattern), display-only, hidden for
// null/kNoGymId.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/profile/presentation/widgets/pinned_current_gym.dart';
import 'package:treino/l10n/app_l10n.dart';

Gym _gym({
  String id = 'gym-1',
  String name = 'SportClub Belgrano',
}) =>
    Gym(
      id: id,
      name: name,
      address: 'Cabildo 1789',
      lat: -34.56,
      lng: -58.45,
      geohash: 'abcde',
      source: GymSource.seed,
      createdAt: DateTime(2025),
    );

Widget _wrap({
  required String? currentGymId,
  List<Override> overrides = const [],
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: PinnedCurrentGym(currentGymId: currentGymId),
        ),
      ),
    );

void main() {
  testWidgets('renders the resolved gym name via overridden gymByIdProvider',
      (tester) async {
    await tester.pumpWidget(_wrap(
      currentGymId: 'gym-1',
      overrides: [
        gymByIdProvider('gym-1')
            .overrideWith((ref) async => _gym(name: 'SportClub Belgrano')),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('SportClub Belgrano'), findsOneWidget);
  });

  testWidgets('shows a loading state while the gym name resolves',
      (tester) async {
    await tester.pumpWidget(_wrap(
      currentGymId: 'gym-1',
      overrides: [
        gymByIdProvider('gym-1').overrideWith(
          (ref) => Completer<Gym?>().future,
        ),
      ],
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hidden entirely when currentGymId is null', (tester) async {
    await tester.pumpWidget(_wrap(currentGymId: null));
    await tester.pumpAndSettle();

    expect(find.byType(PinnedCurrentGym), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widget<PinnedCurrentGym>(find.byType(PinnedCurrentGym))
          .currentGymId,
      isNull,
    );
    // Renders nothing observable — no Text/Card/Container content at all.
    expect(
        find.descendant(
          of: find.byType(PinnedCurrentGym),
          matching: find.byType(Text),
        ),
        findsNothing);
  });

  testWidgets('hidden entirely when currentGymId is kNoGymId', (tester) async {
    await tester.pumpWidget(_wrap(currentGymId: kNoGymId));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
