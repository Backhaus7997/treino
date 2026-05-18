import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/create_post_notifier.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockPostRepository extends Mock implements PostRepository {}

class MockUser extends Mock implements User {
  MockUser({required String uid}) : _uid = uid;
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
  String? avatarUrl,
  String? gymId,
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

/// Builds a [ProviderContainer] with the notifier wired up.
ProviderContainer _makeContainer({
  String? uid = 'u1',
  UserProfile? Function()? profileFactory,
  MockPostRepository? mockRepo,
}) {
  final profile = profileFactory != null ? profileFactory() : _makeProfile();
  final repo = mockRepo ?? MockPostRepository();

  // Default stub: create succeeds
  when(() => repo.create(any())).thenAnswer((invocation) async {
    final post = invocation.positionalArguments[0] as Post;
    return post.copyWith(id: 'generated-id');
  });

  final user = uid != null ? MockUser(uid: uid) : null;

  return ProviderContainer(
    overrides: [
      authStateChangesProvider.overrideWith(
        (ref) => Stream.value(user),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(profile),
      ),
      postRepositoryProvider.overrideWithValue(repo),
      myFriendsFeedProvider.overrideWith((ref) async => const []),
      feedPublicProvider.overrideWith((ref) async => const []),
      myGymFeedProvider.overrideWith((ref) async => null),
    ],
  );
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

  // ── SCENARIO-222/223 — canSubmit / empty / whitespace ────────────────────

  group('CreatePostNotifier — canSubmit (SCENARIO-222, SCENARIO-223)', () {
    late ProviderContainer container;

    setUp(() => container = _makeContainer());
    tearDown(() => container.dispose());

    // SCENARIO-222: canSubmit is false for empty text
    test('SCENARIO-222: canSubmit false when text is empty', () async {
      await container.read(createPostNotifierProvider.future);

      expect(
        container.read(createPostNotifierProvider).valueOrNull?.canSubmit,
        isFalse,
      );
    });

    // SCENARIO-222: canSubmit is false for whitespace-only text
    test('SCENARIO-222: canSubmit false when text is whitespace only',
        () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('   ');
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.canSubmit,
        isFalse,
      );
    });

    // SCENARIO-223: canSubmit is true when text has non-whitespace content
    test('SCENARIO-223: canSubmit true with non-whitespace content', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.canSubmit,
        isTrue,
      );
    });
  });

  // ── SCENARIO-221 — char limit 280 ────────────────────────────────────────

  group('CreatePostNotifier — char limit (SCENARIO-221)', () {
    late ProviderContainer container;

    setUp(() => container = _makeContainer());
    tearDown(() => container.dispose());

    // SCENARIO-221: canSubmit true at exactly 280 chars
    test('SCENARIO-221: canSubmit true at exactly 280 chars', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('a' * kMaxPostChars);
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.canSubmit,
        isTrue,
      );
    });

    // SCENARIO-221: 281 chars → canSubmit false
    test('SCENARIO-221: canSubmit false at 281 chars', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('a' * (kMaxPostChars + 1));
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.canSubmit,
        isFalse,
      );
    });
  });

  // ── SCENARIO-224 — privacy default + setPrivacy ──────────────────────────

  group('CreatePostNotifier — setPrivacy (SCENARIO-224)', () {
    late ProviderContainer container;

    setUp(() => container = _makeContainer());
    tearDown(() => container.dispose());

    // SCENARIO-224: default privacy is friends
    test('SCENARIO-224: privacy defaults to PostPrivacy.friends', () async {
      await container.read(createPostNotifierProvider.future);

      expect(
        container.read(createPostNotifierProvider).valueOrNull?.privacy,
        PostPrivacy.friends,
      );
    });

    test('SCENARIO-224: setPrivacy updates state', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setPrivacy(PostPrivacy.public);
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.privacy,
        PostPrivacy.public,
      );
    });
  });

  // ── SCENARIO-227 — submit success path ───────────────────────────────────

  group('CreatePostNotifier — submit success (SCENARIO-227)', () {
    late ProviderContainer container;
    late MockPostRepository mockRepo;

    setUp(() {
      mockRepo = MockPostRepository();
      when(() => mockRepo.create(any())).thenAnswer((inv) async {
        final post = inv.positionalArguments[0] as Post;
        return post.copyWith(id: 'generated-id');
      });
      container = _makeContainer(mockRepo: mockRepo);
    });

    tearDown(() => container.dispose());

    // SCENARIO-227: submit calls postRepository.create, returns true
    test('SCENARIO-227: submit() returns true on success', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');
      final result = await notifier.submit();

      expect(result, isTrue);
      verify(() => mockRepo.create(any())).called(1);
    });

    // SCENARIO-227: after success state resets to default
    test('SCENARIO-227: state resets to default after submit success',
        () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');
      await notifier.submit();

      final state = container.read(createPostNotifierProvider).valueOrNull;
      expect(state?.text, '');
      expect(state?.errorMessage, isNull);
      expect(state?.isSubmitting, isFalse);
    });
  });

  // ── SCENARIO-231 — gym guard ──────────────────────────────────────────────

  group('CreatePostNotifier — gym guard (SCENARIO-231)', () {
    late ProviderContainer container;
    late MockPostRepository mockRepo;

    setUp(() {
      mockRepo = MockPostRepository();
      container = _makeContainer(
        profileFactory: () => _makeProfile(gymId: null),
        mockRepo: mockRepo,
      );
    });

    tearDown(() => container.dispose());

    // SCENARIO-231: gym privacy + no gymId → errorMessage + false, no create call
    test(
        'SCENARIO-231: submit with gym privacy and null gymId returns false with error',
        () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');
      notifier.setPrivacy(PostPrivacy.gym);
      final result = await notifier.submit();

      expect(result, isFalse);
      verifyNever(() => mockRepo.create(any()));
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.errorMessage,
        isNotNull,
      );
    });
  });

  // ── SCENARIO-229 — error path ─────────────────────────────────────────────

  group('CreatePostNotifier — error path (SCENARIO-229)', () {
    late ProviderContainer container;
    late MockPostRepository mockRepo;

    setUp(() {
      mockRepo = MockPostRepository();
      when(() => mockRepo.create(any())).thenThrow(Exception('Network error'));
      container = _makeContainer(mockRepo: mockRepo);
    });

    tearDown(() => container.dispose());

    // SCENARIO-229: PostRepository throws → errorMessage set, returns false
    test('SCENARIO-229: submit returns false and sets errorMessage on error',
        () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');
      final result = await notifier.submit();

      expect(result, isFalse);
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.errorMessage,
        isNotNull,
      );
      expect(
        container.read(createPostNotifierProvider).valueOrNull?.isSubmitting,
        isFalse,
      );
    });
  });

  // ── SCENARIO-228 — isSubmitting blocks double-tap ─────────────────────────

  group('CreatePostNotifier — isSubmitting guard (SCENARIO-228)', () {
    late ProviderContainer container;
    late MockPostRepository mockRepo;

    setUp(() {
      mockRepo = MockPostRepository();
      // Slow repo: never resolves during the test pump
      when(() => mockRepo.create(any()))
          .thenAnswer((_) => Future.delayed(const Duration(seconds: 10)));
      container = _makeContainer(mockRepo: mockRepo);
    });

    tearDown(() => container.dispose());

    // SCENARIO-228: while submitting, canSubmit is false (isSubmitting=true)
    test('SCENARIO-228: canSubmit false while isSubmitting', () async {
      final notifier = container.read(createPostNotifierProvider.notifier);
      await container.read(createPostNotifierProvider.future);

      notifier.setText('Buena sesión!');

      // Start submit without awaiting — it is slow
      // ignore: unawaited_futures
      notifier.submit();

      // Yield to allow state to update
      await Future<void>.delayed(Duration.zero);

      final state = container.read(createPostNotifierProvider).valueOrNull;
      expect(state?.isSubmitting, isTrue);
      expect(state?.canSubmit, isFalse);
    });
  });
}
