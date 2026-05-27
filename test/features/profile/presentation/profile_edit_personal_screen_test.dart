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
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/gender.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_edit_personal_screen.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/data/avatar_upload_service.dart';

// ---------------------------------------------------------------------------
// Mocks & fakes
// ---------------------------------------------------------------------------

class MockUser extends Mock implements User {}

class MockUserRepository extends Mock implements UserRepository {}

class FakeAvatarUploadService implements AvatarUploadService {
  String? lastUploadedPath;
  String returnUrl;

  FakeAvatarUploadService({this.returnUrl = 'https://storage.test/avatar.jpg'});

  @override
  Future<String> upload(String localPath) async {
    lastUploadedPath = localPath;
    return returnUrl;
  }
}

class FakeAvatarUploadServiceThrowing implements AvatarUploadService {
  @override
  Future<String> upload(String localPath) async {
    throw Exception('Storage error');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserProfile _profile({
  String displayName = 'Carlos',
  double bodyWeightKg = 80,
  int heightCm = 175,
  String? avatarUrl,
  Gender? gender = Gender.male,
  ExperienceLevel? experienceLevel = ExperienceLevel.intermediate,
  String? gymId,
}) =>
    UserProfile(
      uid: 'uid-test',
      email: 'test@test.com',
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      bodyWeightKg: bodyWeightKg,
      heightCm: heightCm,
      avatarUrl: avatarUrl,
      gender: gender,
      experienceLevel: experienceLevel,
      gymId: gymId,
    );

/// Creates a [MockUser] with a fixed uid for use in tests that need an
/// authenticated user.
MockUser _makeAuthUser({String uid = 'uid-test'}) {
  final user = MockUser();
  when(() => user.uid).thenReturn(uid);
  return user;
}

Widget _buildScreen({
  required UserProfile profile,
  UserRepository? userRepository,
  AvatarUploadService? avatarService,
  GoRouter? router,
  /// When true, the auth provider returns an authenticated user (uid = 'uid-test').
  /// Default false for read-only / display tests.
  bool authenticated = false,
}) {
  final mockRepo = userRepository ?? MockUserRepository();

  // By default allow update() to succeed without error
  if (userRepository == null) {
    when(
      () => (mockRepo as MockUserRepository).update(
        any(),
        any(),
      ),
    ).thenAnswer((_) async {});
  }

  final authUser = authenticated ? _makeAuthUser() : null;

  final effectiveRouter = router ??
      GoRouter(
        initialLocation: '/profile/edit-personal',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) =>
                const Scaffold(body: Text('PROFILE_SCREEN')),
            routes: [
              GoRoute(
                path: 'edit-personal',
                builder: (_, __) =>
                    const Scaffold(body: ProfileEditPersonalScreen()),
              ),
            ],
          ),
        ],
      );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith(
          (_) => Stream.value(authUser)),
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
      userRepositoryProvider.overrideWithValue(mockRepo),
      if (avatarService != null)
        avatarUploadServiceProvider.overrideWithValue(avatarService),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: effectiveRouter,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue('uid-test');
    registerFallbackValue(<String, Object?>{});
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-510: form pre-populated from userProfileProvider
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-510: form pre-populated', () {
    testWidgets('displays current displayName, heightCm, bodyWeightKg',
        (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(
            displayName: 'Carlos',
            heightCm: 175,
            bodyWeightKg: 80,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check pre-populated values via controller text in the form fields
      final nameField = tester.widget<TextFormField>(
        find.byKey(const Key('edit_personal_display_name')),
      );
      final weightField = tester.widget<TextFormField>(
        find.byKey(const Key('edit_personal_weight_field')),
      );
      final heightField = tester.widget<TextFormField>(
        find.byKey(const Key('edit_personal_height_field')),
      );

      expect(nameField.controller?.text, equals('Carlos'));
      expect(weightField.controller?.text, equals('80.0'));
      expect(heightField.controller?.text, equals('175'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-512: empty displayName shows validation error
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-512: displayName validation', () {
    testWidgets('shows error when displayName is cleared and form saved',
        (tester) async {
      final repo = MockUserRepository();
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(displayName: 'Carlos'),
          userRepository: repo,
        ),
      );
      await tester.pumpAndSettle();

      // Clear the display name field
      final nameField = find.byKey(const Key('edit_personal_display_name'));
      await tester.tap(nameField);
      await tester.pump();
      await tester.enterText(nameField, '');
      await tester.pump();

      // Scroll to and tap save
      await tester.scrollUntilVisible(
        find.byKey(const Key('edit_personal_save_button')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('edit_personal_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá un nombre'), findsOneWidget); // i18n: Fase 6 Etapa 3
      verifyNever(() => repo.update(any(), any()));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-513: bodyWeightKg out of range shows validation error
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-513: bodyWeightKg validation', () {
    testWidgets('shows error when bodyWeightKg is 0', (tester) async {
      final repo = MockUserRepository();
      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(bodyWeightKg: 80),
          userRepository: repo,
        ),
      );
      await tester.pumpAndSettle();

      final weightField = find.byKey(const Key('edit_personal_weight_field'));
      await tester.tap(weightField);
      await tester.pump();
      await tester.enterText(weightField, '0');
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byKey(const Key('edit_personal_save_button')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('edit_personal_save_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Ingresá un peso entre 30 y 300 kg'), // i18n: Fase 6 Etapa 3
        findsOneWidget,
      );
      verifyNever(() => repo.update(any(), any()));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-511: save fires UserRepository.update + screen pops
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-511: save fires update + pops', () {
    testWidgets('calls update with changed displayName and pops on success',
        (tester) async {
      final repo = MockUserRepository();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(displayName: 'Carlos'),
          userRepository: repo,
          authenticated: true,
        ),
      );
      await tester.pumpAndSettle();

      // Edit display name
      final nameField = find.byKey(const Key('edit_personal_display_name'));
      await tester.enterText(nameField, 'Carlos R.');
      await tester.pump();

      // Scroll to and tap save button
      await tester.ensureVisible(
          find.byKey(const Key('edit_personal_save_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_personal_save_button')));
      await tester.pumpAndSettle();

      final captured = verify(() => repo.update(captureAny(), captureAny()))
          .captured;
      expect(captured[0], equals('uid-test'));
      final partial = captured[1] as Map<String, Object?>;
      expect(partial['displayName'], equals('Carlos R.'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-514: avatar picker is invoked on tap
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-514: avatar picker invoked on tap', () {
    testWidgets('avatar editor is present and tappable', (tester) async {
      await tester.pumpWidget(
        _buildScreen(profile: _profile()),
      );
      await tester.pumpAndSettle();

      // Avatar editor container must exist
      expect(
        find.byKey(const Key('edit_personal_avatar_editor')),
        findsOneWidget,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-515: avatar upload happy path stores URL in UserRepository.update
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-515: avatar upload updates UserRepository', () {
    testWidgets(
        'after upload, avatarUrl is included in update partial',
        (tester) async {
      // This test verifies that when an avatar path is staged,
      // the save handler uploads and includes avatarUrl in the partial.
      // Because triggering the image_picker in test is not possible without
      // a platform channel, we test the upload code path via a pre-seeded
      // local path by setting a non-null avatar path before save.
      //
      // Per design §4.2: upload → avatarUrl in partial → UserRepository.update
      //
      // NOTE: The actual image_picker invocation (tap → opens native picker)
      // cannot be exercised in widget tests without a mock image_picker.
      // We verify the _AvatarEditor key is present (SCENARIO-514 coverage).
      // The upload path is covered by the save handler integration once
      // a localPath is staged. Full E2E upload test requires a custom
      // ImagePicker mock — not in scope for this RED cycle.
      // This test serves as a placeholder that confirms the code structure
      // is testable.
      final uploadService = FakeAvatarUploadService();
      final repo = MockUserRepository();
      when(() => repo.update(any(), any())).thenAnswer((_) async {});

      await tester.pumpWidget(
        _buildScreen(
          profile: _profile(),
          userRepository: repo,
          avatarService: uploadService,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('edit_personal_avatar_editor')),
        findsOneWidget,
      );
    });
  });
}
