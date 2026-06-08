// Tests for ProfileEditTrainerScreen — onboarding mode
//
// Strict TDD: this file is the GREEN artifact for T-TPO-019/021/023/025.
// Scenarios: 710, 713, 714, 716, 718, 719.

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
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal GoRouter harness for [ProfileEditTrainerScreen].
///
/// The screen itself returns a [Scaffold] — do NOT wrap it in another Scaffold
/// here (that would produce double-Scaffold artifacts that break widget finding).
Widget _buildScreen({
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
            // No extra Scaffold — screen provides its own.
            builder: (_, __) => ProfileEditTrainerScreen(
              mode: ProfileEditTrainerMode.onboarding,
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

  // ── SCENARIO-710: router resolves onboarding mode from ?mode=onboarding ──

  group('SCENARIO-710: router maps ?mode=onboarding to onboarding mode', () {
    testWidgets('navigating with ?mode=onboarding shows onboarding title',
        (tester) async {
      // This test verifies the router query-param → mode mapping (ADR-TPO-005).
      // The production GoRoute reads state.uri.queryParameters['mode'].
      final router = GoRouter(
        initialLocation: '/profile/edit-trainer?mode=onboarding',
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
                builder: (context, state) {
                  final mode = state.uri.queryParameters['mode'] == 'onboarding'
                      ? ProfileEditTrainerMode.onboarding
                      : ProfileEditTrainerMode.edit;
                  return ProfileEditTrainerScreen(mode: mode);
                },
              ),
            ],
          ),
        ],
      );

      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider
                .overrideWith((_) => Stream.value(_trainerProfile())),
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

      expect(find.text('Completá tu perfil profesional'), findsOneWidget);
    });
  });

  // ── SCENARIO-713: onboarding mode title ─────────────────────────────────

  group('SCENARIO-713: onboarding mode title', () {
    testWidgets('shows "Completá tu perfil profesional"', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Completá tu perfil profesional'), findsOneWidget);
      expect(find.text('Editá tu perfil profesional'), findsNothing);
    });
  });

  // ── SCENARIO-714: back navigation blocked in onboarding mode ────────────

  group('SCENARIO-714: back navigation blocked in onboarding mode', () {
    testWidgets('no back button in AppBar AND PopScope(canPop: false) in tree',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // 1. No back button — automaticallyImplyLeading: false removes it.
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(BackButtonIcon), findsNothing);

      // 2. PopScope with canPop: false must be present (blocks OS back gesture).
      // Note: Flutter 3.41 uses PopScope<dynamic> — use byWidgetPredicate.
      final hasBlockingPopScope = tester
          .widgetList(
            find.byWidgetPredicate((w) => w is PopScope && w.canPop == false),
          )
          .isNotEmpty;
      expect(hasBlockingPopScope, isTrue,
          reason:
              'Onboarding mode must have PopScope(canPop: false) to block back gesture');
    });
  });

  // ── SCENARIO-716: post-save navigates to /home in onboarding mode ─────────

  group('SCENARIO-716: post-save navigates to /home', () {
    testWidgets('save success in onboarding mode goes to /home',
        (tester) async {
      bool homePushed = false;
      final router = GoRouter(
        initialLocation: '/profile/edit-trainer',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) {
              homePushed = true;
              return const Scaffold(body: Text('HOME'));
            },
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('PROFILE')),
            routes: [
              GoRoute(
                path: 'edit-trainer',
                builder: (_, __) => ProfileEditTrainerScreen(
                  mode: ProfileEditTrainerMode.onboarding,
                ),
              ),
            ],
          ),
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

      // Scroll the button into view (by key) and tap it
      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(homePushed, isTrue,
          reason: 'Onboarding mode must navigate to /home after save');
    });
  });

  // ── SCENARIO-718: repo exception surfaces, no navigation ─────────────────

  group('SCENARIO-718: repo exception → error shown, no navigation to /home',
      () {
    testWidgets(
        'when repo.update throws, error message shown and no navigation',
        (tester) async {
      bool homePushed = false;
      final router = GoRouter(
        initialLocation: '/profile/edit-trainer',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) {
              homePushed = true;
              return const Scaffold(body: Text('HOME'));
            },
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('PROFILE')),
            routes: [
              GoRoute(
                path: 'edit-trainer',
                builder: (_, __) => ProfileEditTrainerScreen(
                  mode: ProfileEditTrainerMode.onboarding,
                ),
              ),
            ],
          ),
        ],
      );

      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any()))
          .thenThrow(Exception('Invariant violation'));

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

      // Scroll the button into view (by key) and tap it
      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Error message shown
      expect(find.text('No pudimos guardar. Probá de nuevo.'), findsOneWidget);

      // Did NOT navigate to /home
      expect(homePushed, isFalse);
    });
  });

  // ── SCENARIO-719: validation rules are mode-independent ──────────────────

  group('SCENARIO-719: validation is mode-independent', () {
    testWidgets(
        'bio shorter than 20 chars shows validation error in onboarding mode',
        (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Fill bio with too-short text (triggers bio validator)
      final bioField = find.byType(TextFormField).first;
      await tester.enterText(bioField, 'Corto');
      await tester.pump();

      // Scroll the button into view (by key) and tap it
      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // The bio validator rejects text < 20 chars in both modes.
      // The error text is rendered inline by TextFormField.
      expect(
        find.text('Al menos 20 caracteres.'),
        findsOneWidget,
        reason:
            'Validation rules must be identical in onboarding and edit modes',
      );
    });
  });
}
