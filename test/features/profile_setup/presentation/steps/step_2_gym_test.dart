import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_2_gym.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake notifier: mirrors [ProfileSetupNotifier.updateGymId] without touching
/// Firebase Auth / Firestore — this widget only exercises step-2 selection.
class _FakeProfileSetupNotifier extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() =>
      const ProfileSetupState(draft: ProfileSetupDraft(), currentStep: 1);

  @override
  void updateGymId(String? value) =>
      state = state.copyWith(draft: state.draft.copyWith(gymId: value));
}

Gym _gym({
  required String id,
  required String name,
  String? brandId,
  String? brandName,
  String? branchName,
  String? city,
}) =>
    Gym(
      id: id,
      name: name,
      lat: 0,
      lng: 0,
      geohash: 'x',
      source: GymSource.seed,
      createdAt: DateTime.utc(2026, 1, 1),
      brandId: brandId,
      brandName: brandName,
      branchName: branchName,
      city: city,
    );

final _sportclubBelgrano = _gym(
  id: 'sportclub-belgrano',
  name: 'SportClub - Belgrano',
  brandId: 'sportclub',
  brandName: 'SportClub',
  branchName: 'Belgrano',
  city: 'CABA',
);
final _sportclubPilar = _gym(
  id: 'sportclub-pilar',
  name: 'SportClub - Pilar',
  brandId: 'sportclub',
  brandName: 'SportClub',
  branchName: 'Pilar',
  city: 'GBA',
);
final _megatlonRecoleta = _gym(
  id: 'megatlon-recoleta',
  name: 'Megatlon Recoleta',
  brandId: 'megatlon-recoleta',
  brandName: 'Megatlon',
);

Widget _buildStep({
  required List<Override> overrides,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(body: Step2Gym()),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  group('Step2Gym', () {
    testWidgets('browses brands without requesting location permission',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith(
          (ref) async =>
              [_sportclubBelgrano, _sportclubPilar, _megatlonRecoleta],
        ),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsOneWidget);
      // "no gym" option always present at step 1.
      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);
    });

    testWidgets('pick chain brand shows branch list, pick branch resolves id',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith(
          (ref) async =>
              [_sportclubBelgrano, _sportclubPilar, _megatlonRecoleta],
        ),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();

      // Step 2: branch list for SportClub only.
      expect(find.text('Belgrano'), findsOneWidget);
      expect(find.text('Pilar'), findsOneWidget);
      expect(find.text('Megatlon'), findsNothing);

      await tester.tap(find.text('Belgrano'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        container.read(profileSetupNotifierProvider).draft.gymId,
        'sportclub-belgrano',
      );
    });

    testWidgets(
        'pick independent (single-branch) brand skips step 2, resolves lone sucursal',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith(
          (ref) async =>
              [_sportclubBelgrano, _sportclubPilar, _megatlonRecoleta],
        ),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Megatlon'));
      await tester.pumpAndSettle();

      // No step-2 navigation — still on brand list, no "Belgrano"/"Pilar".
      expect(find.text('Belgrano'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        container.read(profileSetupNotifierProvider).draft.gymId,
        'megatlon-recoleta',
      );
    });

    testWidgets('search filters brand list by brand name', (tester) async {
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith(
          (ref) async =>
              [_sportclubBelgrano, _sportclubPilar, _megatlonRecoleta],
        ),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'sport');
      await tester.pumpAndSettle();

      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsNothing);
    });

    testWidgets('error state shows retry that invalidates gymsProvider',
        (tester) async {
      var attempt = 0;
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith((ref) async {
          attempt++;
          if (attempt == 1) throw Exception('network down');
          return [_megatlonRecoleta];
        }),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Megatlon'), findsNothing);

      final retryFinder = find.text('Reintentar');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(find.text('Megatlon'), findsOneWidget);
    });

    testWidgets('"no gym" option remains selectable outside the two-step flow',
        (tester) async {
      await tester.pumpWidget(_buildStep(overrides: [
        gymsProvider.overrideWith(
          (ref) async => [_sportclubBelgrano, _megatlonRecoleta],
        ),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OTRO GYM / SIN GYM'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        container.read(profileSetupNotifierProvider).draft.gymId,
        kNoGymId,
      );
    });
  });
}
