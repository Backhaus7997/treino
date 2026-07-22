import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/presentation/create_post_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockPostRepository extends Mock implements PostRepository {}

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserProfile _makeProfile({
  String uid = 'u1',
  String? displayName = 'Tincho',
  String? gymId,
  String? avatarUrl,
}) =>
    UserProfile(
      uid: uid,
      email: 'tincho@test.com',
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
      avatarUrl: avatarUrl,
    );

Routine _makeRoutine({String id = 'r1', String name = 'Push A'}) => Routine(
      id: id,
      name: name,
      level: ExperienceLevel.beginner,
      days: const [],
    );

/// Wraps [CreatePostScreen] in a GoRouter + ProviderScope.
///
/// The initial route is '/' which shows a button that pushes '/create'.
/// Call [_openCreatePost] after pumpWidget to navigate to the screen.
/// This ensures [context.pop()] has a valid previous route (mirrors real app).
Widget _wrapWithRouter({
  String? gymId,
  MockPostRepository? mockRepo,
  List<Routine> routines = const [],
}) {
  final MockPostRepository repo;
  if (mockRepo != null) {
    // Caller already configured all stubs — don't override them.
    repo = mockRepo;
  } else {
    repo = MockPostRepository();
    // Default stub: success.
    when(() => repo.create(any())).thenAnswer((inv) async {
      final post = inv.positionalArguments[0] as Post;
      return post.copyWith(id: 'generated-id');
    });
  }

  final user = _MockUser(uid: 'u1');
  final profile = _makeProfile(gymId: gymId);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => ctx.push('/create'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/create',
        builder: (_, __) => const Scaffold(body: CreatePostScreen()),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
      userProfileProvider.overrideWith((ref) => Stream.value(profile)),
      postRepositoryProvider.overrideWithValue(repo),
      myFriendsFeedProvider.overrideWith((ref) async => const []),
      feedPublicProvider.overrideWith((ref) async => const []),
      myGymFeedProvider.overrideWith((ref) async => null),
      userCreatedRoutinesProvider
          .overrideWith((ref, uid) => Stream.value(routines)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

/// Navigates to the CreatePostScreen (taps the 'open' button).
Future<void> _openCreatePost(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(
      Post(
        id: '',
        authorUid: 'u',
        authorAvatarUrl: null,
        authorGymId: null,
        text: 'fallback',
        routineTag: null,
        privacy: PostPrivacy.friends,
        createdAt: DateTime.utc(2026),
      ),
    );
  });

  // ── SCENARIO-220 — Form structure ─────────────────────────────────────────

  group('SCENARIO-220: form structure', () {
    testWidgets('SCENARIO-220: renders required form components',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter());
      await _openCreatePost(tester);

      expect(find.text('CANCELAR'), findsOneWidget);
      expect(find.text('NUEVO POST'), findsOneWidget);
      expect(find.text('PUBLICAR'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('AMIGOS'), findsOneWidget);
      expect(find.text('MI GYM'), findsOneWidget);
      expect(find.text('PÚBLICO'), findsOneWidget);
      expect(find.text('ETIQUETAR RUTINA'), findsOneWidget);
    });
  });

  // ── SCENARIO-222 — PUBLICAR disabled ─────────────────────────────────────

  group('SCENARIO-222: PUBLICAR disabled state', () {
    testWidgets('SCENARIO-222: PUBLICAR disabled when text empty',
        (tester) async {
      final repo = MockPostRepository();
      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.tap(find.text('PUBLICAR'), warnIfMissed: false);
      await tester.pumpAndSettle();

      verifyNever(() => repo.create(any()));
    });

    testWidgets('SCENARIO-222: PUBLICAR disabled for whitespace text',
        (tester) async {
      final repo = MockPostRepository();
      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      await tester.tap(find.text('PUBLICAR'), warnIfMissed: false);
      await tester.pumpAndSettle();

      verifyNever(() => repo.create(any()));
    });
  });

  // ── SCENARIO-223 — PUBLICAR enabled ──────────────────────────────────────

  group('SCENARIO-223: PUBLICAR enabled state', () {
    testWidgets('SCENARIO-223: PUBLICAR triggers submit when text has content',
        (tester) async {
      final repo = MockPostRepository();
      when(() => repo.create(any())).thenAnswer((inv) async {
        final post = inv.positionalArguments[0] as Post;
        return post.copyWith(id: 'gen');
      });

      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), 'Buena sesión!');
      await tester.pump();

      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      verify(() => repo.create(any())).called(1);
    });
  });

  // ── SCENARIO-221 — Char counter ──────────────────────────────────────────

  group('SCENARIO-221: char counter', () {
    testWidgets('SCENARIO-221: char counter is visible showing /280',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter());
      await _openCreatePost(tester);

      expect(find.textContaining('280'), findsWidgets);
    });

    testWidgets('SCENARIO-221: char counter updates as user types',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter());
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), 'Hola');
      await tester.pump();

      expect(find.text('4 / 280'), findsOneWidget);
    });
  });

  // ── SCENARIO-224 — Privacy default ───────────────────────────────────────

  group('SCENARIO-224: privacy default', () {
    testWidgets('SCENARIO-224: AMIGOS pill is rendered (default selection)',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter());
      await _openCreatePost(tester);

      expect(find.text('AMIGOS'), findsOneWidget);
      expect(find.text('MI GYM'), findsOneWidget);
      expect(find.text('PÚBLICO'), findsOneWidget);
    });
  });

  // ── SCENARIO-225 — Gym pill disabled when no gym ─────────────────────────

  group('SCENARIO-225: gym pill disabled', () {
    testWidgets('SCENARIO-225: helper text shown when gymId is null',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(gymId: null));
      await _openCreatePost(tester);

      expect(
        find.text('Asociate a un gym para postear acá'),
        findsOneWidget,
      );
    });

    testWidgets('SCENARIO-225: helper text absent when gymId is set',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(gymId: 'gym-123'));
      await _openCreatePost(tester);

      expect(
        find.text('Asociate a un gym para postear acá'),
        findsNothing,
      );
    });

    testWidgets(
        'SCENARIO-225: tapping gym pill when disabled does not call repo.create',
        (tester) async {
      final repo = MockPostRepository();
      await tester.pumpWidget(_wrapWithRouter(gymId: null, mockRepo: repo));
      await _openCreatePost(tester);

      await tester.tap(find.text('MI GYM'), warnIfMissed: false);
      await tester.pump();

      expect(find.text('MI GYM'), findsOneWidget);
      verifyNever(() => repo.create(any()));
    });
  });

  // ── SCENARIO-226 — Routine tag picker ────────────────────────────────────

  group('SCENARIO-226: routine tag picker', () {
    testWidgets('SCENARIO-226: routine chip shows ETIQUETAR RUTINA',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter());
      await _openCreatePost(tester);

      expect(find.text('ETIQUETAR RUTINA'), findsOneWidget);
    });

    testWidgets('SCENARIO-226: tapping the chip opens the routine picker',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(routines: [_makeRoutine(name: 'Push A')]),
      );
      await _openCreatePost(tester);

      await tester.tap(find.text('ETIQUETAR RUTINA'));
      await tester.pumpAndSettle();

      expect(find.text('ELEGÍ UNA RUTINA'), findsOneWidget);
      expect(find.text('Push A'), findsOneWidget);
    });

    testWidgets('SCENARIO-226: choosing a routine tags the post',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(routines: [_makeRoutine(name: 'Push A')]),
      );
      await _openCreatePost(tester);

      await tester.tap(find.text('ETIQUETAR RUTINA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push A'));
      await tester.pumpAndSettle();

      // Idle chip is replaced by the accent pill showing the routine name.
      expect(find.text('ETIQUETAR RUTINA'), findsNothing);
      expect(find.text('Push A'), findsOneWidget);
    });

    testWidgets('SCENARIO-226: chosen routine can be detached', (tester) async {
      await tester.pumpWidget(
        _wrapWithRouter(routines: [_makeRoutine(name: 'Push A')]),
      );
      await _openCreatePost(tester);

      await tester.tap(find.text('ETIQUETAR RUTINA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push A'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Quitar rutina etiquetada'));
      await tester.pumpAndSettle();

      expect(find.text('Push A'), findsNothing);
      expect(find.text('ETIQUETAR RUTINA'), findsOneWidget);
    });

    testWidgets('SCENARIO-226: empty state shown when user has no routines',
        (tester) async {
      await tester.pumpWidget(_wrapWithRouter(routines: const []));
      await _openCreatePost(tester);

      await tester.tap(find.text('ETIQUETAR RUTINA'));
      await tester.pumpAndSettle();

      expect(
        find.text('Todavía no tenés rutinas propias para etiquetar.'),
        findsOneWidget,
      );
    });
  });

  // ── SCENARIO-230 — CANCELAR pops without write ───────────────────────────

  group('SCENARIO-230: CANCELAR behavior', () {
    testWidgets('SCENARIO-230: CANCELAR pops without calling repo.create',
        (tester) async {
      final repo = MockPostRepository();
      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), 'Texto de prueba');
      await tester.pump();

      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();

      verifyNever(() => repo.create(any()));
      // Screen has popped — we're back at '/'
      expect(find.text('open'), findsOneWidget);
    });
  });

  // ── SCENARIO-228 — Submitting state ──────────────────────────────────────

  group('SCENARIO-228: submitting state', () {
    testWidgets(
        'SCENARIO-228: PUBLICAR shows spinner while submitting; CANCELAR enabled',
        (tester) async {
      final repo = MockPostRepository();
      final completer = Completer<Post>();
      when(() => repo.create(any())).thenAnswer((_) => completer.future);

      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), 'Buena sesión!');
      await tester.pump();

      // Tap PUBLICAR — triggers submit which hangs at repo.create
      await tester.tap(find.text('PUBLICAR'));
      // Pump several frames to let notifier set isSubmitting=true and widget rebuild
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // While submitting: spinner visible in the header (replaces PUBLICAR text)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // CANCELAR still present
      expect(find.text('CANCELAR'), findsOneWidget);
    });
  });

  // ── SCENARIO-229 — Error rendered inline ─────────────────────────────────

  group('SCENARIO-229: error inline', () {
    testWidgets('SCENARIO-229: error message shown inline after submit failure',
        (tester) async {
      final repo = MockPostRepository();
      when(() => repo.create(any())).thenThrow(Exception('Network fail'));

      await tester.pumpWidget(_wrapWithRouter(mockRepo: repo));
      await _openCreatePost(tester);

      await tester.enterText(find.byType(TextField), 'Buena sesión!');
      await tester.pump();

      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos publicar tu post. Intentá de nuevo.'),
        findsOneWidget,
      );
    });
  });
}
