import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../domain/post.dart';
import '../domain/post_privacy.dart';
import 'feed_screen_providers.dart';
import 'post_providers.dart';

/// Maximum character count for a post (grapheme clusters).
const int kMaxPostChars = 280;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

@immutable
class CreatePostState {
  const CreatePostState({
    this.text = '',
    this.privacy = PostPrivacy.friends,
    this.isSubmitting = false,
    this.errorMessage,
  });

  final String text;
  final PostPrivacy privacy;
  final bool isSubmitting;
  final String? errorMessage;

  /// True when the post can be submitted: text is non-empty, within the char
  /// limit, and not already submitting.
  bool get canSubmit =>
      text.trim().isNotEmpty &&
      text.characters.length <= kMaxPostChars &&
      !isSubmitting;

  CreatePostState copyWith({
    String? text,
    PostPrivacy? privacy,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
  }) =>
      CreatePostState(
        text: text ?? this.text,
        privacy: privacy ?? this.privacy,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class CreatePostNotifier extends AsyncNotifier<CreatePostState> {
  @override
  Future<CreatePostState> build() async => const CreatePostState();

  void setText(String value) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(text: value, clearError: true));
  }

  void setPrivacy(PostPrivacy value) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(privacy: value, clearError: true));
  }

  /// Submits the post. Returns [true] on success, [false] on any failure.
  ///
  /// Failure cases:
  /// - `canSubmit == false` (text empty / over limit / already submitting)
  /// - viewer not authenticated
  /// - gym privacy selected but user has no gym
  /// - `PostRepository.create()` throws
  Future<bool> submit() async {
    final current = state.valueOrNull;
    if (current == null || !current.canSubmit) return false;

    // Mark as submitting immediately — prevents double-tap (SCENARIO-228)
    state = AsyncData(
      current.copyWith(isSubmitting: true, clearError: true),
    );

    // Auth gate
    final authUser = await ref.read(authStateChangesProvider.future);
    if (authUser == null) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'No pudimos publicar tu post. Iniciá sesión.',
        ),
      );
      return false;
    }

    // Profile read (for author fields + gym gate)
    final profile = await ref.read(userProfileProvider.future);

    // Gym gate (defense-in-depth — UI already disables the pill)
    if (current.privacy == PostPrivacy.gym && (profile?.gymId == null)) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'Asociate a un gym para postear acá.',
        ),
      );
      return false;
    }

    try {
      final post = Post(
        id: '',
        authorUid: authUser.uid,
        authorDisplayName: profile?.displayName ?? 'Anónimo',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: current.text.trim(),
        routineTag: null,
        privacy: current.privacy,
        createdAt: DateTime.now().toUtc(),
      );

      await ref.read(postRepositoryProvider).create(post);

      // Invalidate all 3 feed providers unconditionally (ADR-CP-006)
      ref.invalidate(myFriendsFeedProvider);
      ref.invalidate(feedPublicProvider);
      ref.invalidate(myGymFeedProvider);

      // Reset state
      state = const AsyncData(CreatePostState());
      return true;
    } catch (_) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'No pudimos publicar tu post. Intentá de nuevo.',
        ),
      );
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final createPostNotifierProvider =
    AsyncNotifierProvider<CreatePostNotifier, CreatePostState>(
  CreatePostNotifier.new,
);
