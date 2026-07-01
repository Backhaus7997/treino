// ADR-PSR-011: onboarding (Step2Gym) and profile-edit (ProfileGymScreen) MUST
// expose the same two-step brand→sucursal picker behavior. This test drives
// both entry points against the same gym catalog and asserts parity.
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_gym_screen.dart';
import 'package:treino/features/profile_setup/application/profile_setup_notifier.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_draft.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_2_gym.dart';
import 'package:treino/l10n/app_l10n.dart';

class _FakeProfileSetupNotifier extends ProfileSetupNotifier {
  @override
  ProfileSetupState build() =>
      const ProfileSetupState(draft: ProfileSetupDraft(), currentStep: 1);

  @override
  void updateGymId(String? value) =>
      state = state.copyWith(draft: state.draft.copyWith(gymId: value));
}

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

class MockUserRepository extends Mock implements UserRepository {}

Gym _gym({
  required String id,
  required String name,
  String? brandId,
  String? brandName,
  String? branchName,
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
    );

final _sportclubBelgrano = _gym(
  id: 'sportclub-belgrano',
  name: 'SportClub - Belgrano',
  brandId: 'sportclub',
  brandName: 'SportClub',
  branchName: 'Belgrano',
);
final _sportclubPilar = _gym(
  id: 'sportclub-pilar',
  name: 'SportClub - Pilar',
  brandId: 'sportclub',
  brandName: 'SportClub',
  branchName: 'Pilar',
);
final _megatlonRecoleta = _gym(
  id: 'megatlon-recoleta',
  name: 'Megatlon Recoleta',
  brandId: 'megatlon-recoleta',
  brandName: 'Megatlon',
);

final _catalog = [_sportclubBelgrano, _sportclubPilar, _megatlonRecoleta];

Widget _onboardingEntry() => ProviderScope(
      overrides: [
        gymsProvider.overrideWith((ref) async => _catalog),
        profileSetupNotifierProvider
            .overrideWith(_FakeProfileSetupNotifier.new),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Step2Gym()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

Widget _profileEditEntry(MockUserRepository repo) {
  final router = GoRouter(
    initialLocation: '/profile/gym',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE_SCREEN')),
        routes: [
          GoRoute(
            path: 'gym',
            builder: (_, __) => const Scaffold(body: ProfileGymScreen()),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(MockUser())),
      userProfileProvider.overrideWith((_) => Stream.value(UserProfile(
            uid: 'test-uid',
            email: 'test@test.com',
            displayName: 'Test User',
            role: UserRole.athlete,
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
            gymId: null,
          ))),
      userRepositoryProvider.overrideWithValue(repo),
      gymsProvider.overrideWith((ref) async => _catalog),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  group('ADR-PSR-011: onboarding/profile-edit picker parity', () {
    testWidgets('both entry points show the same brand list at step 1',
        (tester) async {
      await tester.pumpWidget(_onboardingEntry());
      await tester.pumpAndSettle();
      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsOneWidget);

      // Riverpod's ProviderScope forbids changing override count on a widget
      // rebuild — reset to an empty tree before mounting the other entry
      // point (which has a different override list: auth/profile/repo).
      await tester.pumpWidget(const SizedBox.shrink());

      final repo = MockUserRepository();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});
      await tester.pumpWidget(_profileEditEntry(repo));
      await tester.pumpAndSettle();
      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsOneWidget);
    });

    testWidgets(
        'both entry points drill into branch list for a multi-branch brand',
        (tester) async {
      await tester.pumpWidget(_onboardingEntry());
      await tester.pumpAndSettle();
      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();
      expect(find.text('Belgrano'), findsOneWidget);
      expect(find.text('Pilar'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());

      final repo = MockUserRepository();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});
      await tester.pumpWidget(_profileEditEntry(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();
      expect(find.text('Belgrano'), findsOneWidget);
      expect(find.text('Pilar'), findsOneWidget);
    });

    testWidgets(
        'both entry points skip step 2 for an independent single-branch brand',
        (tester) async {
      await tester.pumpWidget(_onboardingEntry());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Megatlon'));
      await tester.pumpAndSettle();
      expect(find.text('Belgrano'), findsNothing);
      final onboardingContainer = ProviderScope.containerOf(
        tester.element(find.byType(Step2Gym)),
      );
      expect(
        onboardingContainer.read(profileSetupNotifierProvider).draft.gymId,
        'megatlon-recoleta',
      );

      await tester.pumpWidget(const SizedBox.shrink());

      final repo = MockUserRepository();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});
      await tester.pumpWidget(_profileEditEntry(repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Megatlon'));
      await tester.pumpAndSettle();
      expect(find.text('Belgrano'), findsNothing);

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();
      verify(
        () => repo.update('test-uid', {'gymId': 'megatlon-recoleta'}),
      ).called(1);
    });
  });
}
