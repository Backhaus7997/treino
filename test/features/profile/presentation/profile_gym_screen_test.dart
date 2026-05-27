import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_gym_screen.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/domain/gym.dart';

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
const _currentGymId = 'smart-fit-palermo';

UserProfile _profile({String? gymId = _currentGymId}) => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
    );

const List<Gym> _testGyms = [
  Gym(id: 'gym-a', name: 'GYM NORTE', address: 'Av. Norte 100'),
  Gym(id: 'gym-b', name: 'GYM SUR', address: 'Av. Sur 200'),
];

Widget _buildScreen({
  required UserProfile profile,
  required MockUserRepository repo,
  List<Gym> gyms = _testGyms,
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
      filteredGymsProvider.overrideWithValue(gyms),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-516, SCENARIO-517
// ---------------------------------------------------------------------------

void main() {
  late MockUserRepository mockRepo;

  setUp(() {
    mockRepo = MockUserRepository();
    when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});
  });

  group('ProfileGymScreen', () {
    // SCENARIO-516: gym list renders
    testWidgets('SCENARIO-516: renders gym catalog list', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(),
          repo: mockRepo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GYM NORTE'), findsOneWidget);
      expect(find.text('GYM SUR'), findsOneWidget);
    });

    // SCENARIO-517: select a gym and confirm → UserRepository.update called
    testWidgets(
        'SCENARIO-517: selecting a gym and confirming calls UserRepository.update',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(gymId: null), // start with no gym selected
          repo: mockRepo,
          gyms: const [
            Gym(
                id: 'crossfit-norte-id',
                name: 'CROSSFIT NORTE',
                address: 'Av. Libertad 500'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Tap the gym card to select it.
      await tester.tap(find.text('CROSSFIT NORTE'));
      await tester.pumpAndSettle();

      // Tap the save button.
      await tester.tap(find.text('GUARDAR')); // i18n: Fase 6 Etapa 3
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.update(_uid, {'gymId': 'crossfit-norte-id'}),
      ).called(1);
    });

    // Regression guard 2026-05-27 — gymSearchQueryProvider was retaining
    // its value across screen re-entries while the TextField re-initialized
    // empty, producing a stale filter with no visible query.
    testWidgets(
        'regression: gymSearchQueryProvider resets to "" on mount even if previously set',
        (tester) async {
      final mockUser = MockUser();
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith((_) => Stream.value(mockUser)),
          userProfileProvider.overrideWith((_) => Stream.value(_profile())),
          userRepositoryProvider.overrideWithValue(mockRepo),
          filteredGymsProvider.overrideWithValue(_testGyms),
        ],
      );
      addTearDown(container.dispose);

      container.read(gymSearchQueryProvider.notifier).state = 'palermo';
      expect(container.read(gymSearchQueryProvider), 'palermo');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: ProfileGymScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(gymSearchQueryProvider), '');
    });

    // Save disabled when selection == current gymId
    testWidgets(
        'save button is disabled when pending selection equals current gymId',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(gymId: 'gym-a'),
          repo: mockRepo,
          gyms: const [
            Gym(id: 'gym-a', name: 'GYM NORTE', address: 'Av. Norte 100'),
            Gym(id: 'gym-b', name: 'GYM SUR', address: 'Av. Sur 200'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The current gym is gym-a. Tapping it again shouldn't enable save
      // since it equals currentGymId.
      await tester.tap(find.text('GYM NORTE'));
      await tester.pumpAndSettle();

      // The save button should be disabled (no pending change from current).
      final saveButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'GUARDAR'), // i18n: Fase 6 Etapa 3
      );
      expect(saveButton.onPressed, isNull);
    });
  });
}
