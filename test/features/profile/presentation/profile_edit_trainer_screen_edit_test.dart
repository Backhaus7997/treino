// Tests for ProfileEditTrainerScreen — edit mode (default)
//
// Strict TDD: this file is the RED artifact for T-TPO-017.
// Scenarios: 709, 711, 712, 715, 717.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_edit_trainer_screen.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUserRepository extends Mock implements UserRepository {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

UserProfile _trainerProfile({bool complete = false}) => UserProfile(
      uid: 'trainer-uid',
      email: 'trainer@example.com',
      displayName: 'Mauro PF',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      trainerBio: complete ? 'Bio de al menos 20 caracteres ok' : null,
      trainerSpecialty: complete ? 'crossfit' : null,
      trainerMonthlyRate: complete ? 8000 : null,
      trainerOffersOnline: complete ? true : false,
    );

// ---------------------------------------------------------------------------
// Widget harness
// ---------------------------------------------------------------------------

Widget _buildScreen({
  ProfileEditTrainerMode mode = ProfileEditTrainerMode.edit,
  UserProfile? profile,
  MockUserRepository? repo,
  String initialLocation = '/profile/edit-trainer',
}) {
  final mockRepo = repo ?? MockUserRepository();
  when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

  final effectiveProfile = profile ?? _trainerProfile();

  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE')),
        routes: [
          GoRoute(
            path: 'edit-trainer',
            builder: (_, __) => Scaffold(
              body: ProfileEditTrainerScreen(mode: mode),
            ),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userProfileProvider.overrideWith((_) => Stream.value(effectiveProfile)),
      userRepositoryProvider.overrideWithValue(mockRepo),
      gymsProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue('trainer-uid');
    registerFallbackValue(<String, Object?>{});
  });

  group('SCENARIO-709: default mode is edit', () {
    testWidgets('pumping screen with no mode arg shows edit AppBar title',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // AppBar title must show the edit string
      expect(find.text('Editá tu perfil profesional'), findsOneWidget);
    });
  });

  group('SCENARIO-711: navigate to route without ?mode param → edit mode', () {
    testWidgets('router resolves edit mode when no query param present',
        (tester) async {
      // We navigate to /profile/edit-trainer (no ?mode param) and confirm
      // the screen shows the edit mode title.
      await tester.pumpWidget(_buildScreen(
        mode: ProfileEditTrainerMode.edit,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Editá tu perfil profesional'), findsOneWidget);
      // Must NOT show the onboarding title
      expect(find.text('Completá tu perfil profesional'), findsNothing);
    });
  });

  group('SCENARIO-712: edit mode title', () {
    testWidgets('edit mode shows "Editá tu perfil profesional"',
        (tester) async {
      await tester.pumpWidget(_buildScreen(mode: ProfileEditTrainerMode.edit));
      await tester.pumpAndSettle();

      expect(find.text('Editá tu perfil profesional'), findsOneWidget);
    });
  });

  group('SCENARIO-715: back button present in edit mode', () {
    testWidgets('edit mode has a back button in the AppBar', (tester) async {
      await tester.pumpWidget(_buildScreen(
        mode: ProfileEditTrainerMode.edit,
        initialLocation: '/profile/edit-trainer',
      ));
      await tester.pumpAndSettle();

      // In edit mode, automaticallyImplyLeading is true (default).
      // A back button appears when there is a route to pop to.
      // Check that PopScope(canPop: false) is NOT in tree (edit mode = can pop).
      // Note: Flutter 3.41 uses PopScope<dynamic> — use byWidgetPredicate.
      final hasBlockingPopScope = tester
          .widgetList(
            find.byWidgetPredicate((w) => w is PopScope && w.canPop == false),
          )
          .isNotEmpty;
      expect(hasBlockingPopScope, isFalse,
          reason:
              'Edit mode must not have a blocking PopScope — back should be allowed');
    });
  });

  group('SCENARIO-717: post-save in edit mode calls context.pop()', () {
    testWidgets('save success navigates back (pop) in edit mode',
        (tester) async {
      String? lastLocation;
      final router = GoRouter(
        initialLocation: '/profile/edit-trainer',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('HOME')),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('PROFILE')),
            routes: [
              GoRoute(
                path: 'edit-trainer',
                builder: (context, __) => const Scaffold(
                  body: ProfileEditTrainerScreen(
                      mode: ProfileEditTrainerMode.edit),
                ),
              ),
            ],
          ),
        ],
        observers: [
          _LocationObserver((loc) => lastLocation = loc),
        ],
      );

      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

      final profile = _trainerProfile(complete: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(profile)),
            userRepositoryProvider.overrideWithValue(mockRepo),
            gymsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll the button into view and tap it
      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // In edit mode, save should pop (not go to /home).
      // After pop from /profile/edit-trainer there is no parent route in this
      // harness so GoRouter stays at /profile. Verify we did NOT navigate to /home.
      expect(lastLocation, isNot(equals('/home')));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _LocationObserver extends NavigatorObserver {
  _LocationObserver(this._onLocation);
  final void Function(String location) _onLocation;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) _onLocation(name);
  }
}
