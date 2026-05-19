import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../feed/application/feed_screen_providers.dart';
import '../../feed/application/post_providers.dart';
import '../../feed/domain/post.dart';
import '../../feed/domain/post_privacy.dart';
import '../../feed/domain/routine_tag.dart';
import '../../profile/application/user_providers.dart';
import '../domain/session.dart';
import '../presentation/workout_strings.dart';

class PostWorkoutNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> shareWorkout(Session session) async {
    state = const AsyncLoading();
    try {
      final authUser = await ref.read(authStateChangesProvider.future);
      final profile = await ref.read(userProfileProvider.future);

      final post = Post(
        id: '',
        authorUid: authUser!.uid,
        authorDisplayName: profile?.displayName ?? '',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: WorkoutStrings.postAutoCompleteText,
        routineTag: RoutineTag(
          routineId: session.routineId,
          routineName: session.routineName,
        ),
        privacy: PostPrivacy.friends,
        createdAt: DateTime.now().toUtc(),
      );

      await ref.read(postRepositoryProvider).create(post);

      ref.invalidate(myFriendsFeedProvider);
      ref.invalidate(feedPublicProvider);

      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final postWorkoutNotifierProvider =
    AsyncNotifierProvider.autoDispose<PostWorkoutNotifier, void>(
  PostWorkoutNotifier.new,
);
