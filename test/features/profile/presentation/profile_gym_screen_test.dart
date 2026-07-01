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
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {
  @override
  String get uid => 'test-uid';
}

class MockUserRepository extends Mock implements UserRepository {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';
const _currentGymId = 'sportclub-belgrano';

UserProfile _profile({String? gymId = _currentGymId}) => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
    );

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

Widget _buildScreen({
  required UserProfile profile,
  required MockUserRepository repo,
  Future<List<Gym>> Function(Ref)? gyms,
}) {
  final mockUser = MockUser();

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
      authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
      userRepositoryProvider.overrideWithValue(repo),
      gymsProvider.overrideWith(
        gyms ??
            (ref) async => [
                  _sportclubBelgrano,
                  _sportclubPilar,
                  _megatlonRecoleta,
                ],
      ),
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

// ---------------------------------------------------------------------------
// Tests — SCENARIO-516, SCENARIO-517 (two-step migration)
// ---------------------------------------------------------------------------

void main() {
  late MockUserRepository mockRepo;

  setUp(() {
    mockRepo = MockUserRepository();
    when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});
  });

  group('ProfileGymScreen', () {
    // SCENARIO-516: brand list renders (step 1)
    testWidgets('SCENARIO-516: renders brand catalog list', (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile(), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsOneWidget);
    });

    // SCENARIO-517: pick chain brand → branch → confirm → UserRepository.update
    testWidgets(
        'SCENARIO-517: selecting a branch and confirming calls UserRepository.update',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile(gymId: null), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();

      expect(find.text('Belgrano'), findsOneWidget);
      expect(find.text('Pilar'), findsOneWidget);

      await tester.tap(find.text('Belgrano'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.update(_uid, {'gymId': 'sportclub-belgrano'}),
      ).called(1);
    });

    testWidgets(
        'selecting an independent (single-branch) brand skips step 2 directly',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile(gymId: null), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Megatlon'));
      await tester.pumpAndSettle();

      // No branch-level navigation — SportClub's branches never appear.
      expect(find.text('Belgrano'), findsNothing);

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.update(_uid, {'gymId': 'megatlon-recoleta'}),
      ).called(1);
    });

    testWidgets('back from branch list returns to brand list', (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile(gymId: null), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();
      expect(find.text('Belgrano'), findsOneWidget);

      await tester.tap(find.text('VOLVER A MARCAS'));
      await tester.pumpAndSettle();

      expect(find.text('Belgrano'), findsNothing);
      expect(find.text('SportClub'), findsOneWidget);
      expect(find.text('Megatlon'), findsOneWidget);
    });

    testWidgets('error state shows retry that invalidates gymsProvider',
        (tester) async {
      var attempt = 0;
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(),
          repo: mockRepo,
          gyms: (ref) async {
            attempt++;
            if (attempt == 1) throw Exception('network down');
            return [_megatlonRecoleta];
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Megatlon'), findsNothing);
      final retryFinder = find.text('Reintentar');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(find.text('Megatlon'), findsOneWidget);
    });

    // "no gym" option preserved outside the two-step flow.
    testWidgets('"no gym" option remains selectable outside the two-step flow',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile(gymId: null), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('OTRO GYM / SIN GYM'), findsOneWidget);
      await tester.tap(find.text('OTRO GYM / SIN GYM'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(() => mockRepo.update(_uid, {'gymId': kNoGymId})).called(1);
    });

    // Save disabled when selection == current gymId
    testWidgets(
        'save button is disabled when pending selection equals current gymId',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
            profile: _profile(gymId: 'sportclub-belgrano'), repo: mockRepo),
      );
      await tester.pumpAndSettle();

      // Drill into SportClub → Belgrano again (equals currentGymId).
      await tester.tap(find.text('SportClub'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Belgrano'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'GUARDAR'), // i18n: Fase 6 Etapa 3
      );
      expect(saveButton.onPressed, isNull);
    });
  });
}
