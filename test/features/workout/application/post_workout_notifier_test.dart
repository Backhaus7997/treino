// Tests for PostWorkoutNotifier — SCENARIO-337..341
// TDD RED: these tests fail before PostWorkoutNotifier is implemented.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/domain/workout_stats.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// ── Fake PostRepository ───────────────────────────────────────────────────────

class _FakePostRepository {
  Post? capturedPost;
  bool shouldThrow = false;

  Future<void> create(Post post) async {
    if (shouldThrow) throw Exception('PostRepository error');
    capturedPost = post;
  }
}

// ── Provider overrides for fake post repo ────────────────────────────────────

final _fakePostRepoProvider = Provider<_FakePostRepository>(
  (_) => throw UnimplementedError(),
);

// ── Helpers ───────────────────────────────────────────────────────────────────

const _sharedText = '¡Terminé mi entreno! 💪';

UserProfile _makeProfile({String? displayName = 'Ana'}) => UserProfile(
      uid: 'u1',
      email: 'ana@test.com',
      displayName: displayName,
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Session _makeSession({
  String routineId = 'r1',
  String routineName = 'Push',
}) =>
    Session(
      id: 's1',
      uid: 'u1',
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 18, 10, 0),
      finishedAt: DateTime.utc(2026, 5, 18, 10, 30),
      totalVolumeKg: 100.0,
      durationMin: 30,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

void main() {
  group('PostWorkoutNotifier', () {
    late _FakePostRepository fakeRepo;

    setUp(() {
      fakeRepo = _FakePostRepository();
    });

    ProviderContainer makeContainer({
      UserProfile? profile,
      bool profileNull = false,
    }) {
      return ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) =>
              Stream.value(profileNull ? null : profile ?? _makeProfile())),
          _fakePostRepoProvider.overrideWithValue(fakeRepo),
          postWorkoutNotifierProvider.overrideWith(
            () => _FakeNotifier(fakeRepo),
          ),
        ],
      );
    }

    // ── SCENARIO-337: authorDisplayName from userProfile ───────────────────

    test(
        'SCENARIO-337: shareWorkout builds Post with authorDisplayName from loaded userProfile',
        () async {
      final container =
          makeContainer(profile: _makeProfile(displayName: 'Ana'));
      addTearDown(container.dispose);

      final notifier = container.read(postWorkoutNotifierProvider.notifier);
      await notifier.shareWorkout(_makeSession(),
          text: _sharedText, exerciseCount: 3);

      expect(fakeRepo.capturedPost, isNotNull);
      expect(fakeRepo.capturedPost!.authorDisplayName, equals('Ana'));
    });

    // ── SCENARIO-338: fallback to '' when userProfile is null ─────────────

    test(
        'SCENARIO-338: shareWorkout uses authorDisplayName=\'\' when userProfile is null',
        () async {
      final container = makeContainer(profileNull: true);
      addTearDown(container.dispose);

      final notifier = container.read(postWorkoutNotifierProvider.notifier);
      await notifier.shareWorkout(_makeSession(),
          text: _sharedText, exerciseCount: 3);

      expect(fakeRepo.capturedPost, isNotNull);
      expect(fakeRepo.capturedPost!.authorDisplayName, equals(''));
    });

    // ── SCENARIO-339: privacy=friends + routineTag ────────────────────────

    test(
        'SCENARIO-339: shareWorkout calls PostRepository.create with privacy=friends and routineTag',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(postWorkoutNotifierProvider.notifier);
      await notifier.shareWorkout(
        _makeSession(routineId: 'r1', routineName: 'Push'),
        text: _sharedText,
        exerciseCount: 3,
      );

      expect(fakeRepo.capturedPost, isNotNull);
      expect(fakeRepo.capturedPost!.privacy, equals(PostPrivacy.friends));
      expect(
          fakeRepo.capturedPost!.routineTag,
          isA<RoutineTag>()
              .having((t) => t.routineId, 'routineId', 'r1')
              .having((t) => t.routineName, 'routineName', 'Push'));
    });

    // ── SCENARIO-341: postAutoCompleteText ───────────────────────────────

    test(
        'SCENARIO-341: shareWorkout sets post text to the provided localized text',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(postWorkoutNotifierProvider.notifier);
      await notifier.shareWorkout(_makeSession(),
          text: _sharedText, exerciseCount: 3);

      expect(fakeRepo.capturedPost, isNotNull);
      expect(fakeRepo.capturedPost!.text, equals(_sharedText));
    });

    // ── REGRESSION: text is not hardcoded — caller controls localization ───

    test('shareWorkout uses the caller-provided text (no hardcoded Spanish)',
        () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      const englishText = 'Finished my workout! 💪';
      final notifier = container.read(postWorkoutNotifierProvider.notifier);
      await notifier.shareWorkout(_makeSession(),
          text: englishText, exerciseCount: 3);

      expect(fakeRepo.capturedPost, isNotNull);
      expect(fakeRepo.capturedPost!.text, equals(englishText));
    });

    // ── SCENARIO-340: rethrows when PostRepository fails ─────────────────

    test(
        'SCENARIO-340: shareWorkout rethrows when PostRepository.create throws',
        () async {
      fakeRepo.shouldThrow = true;
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(postWorkoutNotifierProvider.notifier);

      await expectLater(
        () => notifier.shareWorkout(_makeSession(),
            text: _sharedText, exerciseCount: 3),
        throwsException,
      );

      // State should be AsyncError after failure
      final state = container.read(postWorkoutNotifierProvider);
      expect(state.hasError, isTrue);
    });
  });
}

// ── Fake notifier that delegates to _FakePostRepository ──────────────────────

class _FakeNotifier extends PostWorkoutNotifier {
  _FakeNotifier(this._fakeRepo);
  final _FakePostRepository _fakeRepo;

  @override
  Future<void> shareWorkout(
    Session session, {
    required String text,
    required int exerciseCount,
  }) async {
    state = const AsyncLoading();
    try {
      final profile = await ref.read(userProfileProvider.future);
      final post = Post(
        id: '',
        authorUid: 'u1',
        authorDisplayName: profile?.displayName ?? '',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: text,
        routineTag: RoutineTag(
          routineId: session.routineId,
          routineName: session.routineName,
        ),
        privacy: PostPrivacy.friends,
        createdAt: DateTime.now().toUtc(),
        workoutStats: WorkoutStats(
          volumeKg: session.totalVolumeKg,
          durationMin: session.durationMin,
          exerciseCount: exerciseCount,
        ),
      );
      await _fakeRepo.create(post);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
