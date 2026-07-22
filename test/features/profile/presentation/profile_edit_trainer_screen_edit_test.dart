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
import 'package:treino/l10n/app_l10n.dart';

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
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
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

    // QA-PRO-008 (#429): the sign-out escape hatch is onboarding-only — edit
    // mode already has the back arrow, so no extra exit belongs there.
    testWidgets('edit mode does NOT show the onboarding sign-out action',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        mode: ProfileEditTrainerMode.edit,
        initialLocation: '/profile/edit-trainer',
      ));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('trainer_onboarding_sign_out')),
        findsNothing,
        reason: 'Sign-out action is an onboarding-only escape hatch',
      );
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
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
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

  group('#388: campo AÑOS DE EXPERIENCIA', () {
    testWidgets('prefills the field from profile.trainerExperienceYears',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        profile:
            _trainerProfile(complete: true).copyWith(trainerExperienceYears: 7),
      ));
      await tester.pumpAndSettle();

      final field = tester.widget<TextFormField>(
        find.byKey(const Key('profile_edit_trainer_experience_field')),
      );
      expect(field.controller?.text, equals('7'));
    });

    testWidgets('save sends the typed value as int in the update partial',
        (tester) async {
      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_buildScreen(
        profile: _trainerProfile(complete: true),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile_edit_trainer_experience_field')),
        '12',
      );
      // Desfocusear el campo: un EditableText focuseado re-scrollea al caret
      // en cada frame y anula el ensureVisible del botón (tap off-screen).
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.update('trainer-uid', captureAny()))
              .captured
              .single as Map<String, Object?>;
      expect(captured['trainerExperienceYears'], equals(12));
    });

    testWidgets(
        'empty field is optional: save proceeds and sends null (perfil '
        'público cae al "—")', (tester) async {
      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_buildScreen(
        profile: _trainerProfile(complete: true),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockRepo.update('trainer-uid', captureAny()))
              .captured
              .single as Map<String, Object?>;
      expect(captured.containsKey('trainerExperienceYears'), isTrue);
      expect(captured['trainerExperienceYears'], isNull);
    });

    testWidgets('rejects a non-integer value with the inline validator',
        (tester) async {
      final mockRepo = MockUserRepository();
      when(() => mockRepo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(_buildScreen(
        profile: _trainerProfile(complete: true),
        repo: mockRepo,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('profile_edit_trainer_experience_field')),
        '999',
      );
      // Ver comentario en el test anterior: unfocus antes de scrollear.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('profile_edit_trainer_save_button'));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Entre 0 y 80 años.'), findsOneWidget);
      verifyNever(() => mockRepo.update(any(), any()));
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
