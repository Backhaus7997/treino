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

    // Regression guard 2026-05-27 (rewritten 2026-06-01):
    // gymSearchQueryProvider was retaining its value across screen re-entries
    // while the TextField re-initialized empty, producing a stale filter with
    // no visible query. Original fix was a manual reset in initState; proper
    // fix (2026-06-01) was to mark the provider as autoDispose so its state
    // is destroyed automatically when no widget watches it. This test asserts
    // the provider IS autoDispose — if someone removes the .autoDispose, the
    // bug returns and this test fails.
    test('regression: gymSearchQueryProvider is autoDispose', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Listen + mutate state.
      final sub = container.listen(gymSearchQueryProvider, (_, __) {});
      container.read(gymSearchQueryProvider.notifier).state = 'palermo';
      expect(container.read(gymSearchQueryProvider), 'palermo');

      // Drop the subscription. Riverpod's autoDispose runs on the next
      // microtask — not synchronously — so we yield once before re-reading.
      sub.close();
      await Future<void>.delayed(Duration.zero);

      // Provider was disposed and re-built with its default value.
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
